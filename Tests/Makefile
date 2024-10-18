AS = as
ASFLAGS = -g

%.o : %.s
	$(AS) $(ASFLAGS) $< -o $@

% : %.o
	ld $< -o $@

