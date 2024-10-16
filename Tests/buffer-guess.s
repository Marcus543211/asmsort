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

    # Allocation time!
    # Here there is the choice between brk and mmap.
    # I use mmap because for no reason.

    # mmap syscall
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    # Get the file size (in bytes)
    movq $stat_buffer, %r11
    movq 48(%r11), %rsi # The size has offset 48 in the stat struct
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

