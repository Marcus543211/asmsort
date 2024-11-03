.section .text
.globl _start
_start:
    # TODO: Handle errors, check for SIMD features, close things.

    popq %rdi            # Pop no. args
    popq %rdi            # Pop path of program
    popq %rdi            # Pop path of file to sort

    # Open the file.
    movq $2, %rax        # open syscall
                         # The path was pop'ed into %rdi
    movq $0, %rsi        # Open for reading
    syscall

    movq %rax, %r12      # Move the fd

    # We want the size of the file for allocating a buffer
    # and for mmap'ing the file.
    movq %r12, %rdi
    call getFileSize
    
    movq %rax, %r13      # Move the file size

    # The rest of the program assumes the file is not empty
    # so we exit here if it is.
    cmpq $0, %r13
    je exit

    # Calculate the maximum needed amount of memory.
    movq %r13, %rdi      # Get the size of the file
    shl $1, %rdi         # Multiply by 2
    movq $0, %rsi        # No extra flags
    call alloc           # And allocate

    movq %rax, %r14      # Move the address of the allocated space

    # Parsing time!
    movq %r12, %rdi
    movq %r13, %rsi
    movq %r14, %rdx
    call parseFile
    
    movq %rax, %r15      # Move the count of coordinates

    # Sorting!
    movq %r14, %rdi
    movq %r15, %rsi
    call radixSort

    # Printing time!
    movq %rax, %rdi      # The sorted coordinates
    movq %r15, %rsi
    movq %r13, %rdx
    call print

exit:
    # That's all folks!
    movq $60, %rax       # exit syscall
    movq $0, %rdi        # All went good
    syscall


# int getFileSize(int fd)
#     Return the size in bytes of the file.
#     'fd': file descriptor of the file to get the size of.
.section .data
stat_buf: .space 144

.section .text
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
#     Parse the coordinates in the file.
#     Return the number of coordinates in the file.
#     The parsed numbers are 32-bit and stored in packed BCD with
#     their least significant byte being the count of digits in the number.
#     This is done for faster parsing and printing.
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

    movq %r9, %rsi       # Start of the current number
    movq $0, %rcx        # Digits parsed
    leaq (%r9, %r10), %r8 # End of file
    movq $0, %rdx        # Result counter
.p2align 4
parse_start_of_number:
    movzbq (%rsi), %rax  # First digit into %rax, clearing it
    movq $1, %rcx        # Reset digit counter to 1
    subq $48, %rax       # Convert from ASCII to value
    # Parse up to 4 digits more.
    # The loop is unrolled for performance.
.rept 4
    movzbq (%rsi, %rcx), %rdi # Read the next byte (zero extending)
    subq $48, %rdi       # Convert the ASCII digit to its value
    js parse_end_of_number # Jump if sign is negative (\n or \t)
    addq $1, %rcx        # Increase counter
    shlq $4, %rax        # Move 4 bits for the new digit
    addq %rdi, %rax      # Add the new digit
.endr
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
.section .data
# Space for radix sort.
.p2align 4
# A little more than is needed (3*16^2 + 2*16 + 7 = 807)
count_buf_higher: .space 810 * 4
# A little more than is needed (9*16 + 9 = 154)
count_buf_lower: .space 160 * 4

.section .text
.type radixSort, @function
radixSort:
    # It might be slightly wrong to call this radix sort
    # as the radix is not constant. However, the procedure is the same.

    pushq %rdi           # Store the address of the numbers
    pushq %rsi           # Store the count

    # For radix sort we need a buffer to write into.
    # Calculate the needed amount of memory.
    shlq $3, %rsi        # Count of coordinates * 8 bytes

    # Allocate memory
    movq %rsi, %rdi      # Needed space
    movq $0x8000, %rsi   # Flag: MAP_POPULATE (performance improvement)
    call alloc

    popq %r9             # Restore count
    popq %rsi            # Restore address of coordinates
    movq %rax, %rdi      # Move address of allocated space

    # Move the buffers used for counting
    movq $count_buf_higher, %r10
    movq $count_buf_lower, %r11

    # Count the numbers, iterating backwards
    leaq -1(%r9), %rcx   # Counter
