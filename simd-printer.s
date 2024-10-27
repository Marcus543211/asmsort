.section .data
stat_buffer:
    .space 144

.p2align 4
shuffle_wide:
    .long 0xFF070605
    .long 0xFFFF0605
    .long 0xFF030201
    .long 0xFFFF0201

shift:
    .long 0x00000000
    .long 0x00000004
    .long 0x00000000
    .long 0x00000004

select:
    .long 0x0F0F0F0F
    .long 0x0F0F0F0F
    .long 0x0F0F0F0F
    .long 0x0F0F0F0F

shuffle_short:
    .long 0x0502FFFF
    .long 0xFF000401
    .long 0x0D0AFFFF
    .long 0xFF080C09

conversion:
    .long 0x30300000
    .long 0x0A303030
    .long 0x30300000
    .long 0x09303030

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
    shl $1, %rbx

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
    movzbq (%rbx, %rcx), %r8 # Read the next byte (zero extending)
    subq $48, %r8 # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    addq $1, %rcx # Increase counter
    shlq $4, %rax # Move 4 bits
    addq %r8, %rax # Add the new digit
.endm

    movq %r15, %rbx # Start of number in file
    movq $0, %rcx # Digit count in file
    leaq (%r15, %r13), %rdi # End of file
    movq $0, %rdx # Result counter
.p2align 4
start_of_number:
    movzbq (%rbx), %rax # Next digit into %rax, clearing it
    movq $1, %rcx
    subq $48, %rax # Convert from ASCII to value
    parse_digit # 2nd digit
    parse_digit # 3rd digit
    parse_digit # 4th digit
    parse_digit # 5th digit
    # We can safely assume the next char is \t or \n since
    # no number is longer than 5 digits (max 32767).
end_of_number:
    # Save the count of digits in the lower byte
    shlq $8, %rax
    addq %rcx, %rax
    # Save the number
    #movl %eax, (%r14, %rdx, 4)
    movntil %eax, (%r14, %rdx, 4)
    addq $1, %rcx # Count the \t or \n
    addq %rcx, %rbx
    addq $1, %rdx # Increase the counter
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n
    cmpq %rbx, %rdi
    # We just read a tab or newline so the next character must be a digit.
    # We've also just ended a number so %ax is free.
    jg start_of_number
end_parsing:

    # Move the count of numbers
    movq %rdx, %r12

    # At this point:
    # %r12 = count of numbers (not pairs)
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

    # Calculate the actual needed amount of memory
    movq %r12, %rbx
    shlq $2, %rbx # Count of numbers * 4 bytes

    # Allow us to write a little bit in front of the start
    movq %r13, %rbx
    addq $16, %rbx

    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %rbx, %rsi # Allocate the filesize
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    movq %rax, %r11

    # Printing time!

    # We iterate backwards over the numbers
    movq %r12, %r8 # Number counter
    leaq -1(%r11, %rbx), %r9 # Output pointer
    movdqa shuffle_wide, %xmm2
    movdqa shift, %xmm3
    movdqa select, %xmm4
    movdqa shuffle_short, %xmm5
    movdqa conversion, %xmm6
.p2align 4
write_num:
    subq $2, %r8 # Have we written all numbers?
    jl end_writing
    # Get the numbers into ascii from BCD
    movq (%r14, %r8, 4), %xmm0
    movzbq 4(%r14, %r8, 4), %rax
    movzbq (%r14, %r8, 4), %rbx
    pshufb %xmm2, %xmm0
    vpsrlvd %xmm3, %xmm0, %xmm0
    pand %xmm4, %xmm0
    pshufb %xmm5, %xmm0
    paddb %xmm6, %xmm0
    # Moves: n1, \t, n2, \n
    movq %xmm0, -7(%r9)
    subq %rax, %r9
    punpckhqdq %xmm0, %xmm0
    movq %xmm0, -8(%r9) # One more than before to count \t
    subq %rbx, %r9
    subq $2, %r9 # Count \t and \n
    # Repeat
    jmp write_num
end_writing:
    addq $1, %r9

print:
    movq $1, %rax
    movq $1, %rdi
    movq %r9, %rsi
    movq %r13, %rdx
    syscall

exit:
    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

