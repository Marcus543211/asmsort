.section .data
reverse: .quad 0x08090A0B0C0D0E0F, 0x0001020304050607
to_num: .quad 0x3030303030303030, 0x3030303030303030
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

    # Parse the numbers of the file
    movq $0, %rcx # File counter
    movq $0, %rbx # Result counter
    movq $0, %rax # Current number
    movq $10, %r8 # Just 10 for multiplication
    movdqu reverse, %xmm0
    movdqu to_num, %xmm1
parse_loop:
    cmp %rcx, %r13 # Have we read the entire file?
    jle parse_loop_end
    movdqu (%r15, %rcx), %xmm2
    pshufb %xmm0, %xmm2
    psubw %xmm1, %xmm2

    movzbw (%r15, %rcx), %r9w # Read the next byte (zero extending)
    incq %rcx # Increase counter
    cmpw $0x20, %r9w # Both tab and newline are below 0x20 (space)
    jle end_number
parse_digit:
    subw $48, %r9w # Convert the ASCII digit to its value
    mulw %r8w # %ax *= 10
    addw %r9w, %ax # Add the new digit
    jmp parse_loop
end_number:
    movw %ax, (%r14, %rbx, 2) # Move the result to the buffer
    incq %rbx # Increase the counter
    movq $0, %rax # Reset the number
    jmp parse_loop
parse_loop_end:

    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