radixSort_count:
    movzwq 6(%rsi, %rcx, 8), %rax # Extract "higher" word of y
    movzbq 5(%rsi, %rcx, 8), %rdx # Extract "lower" byte of y
    addl $1, (%r10, %rax, 4) # Count both
    addl $1, (%r11, %rdx, 4)
    subq $1, %rcx        # Move on to next y
    jns radixSort_count  # Continue while the count is positive

    # Macro for calculating the running sum of the counts.
.macro running_sum label buf count
    movq $0, %rax        # Accumulator
    movq $0, %rcx        # Counter
\label :
    addl (\buf, %rcx, 4), %eax # Add current number to total
    movl %eax, (\buf, %rcx, 4) # Move total back
    addq $1, %rcx        # Move to next number
    cmpq $\count, %rcx   # Check if were done
    jl \label
.endm

    # Macro for moving based on a counts.
.macro move label from to counts smov offset
    # Move the coordinates iterating backwards.
    leaq -1(%r9), %rcx   # Index of last element
\label :
    \smov \offset(\from, %rcx, 8), %rdx # Get part to sort by
    movq (\from, %rcx, 8), %rax   # Get the full coordinate
    subq $1, (\counts, %rdx, 4)   # Subtract one from the counts
    movl (\counts, %rdx, 4), %edx # Get the index to place at
    movq %rax, (\to, %rdx, 8)     # Place at new index
    subq $1, %rcx        # Move to next coordinate
    jns \label           # Continue while positive
.endm

    # Sort based on lower part
    running_sum radixSort_sum_lower %r11 160
    move radixSort_move_lower %rsi %rdi %r11 movzbq 5

    # Sort based on higher part
    running_sum radixSort_sum_higher %r10 810
    move radixSort_move_higher %rdi %rsi %r10 movzwq 6

    # Move the address to the sorted coordinates.
    movq %rsi, %rax
    ret


# void print(int* coordinates, int count, int size)
#     Print the coordinates.
#     'coordinates': the address of the coordinates.
#     'count': the count of coordinates.
#     'size': the size of initial file.
.section .data
# Various constants for SIMD operations.
# TODO: Explain these here or in the code.
.p2align 4
shuffle_wide:
    .long 0xFF070605
    .long 0xFF070605
    .long 0xFF030201
    .long 0xFF030201

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
.type print, @function
print:
    pushq %rdi           # Save the address
    pushq %rsi           # Save the count
    addq $16, %rdx       # We will be allocating a little extra
    pushq %rdx           # Save the allocated size

    # Buffer for writing the ASCII to.
    movq %rdx, %rdi
    movq $0x8000, %rsi
    call alloc

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
print_loop:
    subq $1, %rcx        # We read a pair at a time 
    jl print_loop_end    # Have we written all numbers?
    # Read a pair
    movq (%rsi, %rcx, 8), %xmm0 # Read a pair of numbers
    movzbq 4(%rsi, %rcx, 8), %rax # Read size of x
    movzbq (%rsi, %rcx, 8), %rbx # Read size of y
    pshufb %xmm2, %xmm0         # Duplicate the numbers without counts
    vpsrlvd %xmm3, %xmm0, %xmm0 # Bit shift one version by 4
    pand %xmm4, %xmm0           # Clear the upper half of all bytes
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
    jmp print_loop
print_loop_end:
    addq $1, %r9         # Don't know

    movq $1, %rax        # write syscall
    movq $1, %rdi        # To stdout
    movq %r9, %rsi       # The buffer we've written to
    movq %r13, %rdx      # Which must have the same length as the file
    syscall
    ret


# int* alloc(int size, int flags)
#     Allocates memory using mmap.
#     Returns the address of the allocated memory.
#     'size': how much memory to allocate in bytes.
#     'flags': additional flags to pass to mmap.
.type alloc, @function
alloc:
    # Move the arguments before their overwritten
    movq $0x22, %r10     # Flags: MAP_PRIVATE + MAP_ANONYMOUS
    orq %rsi, %r10       # Add additional flags
    movq %rdi, %rsi      # Space to allocate

    # Allocate space with mmap
    movq $9, %rax        # mmap syscall
    movq $0, %rdi        # Let the kernel choose the address again
    # %rsi, space to allocate
    movq $0b11, %rdx     # Read and write (PROT_READ + PROT_WRITE)
    # %r10, flags
    movq $-1, %r8        # The connected file (none)
    movq $0, %r9         # The offset (don't care)
    syscall
    ret

