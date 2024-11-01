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

    # Open the file.
    movq $2, %rax        # open syscall
                         # The path was pop'ed into %rdi
    movq $0, %rsi        # Open for reading
    syscall

    # Move fd.
    movq %rax, %r12

    # We want the size of the file for allocating a buffer
    # and for mmap'ing the file.
    movq %r12, %rdi
    call getFileSize

    # Move file size.
    movq %rax, %r13

    # Allocation time!
    # We need somewhere to store the numbers after parsing.
    # The numbers will be stored in packed binary-coded decimal form (BCD)
    # with the size (count of digits) in the lower byte.
    # This is done for faster parsing and printing.

    # Calculate the maximum needed amount of memory.
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

    # Move the address of the allocated space.
    movq %rax, %r14

    # Parsing time!
    movq %r12, %rdi
    movq %r13, %rsi
    movq %r14, %rdx
    call parseFile

    # Move the count of coordinates.
    movq %rax, %r15

    # Sorting!
    movq %r14, %rdi
    movq %r15, %rsi
    call radixSort

    # Printing time!
    movq %rax, %rdi
    movq %r15, %rsi
    movq %r13, %rdx
    call print

exit:
    # That's all folks!
    movq $60, %rax       # exit syscall
    movq $0, %rdi        # All went good
    syscall


# int getFileSize(int fd)
#     Returns the size in bytes of the file.
.type getFileSize, @function
getFileSize:
    # Get file information.
    movq $5, %rax        # fstat syscall
                         # The fd of our file is already in %rdi
    movq $stat_buf, %rsi # A buffer for the result
    syscall

    # Extract the file size into %rax.
    # The buffer was populated by fstat.
    # The file size is a quadword at offset 48.
    movq stat_buf + 48, %rax
    ret


# int parseFile(int fd, int size, int* result)
#     Parses the coordinates in the file.
#     Returns the number of coordinates in the file.
#     The parsed numbers are 32-bit and stored in packed BCD with
#     their least significant byte being the count of digits in the number.
#     'fd': file descriptor of the file to read.
#     'size': the size of the file in bytes.
#     'result': the address to store the numbers to.
.type parseFile, @function
parseFile:
    pushq %rsi           # Save the file size
    pushq %rdx           # Save the result buffer

    # For efficency, I mmap the file.
    # (The arguments are a little out of order)
    movq $9, %rax        # mmap syscall
    movq %rdi, %r8       # The connected file
    movq $0, %rdi        # Let the kernel choose the address
                         # Allocate the filesize (already in %rsi)
    movq $1, %rdx        # Only for reading (PROT_READ)
    movq $0x8002, %r10   # Flags: MAP_POPULATE + MAP_PRIVATE
    movq $0, %r9         # The offset (just take everything)
    syscall

    movq %rax, %r9       # Move the address of the mmap'ed file
    popq %r11            # Restore the result buffer
    popq %r10            # Restore the file size

    # The loop is unrolled for performance.
    # This macro helps bring down the repetition.
.macro parse_digit
    movzbq (%rsi, %rcx), %rdi # Read the next byte (zero extending)
    subq $48, %rdi       # Convert the ASCII digit to its value
    js parse_end_of_number # Jump if sign is negative (\n or \t)
    addq $1, %rcx        # Increase counter
    shlq $4, %rax        # Move 4 bits for the new digit
    addq %rdi, %rax       # Add the new digit
.endm

    movq %r9, %rsi       # Start of the current number
    movq $0, %rcx        # Digits parsed
    leaq (%r9, %r10), %r8 # End of file
    movq $0, %rdx        # Result counter
.p2align 4
parse_start_of_number:
    movzbq (%rsi), %rax  # First digit into %rax, clearing it
    movq $1, %rcx        # Reset digit counter to 1
    subq $48, %rax       # Convert from ASCII to value
    parse_digit          # 2nd digit
    parse_digit          # 3rd digit
    parse_digit          # 4th digit
    parse_digit          # 5th digit
    # We can safely assume the next character is \t or \n since
    # no number is longer than 5 digits (max 32767).
