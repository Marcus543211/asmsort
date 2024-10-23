.section .data
stat_buffer: .space 144
count_array: .space 32768 * 4

.section .text
.globl _start
_start:
    popq %rdi # Pop no. args
    popq %rdi # Pop path of program
    popq %rdi # Pop path of file to sort

    # Open the file
    movq $2, %rax
    # The path was pop'ed into %rdi
    movq $0, %rsi
    syscall

    # Move fd to %r12
    movq %rax, %r12

    # We want the size of the file for allocating a buffer
    # and for mmap'ing the file.

    # Call fstat
    movq $5, %rax
    movq %r12, %rdi
    movq $stat_buffer, %rsi
    syscall

    # Extract the file size in bytes into %r13.
    # The buffer was populated by fstat.
    # The size is a quadword at offset 48.
    movq stat_buffer + 48, %r13 

    # For efficency, I mmap the file
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r13, %rsi # Allocate the filesize
    movq $1, %rdx # Flags for PROT_READ
    movq $0x8002, %r10 # MAP_POPULATE + MAP_PRIVATE
    movq %r12, %r8 # The connected file
    movq $0, %r9 # The offset (just take everything)
    syscall

    # Move the address of the mmap'ed file to %r15
    movq %rax, %r15

    # Now that the file is mmap'ed, it can be closed.
    
    # close syscall
    movq $3, %rax
    movq %r12, %rdi
    syscall

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

    # Move the address of the allocated space to %r14
    movq %rax, %r14

    # Parsing time!
    # We now have the file and a buffer for the result in memory.
    # Next step is converting the numbers from ASCII to binary.

    # At this point:
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file

    # The loop is unrolled for performance.
    # This macro helps bring down the repetition.
.macro parse_digit
    movzbq (%r15, %rcx), %rdx # Read the next byte (zero extending)
    addq $1, %rcx # Increase counter
    subw $48, %dx # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    imulw $10, %ax, %ax
    addw %dx, %ax # Add the new digit
.endm

    movq $0, %rcx # File counter
    movq $0, %rbx # Result counter
.align 16
start_of_number:
    movzbq (%r15, %rcx), %rax # Next digit into %rax, clearing it
    addq $1, %rcx
    subb $48, %al # Convert from ASCII to value
    parse_digit # 2nd digit
    parse_digit # 3rd digit
    parse_digit # 4th digit
    parse_digit # 5th digit
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

    # At this point:
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file
    # %rbx = count of numbers (not pairs)

    # For sorting read from buffer
    # Write to mmap'ed file (%r15) (don't need it anymore (being mean))


sort_start:
    # Here we get ready to do the accual sorting
    movq $0, %rcx # Resets our counter
    movq $count_array, %r11 # Moves address of our array to %r11 for use in future
count_start:

    # Counts the numbers in our input and adds 1 to the relevant indexes in our counting array

    movzwq 2(%r14, %rcx, 4), %r8 # Moves a y cordinate to %r8. We find the two bytes at %r14 + %rcx * 4 + 2
    addl $1, (%r11, %r8, 4) # Increments our index corresponding to the y value we just read 
    #movq (%r11, %r8, 2), %r9 # Test to see if counting correctlly
    addq $1, %rcx # Increments our counter
    movq %rcx, %rax # Copies our counter to rax to make calculations on
    imulq $2, %rax # We need to mult rax by 2 to make sure we follow our scala
    cmpq %rax, %rbx # Checks if we're done with the file
    # cmpq arg1, arg2 = arg2 - arg1
    jg count_start # Goes to start of loop if we're not done with the file
count_sum:

    # Takes all the indexes in our array and adds them with the previous exept for the first
    # We have the length of our array, that being 32767 so we can just loop until our counter reaches that number
    movq $0, %rcx # Readies our counter for the summation
    
loop_sum:
    #Tag tal ud i seperate registre
    #Lig dem sammen
    #Put tilbage i relevante register
    
    addq $1, %rcx # Increments our counter. We start at 0 so it's fine

    movl (%r11, %rcx, 4), %r8d # Moves the number we need to add to %r12
    movl -4(%r11, %rcx, 4), %r9d # Moves the number in the previous index to %r11
    addl %r8d, %r9d # Adds the numbers
    movl %r9d, (%r11, %rcx, 4) # Moves the added number to the relevenat index 

    # addl -4(%r11, %rcx, 4), (%r11, %rcx, 4) # Might work, Might not

    cmpq $32767, %rcx   # Checks if were done

    jne loop_sum

    # Calculate how much space we need
    movq %rbx, %r8
    shlq $1, %r8 # Multiply by two

    # Allocate more space with mmap
    movq $9, %rax # mmap syscall
    movq $0, %rdi # let the kernel choose the address
    movq %r8, %rsi # Allocate space for all numbers
    movq $0b11, %rdx # Flags for PROT_READ, PROT_WRITE
    # MAP_POPULATE + MAP_PRIVATE + MAP_ANONYMOUS (no file, just memory)
    movq $0x8022, %r10
    movq $-1, %r8 # The connected file (none)
    movq $0, %r9 # The offset (don't care)
    syscall

    # TODO: Unmap the file
    # We don't need the file anymore so save the allocated address in %r15
    movq %rax, %r15

move_num:
    # Now that we counted our numbers and summed we need to place the numbers in a sorted way
    # We do this by looking at the numbers in our input from the start again and checking where in our output they need to go

    # At this point:
    # %r13 = file size, %r14 = buffer, %r15 = mmap'ed file
    # %rbx = count of numbers (not pairs)

    # For sorting read from buffer
    # Write to mmap'ed file (%r15) (don't need it anymore (being mean))

    # Read the y in input
    # Check the number in our count array to get where our y needs to go
    #Put the y cordinate into the right spot in our output array

    # movq %rbx, %rax
    # movq $2, %rcx
    # div %rcx
    # movq %rax, %r8 # makes %r8 how many y coordinates we have

    movq $0, %rcx # Resets our counter
    movq $count_array, %r11 # Moves address of our array to %r11 for use in future
    movq %rbx, %rax # Calculate pair count
    shrq $1, %rax # Count of numbers divided by 2

move_loop:

    # %r10 = y coordinate we're looking at. %r9 = The index at which y needs to be incerted. %r12 = Both the x and y coordinates we need to move

    movzwq 2(%r14, %rcx, 4), %r10 # Moves a y cordinate to %r10. We find the two bytes at %r14 + %rcx * 4 + 2
    movl (%r11, %r10, 4), %r9d # Look at our counting array for where the y needs to go
    movl (%r14, %rcx, 4), %r12d # Moves both our X AND Y coordinates to %r12 contrary to before where we only had y
    movl %r12d, -4(%r15, %r9, 4) # Moves our coordinates to the index we got from %r9 minus one
    # We need to subtract 1 from the relevant index in our counting array to compensate for duplicates 
    subq $1, (%r11, %r10, 4)
    addq $1, %rcx # Increment our counter
    cmpq %rcx, %rax # Checks if we're done with our y coordinates
    jne move_loop

exit:
    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

