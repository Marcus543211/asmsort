.section .data
hello:
    .string "Hello World!\n"

new_stack:
    .space 0x10000
stack_top:

.section .text
.globl _start
_start:
    # The plan:
    # Start a new thread using clone (can't be bothered to clone3)
    # Print hello world
    # It should appear twice!
    # Profit
    # Exit

    # Using fork
    #movq $57, %rax
    #syscall

    # Using clone with seperate memory spaces
    #movq $56, %rax
    #movq $0, %rdi
    #movq $0, %rsi
    # And 3 more unimportant arguments
    #syscall

    # Using clone with shared memory space
    movq $56, %rax
    movq $0x00000100, %rdi # Flag CLONE_VM
    movq $stack_top, %rsi
    syscall

    pushq $42

    # Print hello world
    movq $1, %rax
    movq $1, %rdi
    movq $hello, %rsi
    movq $13, %rdx
    syscall

    # Quit
    movq $60, %rax
    movq $0, %rdi
    syscall

