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

    # Parse the numbers of the file
    movq $0, %rcx # File counter
    movq $0, %rbx # Result counter
    # %r8 is used for the final number
.align 16
start_of_number:
    # Idea: most numbers are either 4 or 5 digit.
    # Only 1000 / 32767 = ~3% are not.
    # Therefore optimizing for these make sense
    # and here instruction level parallelism might help.
    # Essentially the code is written for 4 and 5 digit numbers
    # with 1, 2, and 3 digit numbers getting second class treatment.

    # When mmap'ing the file, extra space was reserved
    # so this should never read outside the allocated memory.
    movzbq (%r15, %rcx), %r8
    movzbq 1(%r15, %rcx), %r9
    movzbq 2(%r15, %rcx), %r10
    movzbq 3(%r15, %rcx), %r11
    # Increase file counter, one for each digit read.
    addq $4, %rcx
    # Subtraction with handlers for \t and \n.
    subq $48, %r8 # The first digit must always be a number so no jump.
    subq $48, %r9
    js one_digit
    subq $48, %r10
    subq $48, %r11
    js three_digits
    # "Make space" for the digit before
    shlq $4, %r8
    shlq $4, %r10
    # Add the previous digit
    addq %r9, %r8
    addq %r11, %r10
    js two_digits
    # "Make space" again
    shlq $8, %r8
    # Add to get final result
    addq %r10, %r8
last_digit:
    movzbq (%r15, %rcx), %r9 # Read the next byte (zero extending)
    addq $1, %rcx # Increase counter
    subq $48, %r9 # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    shlq $4, %r8
    addq %r9, %r8 # Add the new digit
    # We can safely assume the next char is \t or \n since
    # no number is longer than 5 digits (max 32767).
    addq $1, %rcx # Count the \t or \n
    # Normally when jumping it has been counted
end_of_number:
    movl %r8d, (%r14, %rbx, 4)
    addq $1, %rbx # Increase the result counter
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n
    cmpq %rcx, %r13
    # We just read a tab or newline so the next character must be a digit.
    # We've also just ended a number so %ax is free.
    jg start_of_number
    jmp parse_loop_end
one_digit:
    # When reading, two numbers too much were read.
    subq $2, %rcx
    jmp end_of_number
two_digits:
    subq $1, %rcx
    jmp end_of_number
three_digits:
    shlq $8, %r8
    shlq $4, %r9
    addq %r9, %r8
    addq %r10, %r8
    jmp end_of_number
parse_loop_end:

    # Move the count of numbers
    movq %rbx, %r12

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

