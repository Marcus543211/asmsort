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

    # !!!
    movq %r13, %rbx
    shl $1, %rbx

    # For efficency, I mmap the file
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %rbx, %rsi # Allocate the filesize (double!!!)
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

    # Allocate space with mmap
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %rbx, %rsi # Allocate the filesize (double!!!)
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
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

    # The loop is unrolled for performance.
    # This macro helps bring down the repetition.
.macro parse_digit # !!!
    movzbq (%r15, %rcx), %r8 # Read the next byte (zero extending)
    addq $1, %rcx # Increase counter
    subq $48, %r8 # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    shlq $4, %rax # Move 4 bits
    addq %r8, %rax # Add the new digit
.endm

    movq $0, %rcx # File counter
    movq $0, %rdx # Result counter
.align 16
start_of_number:
    movzbq (%r15, %rcx), %rax # Next digit into %rax, clearing it
    addq $1, %rcx
    subq $48, %rax # Convert from ASCII to value
    parse_digit # 2nd digit
    parse_digit # 3rd digit
    parse_digit # 4th digit
    parse_digit # 5th digit
    # We can safely assume the next char is \t or \n since
    # no number is longer than 5 digits (max 32767).
    addq $1, %rcx # Count the \t or \n
    # Normally when jumping it has been counted
end_of_number:
    movntil %eax, (%r14, %rdx, 4)
    #movl %eax, (%r14, %rdx, 4)
    addq $1, %rdx # Increase the counter
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n
    cmpq %rcx, %r13
    # We just read a tab or newline so the next character must be a digit.
    # We've also just ended a number so %ax is free.
    jg start_of_number

    # Move the count of numbers
    movq %rdx, %r12

    # At this point:
    # %r12 = count of numbers (not pairs)
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

    # Calculate the actual needed amount of memory
    movq %r12, %rbx
    shlq $2, %rbx # Count of numbers * 4 bytes

    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %rbx, %rsi # Allocate the filesize (double!!!)
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    movq %rax, %r11

    # Printing time!
.macro write_digit
    movq %rax, %rdx
    andq $0xf, %rdx
    addq $48, %rdx
    movb %dl, (%r9) # Write next digit
    subq $1, %r9
    shrq $4, %rax
    je write_num
.endm

    # We iterate backwards over the numbers
    movq %r12, %r8 # Number counter
    leaq -1(%r11, %r13), %r9 # Output pointer
.align 16
write_num:
    subq $1, %r8 # Have we written all numbers?
    jl end_writing
    #xor %rax, %rax
    movl (%r14, %r8, 4), %eax
    testq $1, %r8 # Is even?
    jz tab # Jump if even
    movb $'\n', (%r9)
    jmp end_seperator
tab:
    movb $'\t', (%r9)
end_seperator:
    subq $1, %r9
    write_digit # 1
    write_digit # 2
    write_digit # 3
    write_digit # 4
    write_digit # 5
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