parse_end_of_number:
    # Save the count of digits in the lower byte
    shlq $8, %rax        # Shift out of the lower byte
    addq %rcx, %rax      # And save the count there
    # Save the number
    movl %eax, (%r11, %rdx, 4)
    addq $1, %rdx        # Increase the counter
    addq $1, %rcx        # Count the \t or \n we read
    addq %rcx, %rsi      # Move to the start of the next number
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n.
    cmpq %rsi, %r8
    # If we aren't done, jump back to the start.
    # We just read a tab or newline so the next character must be a digit.
    jg parse_start_of_number

    # Calculate the count of coordinates.
    movq %rdx, %rax      # Count of numbers
    shrq $1, %rax        # Divided by 2
    ret



# int* radixSort(int* coordinates, int count)
#     Sorts the numbers using radix sort.
#     Returns the address of the sorted coordinates.
#     'numbers': the address of the coordinates to sort.
#     'count': the count of coordinates to sort.
.type radixSort, @function
radixSort:
    pushq %rdi           # Store the address of the numbers
    pushq %rsi           # Store the count

    # For radix sort we need a buffer to write into.
    # Calculate the needed amount of memory.
    shlq $3, %rsi        # Count of coordinates * 8 bytes

    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address
                         # Allocate space for all the numbers (already in %rsi)
    movq $0b11, %rdx     # Read and write
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8        # The connected file (none)
    movq $0, %r9         # The offset (don't care)
    syscall

    popq %r9             # Restore count
    popq %rsi            # Restore address of coordinates
    movq %rax, %rdi      # Move address of allocated space

    # Move the buffers used for counting
    movq $count_buf_high, %r10
    movq $count_buf_low, %r11

    # Count the numbers, iterating backwards
    leaq -1(%r9), %rcx
count_start:
    movzwq 6(%rsi, %rcx, 8), %rax
    movzbq 5(%rsi, %rcx, 8), %rdx
    addl $1, (%r10, %rax, 4)
    addl $1, (%r11, %rdx, 4)
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
    leaq -1(%r9), %rcx
move_num1:
    movzbq 5(%rsi, %rcx, 8), %rdx
    movq (%rsi, %rcx, 8), %rax
    subq $1, (%r11, %rdx, 4)
    movl (%r11, %rdx, 4), %edx
    movq %rax, (%rdi, %rdx, 8)
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
    leaq -1(%r9), %rcx
move_num2:
    movzwq 6(%rdi, %rcx, 8), %rdx
    movq (%rdi, %rcx, 8), %rax
    subq $1, (%r10, %rdx, 4)
    movl (%r10, %rdx, 4), %edx
    movq %rax, (%rsi, %rdx, 8)
    subq $1, %rcx
    jns move_num2

    movq %rsi, %rax
    ret


# void print(int* coordinates, int count, int size)
#     Print the coordinates.
#     'coordinates': the address of the coordinates.
#     'count': the count of coordinates.
#     'size': the size of initial file.
.type print, @function
print:
    pushq %rdi           # Save the address
    pushq %rsi           # Save the count

    # Buffer for writing the ASCII to.
    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address
    movq %rdx, %rsi      # Allocate the filesize
    addq $16, %rsi       # plus a little bit so we can read ahead
    pushq %rsi           # and save it
    movq $0b11, %rdx     # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8        # The connected file (none)
    movq $0, %r9         # The offset (don't care)
    syscall

    # Move the allocated space
    movq %rax, %rdi

    # We iterate backwards over the numbers,
    popq %rdx            # The allocated size
    popq %rcx            # Restore count for counting
    popq %rsi            # The coordinates
    leaq -1(%rdi, %rdx), %r9 # Output pointer
    movdqa shuffle_wide, %xmm2
    movdqa shift, %xmm3
    movdqa select, %xmm4
    movdqa shuffle_short, %xmm5
    movdqa conversion, %xmm6
.p2align 4
write_num:
    subq $1, %rcx        # We read a pair at a time 
    jl end_writing       # Have we written all numbers?
    # Read a pair
    movq (%rsi, %rcx, 8), %xmm0 # Read a pair of numbers
    movzbq 4(%rsi, %rcx, 8), %rax # Read size of x
    movzbq (%rsi, %rcx, 8), %rbx # Read size of y
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
    addq $1, %r9         # Don't know

    movq $1, %rax        # write syscall
    movq $1, %rdi        # To stdout
    movq %r9, %rsi       # The buffer we've written to
    movq %r13, %rdx      # Which must have the same length as the file
    syscall
    ret

