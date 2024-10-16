.section .data
stat_buffer: .space 144

.section .text
.globl _start
_start:
    popq %rdi # Pop no. args
    popq %rdi # Pop path of prog.
    popq %rdi # Pop arg. path

    # Open the file
    movq $2, %rax
    # %rdi was pop'ed
    movq $0, %rsi
    syscall

    # Move fd to %r12
    movq %rax, %r12

    # Call fstat
    movq $5, %rax
    movq %r12, %rdi
    movq $stat_buffer, %rsi
    syscall

    # Extract the file size in bytes into %r13
    movq $stat_buffer, %rax # The buffer was populated by fstat
    movq 48(%rax), %r13 # The size is a quadword at offset 48.

    # Allocation time!
    # We need somewhere to store the numbers after parsing.
    # Here there is the choice between brk and mmap.
    # I use mmap because for no reason.

    # Allocate space with mmap
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r13, %rsi # Allocate the filesize
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    # Move allocated space (A) to %r14
    movq %rax, %r14

    # For efficency, I mmap the file
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r13, %rsi # Allocate the filesize
    addq $16, %rsi # Plus a little bit for reading ahead
    movq $1, %rdx # Flags for PROT_READ
    movq $0x8002, %r10 # MAP_POPULATE + MAP_PRIVATE
    movq %r12, %r8 # The connected file
    movq $0, %r9 # The offset (just take everything)
    syscall

    # Move mmap'ed file to %r15
    movq %rax, %r15

    # At this point:
    # %r12 = fd, %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

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
    xorq %rax, %rax
    xorq %rdx, %rdx
    movzbq (%r15, %rcx), %r8
    movzbq 1(%r15, %rcx), %r9
    movzbq 2(%r15, %rcx), %r10
    movzbq 3(%r15, %rcx), %r11
    # Increase file counter, one for each digit read.
    addq $4, %rcx
    # Subtraction with handlers for \t and \n.
    subw $48, %r8w # The first digit must always be a number so no jump.
    subw $48, %r9w
    subw $48, %r10w
    subw $48, %r11w
    js three_digits
    # "Make space" for the digit before
    imulw $10, %r8w, %ax
    imulw $10, %r10w, %dx
    # Add the previous digit
    addw %r9w, %ax
    addw %r11w, %dx
    js two_digits
    # "Make space" again
    imulw $100, %ax, %ax
    # Add to get final result
    addw %dx, %ax
    js one_digit
last_digit:
    movzbq (%r15, %rcx), %r9 # Read the next byte (zero extending)
    addq $1, %rcx # Increase counter
    subw $48, %r9w # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    imulw $10, %ax, %ax
    addw %r9w, %ax # Add the new digit
    # We can safely assume the next char is \t or \n since
    # no number is longer than 5 digits (max 32767).
    addq $1, %rcx # Count the \t or \n
    # Normally when jumping it has been counted
end_of_number:
    movw %ax, (%r14, %rbx, 2)
    addq $1, %rbx # Increase the result counter
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n
    cmpq %rcx, %r13
    # We just read a tab or newline so the next character must be a digit.
    # We've also just ended a number so %ax is free.
    jg start_of_number
    jmp parse_loop_end
one_digit:
    movw %r8w, %ax
    # When reading, two numbers too much were read.
    subq $2, %rcx
    jmp end_of_number
two_digits:
    subq $1, %rcx
    jmp end_of_number
three_digits:
    imulw $100, %r8w, %ax
    imulw $10, %r9w, %dx
    addw %dx, %ax
    addw %r10w, %ax
    jmp end_of_number
parse_loop_end:

    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

