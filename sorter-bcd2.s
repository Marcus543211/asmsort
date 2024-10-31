.section .data

# Buffer for a call to fstat
statbuf:
    .space 144

# Space for the counting sort
countbuf:
    # A little more than is needed (206995)
    .space 206700 * 4

# Various constants for SIMD operations.
# Used when writing.
# TODO: Explain these here or in the code.
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

split:
    .long 0x090B0D0F
    .long 0x01030507
    .long 0x080A0C0E
    .long 0x00020406

compare:
    .long 0x10101010
    .long 0x10101010
    .long 0x10101010
    .long 0x10101010

.section .text
.globl _start
_start:
    # TODO: Handle errors, check for SIMD features.
    popq %rdi            # Pop no. args
    popq %rdi            # Pop path of program
    popq %rdi            # Pop path of file to sort

    # Open the file
    movq $2, %rax        # open syscall
                         # The path was pop'ed into %rdi
    movq $0, %rsi        # Open for reading
    syscall

    # Move fd to %r12
    movq %rax, %r12

    # We want the size of the file for
    # allocating a buffer and for mmap'ing the file.

    # Get file information
    movq $5, %rax        # fstat syscall
    movq %r12, %rdi      # The fd of our file
    movq $statbuf, %rsi  # A buffer for the result
    syscall

    # Extract the file size in bytes into %r13.
    # The buffer was populated by fstat.
    # The file size is a quadword at offset 48.
    movq statbuf + 48, %r13 

    # For efficency, I mmap the file
    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address
    movq %r13, %rsi      # Allocate the filesize
    addq $16, %rsi       # Allocate a little extra for reading too much
    movq $1, %rdx        # Only for reading (PROT_READ)
    movq $0x8002, %r10   # Flags: MAP_POPULATE + MAP_PRIVATE
    movq %r12, %r8       # The connected file
    movq $0, %r9         # The offset (just take everything)
    syscall

    # Move the address of the mmap'ed file to %r15
    movq %rax, %r15

    # Now that the file is mmap'ed, it can be closed.
    movq $3, %rax        # close syscall
    movq %r12, %rdi      # Our fd
    syscall

    # Allocation time!
    # We need somewhere to store the numbers after parsing.
    # Here there is the choice between brk and mmap.
    # I use mmap because for no particular reason.

    # The numbers will be stored in packed binary-coded decimal form (BCD)
    # with the size (count of digits) in the lower byte.
    # This is done for faster parsing and printing.

    # TODO: Write nicer
    # To allocate a buffer for the result, we need to know the size.
    # This can either be found exactly, e.g., by counting lines
    # or we can calculate the maximum needed space, which is faster.
    # Worst case, all digits are 1 decimal.
    # All numbers are followed by either \t or \n.
    # Thus the max count of numbers is: file size / 2.
    # Each number we store will take up 4 bytes.
    # TODO: Ignoring the stored size.
    # (5 digits taking up 1 nibble each = 20 bits, rounded up)
    # Thus the max size is: 2 * file size
    # Calculated here:
    movq %r13, %rbx      # Get the size of the file
    shl $1, %rbx         # Multiply by 2

    # Allocate space with mmap
    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address again
    movq %rbx, %rsi      # Allocate the maximum needed space
    movq $0b11, %rdx     # Read and write (PROT_READ + PROT_WRITE)
    # Flags: MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x22, %r10
    movq $-1, %r8        # The connected file (none)
    movq $0, %r9         # The offset (don't care)
    syscall

    # Move the address of the allocated space to %r14
    movq %rax, %r14

    # Parsing time!
    # We now have the file and a buffer for the result in memory.
    # Next step is converting the numbers from ASCII to packed BCD.

    # At this point:
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

    movq $0, %rsi # File counter
    movq $0, %rdi # Result counter
    movdqa select, %xmm2
    movdqa split, %xmm3
    movdqa compare, %xmm4
.p2align 4
start_of_number:
    movdqa %xmm4, %xmm1
    movdqu (%r15, %rsi), %xmm0
    pcmpgtb %xmm0, %xmm1
    pand %xmm2, %xmm0
    pand %xmm2, %xmm1
    pshufb %xmm3, %xmm0
    pshufb %xmm3, %xmm1
    movq %xmm0, %r8
    movq %xmm1, %r10
    punpckhqdq %xmm0, %xmm0
    punpckhqdq %xmm1, %xmm1
    movq %xmm0, %r9
    movq %xmm1, %r11
    shlq $4, %r9
    shlq $4, %r11
    orq %r9, %r8
    orq %r11, %r10
    # We now have the lower nibbles
    # Get the length of first number
