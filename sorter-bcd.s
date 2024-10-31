.section .data

# Buffer for a call to fstat
stat_buf:
    .space 144

# Space for the radix sort
.p2align 4
count_buf_high:
    # A little more than is needed (887)
    .space 900 * 4
count_buf_low:
    # A little more than is needed (154)
    .space 160 * 4

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
    movq $stat_buf, %rsi  # A buffer for the result
    syscall

    # Extract the file size in bytes into %r13.
    # The buffer was populated by fstat.
    # The file size is a quadword at offset 48.
    movq stat_buf + 48, %r13 

    # For efficency, I mmap the file
    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address
    movq %r13, %rsi      # Allocate the filesize
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

    # TODO: Write nicer (maybe just delete and write in report)
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

    # The loop is unrolled for performance.
    # This macro helps bring down the repetition.
.macro parse_digit
    movzbq (%rbx, %rcx), %r8 # Read the next byte (zero extending)
    subq $48, %r8        # Convert the ASCII digit to its value
    js end_of_number     # Jump if sign is negative (\n or \t)
    addq $1, %rcx        # Increase counter
    shlq $4, %rax        # Move 4 bits for the new digit
    addq %r8, %rax       # Add the new digit
.endm

    movq %r15, %rbx      # Start of number in file
    movq $0, %rcx        # Digits parsed
    leaq (%r15, %r13), %rdi # End of file
    movq $0, %rdx        # Result counter
.p2align 4
start_of_number:
    movzbq (%rbx), %rax  # First digit into %rax, clearing it
    movq $1, %rcx        # Reset digit counter to 1
    subq $48, %rax       # Convert from ASCII to value
    parse_digit          # 2nd digit
    parse_digit          # 3rd digit
    parse_digit          # 4th digit
    parse_digit          # 5th digit
    # We can safely assume the next character is \t or \n since
    # no number is longer than 5 digits (max 32767).
end_of_number:
    # Save the count of digits in the lower byte
    shlq $8, %rax        # Shift out of the lower byte
    addq %rcx, %rax      # And save the count there
    # Save the number
    movl %eax, (%r14, %rdx, 4) # Non-temporal hint
    addq $1, %rdx        # Increase the counter
    addq $1, %rcx        # Count the \t or \n we read
    addq %rcx, %rbx      # Move to the start of the next number
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n.
    cmpq %rbx, %rdi
    # If we aren't done, jump back to the start.
    # We just read a tab or newline so the next character must be a digit.
    jg start_of_number
end_parsing:

    # Calculate the count of pairs
    movq %rdx, %r12      # Count of numbers
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
    movq $count_buf_high, %r10
    movq $count_buf_low, %r11

    # At this point:
    # %r10 = counting high, %r11 = counting low,
    # %r12 = count of pairs, %r13 = file size
    # %r14 = numbers, %r15 = buffer for sorting

    # Count the numbers, iterating backwards
    leaq -1(%r12), %rcx
count_start:
    movzwq 6(%r14, %rcx, 8), %rax
    movzbq 5(%r14, %rcx, 8), %rbx
    addl $1, (%r10, %rax, 4)
    addl $1, (%r11, %rbx, 4)
    subq $1, %rcx
    jns count_start

    # Calculate the running sum for the lower part
    movq $0, %rax # Accumulator
    movq $0, %rcx
count_sum1:
    addl (%r11, %rcx, 4), %eax
    movl %eax, (%r11, %rcx, 4)
    addq $1, %rcx
    cmpq $160, %rcx
    jl count_sum1
 
    # Move the numbers based on the lower part
    leaq -1(%r12), %rcx
    xorq %rdx, %rdx
move_num1:
    movzbq 5(%r14, %rcx, 8), %rbx
    movq (%r14, %rcx, 8), %rax
    movl (%r11, %rbx, 4), %edx
    movq %rax, -8(%r15, %rdx, 8)
    subq $1, (%r11, %rbx, 4)
    subq $1, %rcx
    jns move_num1

    # Calculate the running sum for the higher part
    movq $0, %rax # Accumulator
    movq $0, %rcx
count_sum2:
    addl (%r10, %rcx, 4), %eax
    movl %eax, (%r10, %rcx, 4)
    addq $1, %rcx
    cmpq $900, %rcx
    jl count_sum2

    # Move the numbers based on the higher part
    leaq -1(%r12), %rcx
    xorq %rdx, %rdx
move_num2:
    movzwq 6(%r14, %rcx, 8), %rbx
    movq (%r14, %rcx, 8), %rax
    movl (%r10, %rbx, 4), %edx
    movq %rax, -8(%r15, %rdx, 8)
    subq $1, (%r10, %rbx, 4)
    subq $1, %rcx
    jns move_num2

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

