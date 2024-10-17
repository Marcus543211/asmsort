.section .data
stat_buffer:
    .space 144

thread_stack:
    .space 256
thread_stack_top:

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

    # Since the file is mmap'ed it's safe to close it
    movq $3, %rax # close syscall
    movq %r12, %rdi # fd
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

    # Move allocated space to %r14
    movq %rax, %r14

    ### Threading ###

    # Calculate half the file length
    # Or rather the offset from which the thread will read/write.
    # It's half of the file length aligned to an even number.
    # This makes debugging a nicer expericence.
    movq %r13, %rax # Move file length
    shrq $2, %rax # Divide by 4
    shlq $1, %rax # Multiply by 2

    # Prepare stack for both threads.
    # From top: buffer start, file end, file start
    leaq (%r15, %rax), %rbx # Child file start
    leaq (%r15, %r13), %rcx # File end
    leaq (%r14, %rax), %rdx # Child buffer start
    pushq %r15 # Main thread starts at beginning of file
    pushq %rbx # Ends where the child starts
    pushq %r14 # Main thread starts at beginning of buffer
    # Child thread starts halfway through
    movq %rbx, thread_stack_top - 8 # Starts halfway through file
    movq %rcx, thread_stack_top - 16 # Ends at end
    movq %rdx, thread_stack_top - 24 # Starts halfway through buffer

    # Creating new process with clone
    movq $56, %rax # clone syscall
    movq $0x100, %rdi # VM_CLONE
    movq $thread_stack_top - 24, %rsi # Start it above so it can pop
    syscall
threads:

    # Move process id (pid)
    movq %rax, %r12

    # Get where to begin
    popq %r9 # Buffer start
    popq %r11 # File end
    popq %r10 # File start

    # Move to start location
    cmpq $0, %r12 # Only the child needs to seek
    jne at_line_start
seek_loop:
    cmpb $'\n', -1(%r10) # Is the character before a newline?
    je at_line_start # If not
    addq $1, %r10 # Move our start location one ahead
    jmp seek_loop
at_line_start:

    # At this point:
    # %r9 = buffer start, %r10 = file start, %r11 = file end
    # %r12 = process id (0 for child)
    # %r13 = file size
    # %r14 = buffer (or this threads start (main thread has actual start))
    # %r15 = mmap'ed file (--||--)

    # Parse the numbers of the file

    # Macro for parsing a digit
.macro parse_digit
    movzbq (%r10), %rbx # Read the next byte (zero extending)
    addq $1, %r10 # Move file pointer
    subw $48, %bx # Convert the ASCII digit to its value
    js end_of_number # Jump if sign is negative (\n or \t)
    imulw $10, %ax, %ax # Make room for new digit
    addw %bx, %ax # Add the new digit
.endm

.align 16 # Align for a little performance on jumps
start_of_number:
    # We're at the start of a number so the next char must be a digit.
    movzbq (%r10), %rax # Next digit into %rax, clearing it
    addq $1, %r10
    subw $48, %ax # Convert from ASCII to value
    parse_digit # 2nd digit (from left)
    parse_digit # 3rd digit
    parse_digit # 4th digit
    parse_digit # 5th digit
    # We can safely assume the next char is \t or \n since
    # no number is longer than 5 digits (max 32767).
    addq $1, %r10 # Count the \t or \n
    # Normally when jumping it has been counted
end_of_number:
    movw %ax, (%r9) # Move number into buffer
    addq $2, %r9 # Increase the counter (by 2 since we write 16 bit numbers)
    # Have we read the entire file?
    # We only check here since a well formatted file will ends with \n
    cmpb $'\n', -1(%r10)
    jne start_of_number
    cmpq %r11, %r10
    # We just read a tab or newline so the next character must be a digit.
    # We've also just ended a number so %ax is free.
    jl start_of_number
parse_loop_end:

    # Exit child thread
    cmpq $0, %r12
    je exit

    # Wait for child thread exit
    movq $61, %rax # wait4 syscall
    movq %r12, %rdi # pid of child
    movq $0, %rsi # wstatus (don't care)
    movq $0x80000000, %rdx # __WCLONE
    movq $0, %r10 # rusage (don't care)
    syscall

exit:
    # Exit
    movq $60, %rax
    movq $0, %rdi
    syscall

