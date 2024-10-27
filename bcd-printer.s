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
.align 4
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
.macro write_digit
    movb %al, %dl
    addq $1, %rdi
    shrq $4, %rax
    jz write_num_write
    shlq $8, %rdx
.endm

.macro show_num size
    .rept (\size - 1)
    movb %al, %dl
    shrq $4, %rax
    shlq $8, %rdx
    .endr
    movb %al, %dl
    shrq $4, %rax

    andq %rdi, %rdx
    addq %rsi, %rdx
    shlq $(64-8*\size), %rdx
    movq %rdx, -7(%r9)
    subq $\size, %r9
    jmp write_num
.endm

    # We iterate backwards over the numbers
    movq %r12, %r8 # Number counter
    leaq -1(%r11, %rbx), %r9 # Output pointer
    movabsq $0x0F0F0F0F0F0F0F0F, %rdi
    movabsq $0x0000003030303030, %rsi
.align 4
write_num:
    subq $1, %r8 # Have we written all numbers?
    jl end_writing
    # Write either \n or \t
    testq $1, %r8 # Is even?
    jz tab # Jump if even
    movb $'\n', (%r9)
    jmp end_seperator
tab:
    movb $'\t', (%r9)
end_seperator:
    subq $1, %r9
    # Read number
    xorq %rax, %rax
    movl (%r14, %r8, 4), %eax
    # Extract count of digits
    movzbq %al, %rbx
    shrq $8, %rax
    # Jump correctly
    cmpq $5, %rbx
    je digits_5
    cmpq $4, %rbx
    je digits_4
    cmpq $3, %rbx
    je digits_3
    cmpq $2, %rbx
    je digits_2
    cmpq $1, %rbx
    je digits_1
.align 4
digits_5:
    show_num 5
.align 4
digits_4:
    show_num 4
.align 4
digits_3:
    show_num 3
.align 4
digits_2:
    show_num 2
.align 4
digits_1:
    show_num 1
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

