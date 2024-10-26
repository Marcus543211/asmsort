.section .data
stat_buffer: .space 144

.section .text
.globl _start
_start:
    popq %rdi # Pop no. args
    popq %rdi # Pop path of program
    popq %rdi # Pop path of file to sort

    # Open the file
    movq $2, %rax
    # The path was pop'ed into %rdi
    movq $0, %rsi
    syscall

    # Move fd to %r12
    movq %rax, %r12

    # We want the size of the file for allocating a buffer
    # and for mmap'ing the file.

    # Call fstat
    movq $5, %rax
    movq %r12, %rdi
    movq $stat_buffer, %rsi
    syscall

    # Extract the file size in bytes into %r13.
    # The buffer was populated by fstat.
    # The size is a quadword at offset 48.
    movq stat_buffer + 48, %r13 

    # For efficency, I mmap the file
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r13, %rsi # Allocate the filesize
    movq $1, %rdx # Flags for PROT_READ
    movq $0x8002, %r10 # MAP_POPULATE + MAP_PRIVATE
    movq %r12, %r8 # The connected file
    movq $0, %r9 # The offset (just take everything)
    syscall

    # Move the address of the mmap'ed file to %r15
    movq %rax, %r15

    # Now that the file is mmap'ed, it can be closed.
    
    # close syscall
    movq $3, %rax
    movq %r12, %rdi
    syscall

    # Allocation time!
    # We need somewhere to store the numbers after parsing.
    # Here there is the choice between brk and mmap.
    # I use mmap because for no reason.

    # !!!
    movq %r13, %rbx
    shl $2, %rbx

    # Allocate space with mmap
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %rbx, %rsi # Allocate the filesize (double!!!)
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    #movq $0x8022, %r10
    movq $0x22, %r10 # No MAP_POPULATE
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    # Move the address of the allocated space to %r14
    movq %rax, %r14

    # Parsing time!
    # We now have the file and a buffer for the result in memory.
    # Next step is converting the numbers from ASCII to binary.

    # At this point:
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

.macro parse_num len
    addq $\len + 1, %rbx
    shlq $64 - 8*(\len+1), %rax
    addq $64 - 8*(\len+1), %rax
    movntiq %rax, (%r14, %rdx, 8)
    addq $1, %rdx
    cmpq %rbx, %r13
    jg start_of_number
    jmp parse_end
.endm

    movq $0, %rbx # File counter
    movq $0, %rdx # Result counter
    movq $0x30, %rcx
    shlq $32, %rcx
.align 16
start_of_number:
    movq (%r15, %rbx), %rax # Next digit into %rax, clearing it
    testq $0x3000, %rax
    jz digit_1
    testq $0x300000, %rax
    jz digits_2
    testq $0x30000000, %rax
    jz digits_3
    testq %rcx, %rax
    jz digits_4
    parse_num 5
.align 16
digits_4:
    parse_num 4
.align 16
digits_3:
    parse_num 3
digits_2:
    parse_num 2
digit_1:
    parse_num 1
parse_end:
    
    # Move the count of numbers
    movq %rdx, %r12

    # At this point:
    # %r12 = count of numbers (not pairs)
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

    # Allocate memory for printing
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r13, %rsi # Allocate the filesize
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    movq %rax, %r11

    # Printing time!
    movq $0, %r8 # Number counter
    movq $0, %r9 # Output counter
.align 16
write_num:
    movq (%r14, %r8, 8), %rax
    addq $1, %r8
    movzbq %al, %rcx
    shrq %cl, %rax
    shrq $3, %rcx
    movq %rax, (%r11, %r9)
    addq $8, %r9
    subq %rcx, %r9
    #leaq 8(%r9, %rcx, -1), %r9
    cmpq %r12, %r8 # Have we written all numbers?
    jl write_num
end_writing:

print:
    movq $1, %rax
    movq $1, %rdi
    movq %r11, %rsi
    movq %r13, %rdx
    syscall

exit:
    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

