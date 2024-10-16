.section .data
nums: .byte 11, 1, 14, 8, 14, 15, 14, 13, 4, 3, 4, 7, 2, 12, 9, 4, 2, 9, 6, 9, 8, 1, 9, 4, 5, 1, 10, 11, 2, 4, 1, 11

buckets: .zero 16

result: .space 32

.section .text
.globl _start
_start:
    #popq %rax # Number of args
    #popq %rax # Path to program
    #popq %rax # Path to numbers

    # %rax is nums, A in the book
    movq $nums, %rax
    # %rbx is result, B in the book
    movq $result, %rbx
    # %rcx is buckets, C in the book
    movq $buckets, %rcx
    # %rdx is used as a counter

    # Count the occurance of each number
    movq $0, %rdx
count:
    cmpq $32, %rdx
    je count_end
    movzbq (%rax, %rdx), %r8 # %r8 = A[j]
    incb (%rcx, %r8) # C[r8]++
    incq %rdx
    jmp count
count_end:

    # Histogramify
    movq $1, %rdx
hist:
    cmpq $16, %rdx
    je hist_end
    movb -1(%rcx, %rdx), %r8b # %r8b = C[j-1]
    addb %r8b, (%rcx, %rdx) # C[j] += r8b
    incq %rdx
    jmp hist
hist_end:

    # Move to result
    movq $31, %rdx
move:
    cmpq $-1, %rdx
    je move_end
    movzbq (%rax, %rdx), %r8 # %r8 = A[j]
    movzbq (%rcx, %r8), %r9 # %r9 = C[%r8]
    decb (%rcx, %r8) # C[%r8]--
    movb %r8b, -1(%rbx, %r9) # B[%r9] = %r8b
    decq %rdx
    jmp move
move_end:

    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

