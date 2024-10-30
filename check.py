import sys

if len(sys.argv) < 3:
	print("Filename(s) missing.", file=sys.stderr)
	print("Usage: check.py <unsortedInputFile> <sortedFileToCheck>",
		file=sys.stderr)
	sys.exit(1)


with open(sys.argv[2]) as f:
	candLines = list(f)

for lineNum in range(len(candLines)):
	l = candLines[lineNum]
	fields = l.split()
	if len(fields) != 2:
		print("Line %d does not have 2 fields but %d. The line is\n%s"
		      % (lineNum + 1, len(fields), l), end="", file=sys.stderr)
		sys.exit(2)
	try:
		data = [int(f) for f in fields]
	except ValueError as e:
		print("Error in conversion to integers in line %d. The line is\n%s"
		      % (lineNum + 1, l), end="", file=sys.stderr)
		sys.exit(3)
	if lineNum == 0:
		prev = data
		continue
	if prev[1] > data[1]:
		print("Disorder between line %d and %d. Lines are\n%s%s"
		      % (lineNum, lineNum + 1,
				candLines[lineNum - 1], l), end="", file=sys.stderr)
		sys.exit(4)
	prev = data

with open(sys.argv[1]) as f:
	unsortedLines = list(f)

candLines.sort()
unsortedLines.sort()

for (l, lCand) in zip(unsortedLines, candLines):
	if l == lCand:
		continue
	print("Mismatch between sorted data and original unsorted data.", file=sys.stderr)
	print("Unsorted line:", file=sys.stderr)
	print(l, end="", file=sys.stderr)
	print("Sorted line:", file=sys.stderr)
	print(lCand, end="", file=sys.stderr)
	sys.exit(5)

if len(unsortedLines) < len(candLines):
	print("There are too many lines in the sorted data %d, but should have been %d." % (len(candLines), len(unsortedLines)), file=sys.stderr)
	print("Extra lines:", file=sys.stderr)
	for l in candLines[len(unsortedLines):]:
		print(l, end="", file=sys.stderr)
	sys.exit(6)
elif len(unsortedLines) > len(candLines):
	print("There are too few lines in the sorted data %d, but should have been %d." % (len(candLines), len(unsortedLines)), file=sys.stderr)
	print("Missing lines:", file=sys.stderr)
	for l in unsortedLines[len(candLines):]:
		print(l, end="", file=sys.stderr)
	sys.exit(7)
