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
    movq $1, %rdx # Flags for PROT_READ
    movq $0x8002, %r10 # MAP_POPULATE + MAP_PRIVATE
    movq %r12, %r8 # The connected file
    movq $0, %r9 # The offset (just take everything)
    syscall

    # Move mmap'ed file to %r15
    movq %rax, %r15

    # At this point:
    # %r12 = fd, %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

.macro parse_digit
    movzbq (%r15, %rcx), %r9 # Read the next byte (zero extending)
    addq $1, %rcx # Increase counter
    subw $48, %r9w # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    imulw $10, %ax, %ax
    addw %r9w, %ax # Add the new digit
.endm

    # Parse the numbers of the file
    movq $0, %rcx # File counter
    movq $0, %rbx # Result counter
.align 16
start_of_number:
    movzbq (%r15, %rcx), %rax # Next digit into %rax, clearing it
    addq $1, %rcx
    subb $48, %al # Convert from ASCII to value
    parse_digit
    parse_digit
    parse_digit
    parse_digit
    # We can safely assume the next char is \t or \n since
    # no number is longer than 5 digits (max 32767).
    addq $1, %rcx # Count the \t or \n
    # Normally when jumping it has been counted
end_of_number:
    movw %ax, (%r14, %rbx, 2)
    addq $1, %rbx # Increase the counter
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n
    cmpq %rcx, %r13
    # We just read a tab or newline so the next character must be a digit.
    # We've also just ended a number so %ax is free.
    jg start_of_number
parse_loop_end:

    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

