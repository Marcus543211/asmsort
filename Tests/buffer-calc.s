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

    # Save the file id
    movq %rax, %r12

    # Call fstat
    movq $5, %rax
    movq %r12, %rdi
    movq $stat_buffer, %rsi
    syscall

    # Get the file size (in bytes)
    movq $stat_buffer, %r11
    movq 48(%r11), %r13 # The size has offset 48 in the stat struct

    # mmap'ing the file
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r13, %rsi # the length of the file
    movq $1, %rdx # Flags for PROT_READ
    movq $0x8002, %r10 # MAP_PRIVATE + MAP_POPULATE (read ahead)
    movq %r12, %r8 # The connected file
    movq $0, %r9 # The offset (from the start)
    syscall

    # Time to count how many lines there are
    # %rax is the start of the mmap'ed file
    movq $0, %rdx # Character count
    movq $0, %r14 # Line count
loop:
    cmpq %r13, %rdx
    jge loop_end
    movb (%rax, %rdx), %bl
    cmpb $'\n', %bl
    jne not_line
    incq %r14
not_line:
    incq %rdx
    jmp loop
loop_end:
    
    # Two 16-bits numbers per line, so 4 byte per line
    shlq $2, %r14 # multiply by 4

    # Allocation time!
    # Here there is the choice between brk and mmap.
    # I use mmap because for no reason.

    # mmap syscall
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r14, %rsi # allocate for each number
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    movq $34, %r10 # MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