aaa:
    bsrq %r10, %rcx
    subq $3, %rcx
    movq $64, %rdx
    subq %rcx, %rdx
    # Calculate the size
    movq %rdx, %rbx
    shrq $2, %rbx
    addq %rbx, %rsi
    subq $1, %rbx
    # Shift the bits
    movq %r8, %rax
    shrq %cl, %rax
    shlq $4, %rax
    movb %bl, %al
    movntil %eax, (%r14, %rdi, 4)
    movq %rdx, %rcx
    shlq %cl, %r8
    shlq %cl, %r10
    # For y
    bsrq %r10, %rcx
    subq $3, %rcx
    movq $64, %rdx
    subq %rcx, %rdx
    # Calculate the size
    movq %rdx, %rbx
    shrq $2, %rbx
    addq %rbx, %rsi
    subq $1, %rbx
    # Shift the bits
    movq %r8, %rax
    shrq %cl, %rax
    shlq $4, %rax
    movb %bl, %al
    movntil %eax, 4(%r14, %rdi, 4)

    addq $2, %rdi
    cmpq %rsi, %r13
    jg start_of_number

    # Calculate the count of pairs
    movq %rdi, %r12      # Count of numbers
    shrq $1, %r12        # Divided by 2

    # Sorting!

    # For counting sort we need a buffer to write into
    # Calculate the actual needed amount of memory
    movq %r12, %rbx      # Move count of pairs
    shlq $3, %rbx        # Count of pairs * 8 bytes

    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address
    movq %rbx, %rsi      # Allocate space for all the numbers
    movq $0b11, %rdx     # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8        # The connected file (none)
    movq $0, %r9         # The offset (don't care)
    syscall

    # Move allocated space to %r15
    # We don't need the file that was stored there anymore
    movq %rax, %r15

    # Move the buffer used for counting
    movq $countbuf, %r11

    # At this point:
    # %r11 = counting buffer, %r12 = count of pairs
    # %r13 = file size, %r14 = buffer, %r15 = buffer

    movq $0, %rcx
count_start:
    xorq %rax, %rax
    movl 4(%r14, %rcx, 8), %eax
    shrq $8, %rax
    addl $1, (%r11, %rax, 4)
    addq $1, %rcx
    cmpq %rcx, %r12
    jg count_start

    movq $0, %rax # Accumulator
    movq $0, %rcx
count_sum:
    addl (%r11, %rcx, 4), %eax
    movl %eax, (%r11, %rcx, 4)
    addq $1, %rcx
    cmpq $206699, %rcx
    jne count_sum
    
    movq $0, %rcx
    xorq %rax, %rax
    xorq %rdx, %rdx
move_num:
    movl 4(%r14, %rcx, 8), %eax
    shrq $8, %rax
    movl (%r11, %rax, 4), %edx
    movq (%r14, %rcx, 8), %rbx
    movq %rbx, -8(%r15, %rdx, 8)
    subq $1, (%r11, %rax, 4)
    addq $1, %rcx
    cmpq %rcx, %r12
    jne move_num

    # Allow us to write a little bit in front of the start
    movq %r13, %rbx
    addq $16, %rbx

    # Buffer for writing the ASCII to
    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address
    movq %rbx, %rsi      # Allocate the filesize
    movq $0b11, %rdx     # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8        # The connected file (none)
    movq $0, %r9         # The offset (don't care)
    syscall

    movq %rax, %r11

    # Printing time!

    # We iterate backwards over the numbers
    movq %r12, %r8 # Pair counter
    leaq -1(%r11, %rbx), %r9 # Output pointer
    movdqa shuffle_wide, %xmm2
    movdqa shift, %xmm3
    movdqa select, %xmm4
    movdqa shuffle_short, %xmm5
    movdqa conversion, %xmm6
.p2align 4
write_num:
    subq $1, %r8         # We read a pair at a time 
    jl end_writing       # Have we written all numbers?
    # Read a pair
    movq (%r15, %r8, 8), %xmm0 # Read a pair of numbers
    movzbq 4(%r15, %r8, 8), %rax # Read size of x
    movzbq (%r15, %r8, 8), %rbx # Read size of y
    # Bit shift every other digit (nibble)
    pshufb %xmm2, %xmm0
    vpsrlvd %xmm3, %xmm0, %xmm0
    # Clear the "upper nibbles"
    pand %xmm4, %xmm0
    # Move everything back, so y is in the lower dword and x in the upper.
    # Each digit will fill a byte.
    # And at the end of both x and y there will be space for \t or \n.
    pshufb %xmm5, %xmm0
    # Add 0x30 to each digit to convert to ascii.
    # Furthermore add in \t and \n.
    paddb %xmm6, %xmm0
    # Moving!
    movq %xmm0, -7(%r9)  # Move y (and \n with it)
    subq %rax, %r9       # Subtract y's size (not counting \n!)
    punpckhqdq %xmm0, %xmm0 # Set lower qword to upper qword
    movq %xmm0, -8(%r9)  # Move x (and \t) (notice -8 instead of -7)
    subq %rbx, %r9       # Subtract x's size.
    subq $2, %r9         # Count \t and \n
    # Repeat
    jmp write_num
end_writing:
    addq $1, %r9         # I don't know

print:
    movq $1, %rax        # write syscall
    movq $1, %rdi        # To stdout
    movq %r9, %rsi       # The buffer we've written to
    movq %r13, %rdx      # Which must have the same length as the file
    syscall

exit:
    # That's all folks!
    movq $60, %rax       # exit syscall
    movq $0, %rdi        # All went good
    syscall

