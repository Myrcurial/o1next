
	TITLE	'Diagnostic section.'
;	This section of code is entered either via the 1st prompt
;	level by entering ^d, or by using the monitor command of
;	'T' if DEBUG is assembled on.
;
;	This section of code contains all of the rom resident
;	diagnostics to assist production and distributors.
;
;	The diagnostic section uses a menu and contain test
;	for major hardware pieces.  These diagnostics are NOT
;	considered to be all-encompassing......



DIAG:
	proc

	LDK	DE,DIAMSG

DIAG1:	LK	SP,ROMSTK
	CALL	ASKU		;ask user for input
	LDK	HL,DSKSWP	;disk swap cell
	LDK	C,0
	STO	C,[HL]		;SET A=A,B=B
	CMP	'A'
	JZ	CBOOT		;IF BOOT A DRIVE
	INC	[HL]		;SWAP DRIVES A=B,B=A
	CMP	'B'
	JZ	CBOOT		;IF BOOT B DRIVE
	DEC	[HL]		;A=A, B=B
	CMP	'K'
	JZ	KEYBT		;if Keyboard test
	CMP	'M'
	JZ	TSTMEM		;if memory test
	CMP	'R'
	JZ	TSERI		;if input test program
	CMP	'D'
	JRNZ	DIAG		;if illegal

DSKD:
	;Here to run disk diagnostic
	LDK	DE,DSKMSG
	CALL	ASKU		;Ask user for input
	SUB	'A'
	JRZ	:2		;if 'A'
	DEC	A
	JRNZ	DIAG		;if not A or B
	INC	A
:2:
	STO	A,SDISK		;set drive

	CALL	DRDT		;test reading entire disk
	CALL	DSEKT		;test random seeks
	JMP	DIAG		;next

DIAMSG:
	DBE	'Z'-40h
	DBE	'   ROM DIAGNOSTICs'
	DBE	cr,lf,'Select Test:'
	DBE	cr,lf,'A,B Boot Sys'
	DBE	cr,lf,' D isk'
	DBE	cr,lf,' K ey-vdt'
	DBE	cr,lf,' M emory'
	DBE	cr,lf,' R ead in test'
	DBE	lf,cr,lf,' :'
	DCE	' '

DSKMSG:
	DBE	cr,lf
	DCE	'Select (A,B): '
	PAGE
;	Disk diagnostic section.

DRDT:
;Disk read test
;reads each sector on disk and reports any errors
	proc
	CALL	DSKDI		;initialize disk

:2:	STO	A,SAVTRK
	LDK	B,1
	MOV	A,B
	STO	A,SAVSEC	;SECTOR = 1
	CALL	DREAD		;read sector
	CNZ	DERR		;if error
	LD	A,SAVTRK
	INC	A
	CMP	MTRK
	JRNZ	:2		;if not full disk
	ret
	PAGE
DSEKT:
;Disk seek test
;	Routine performs random seeks followed by reads validating
;	drive is aligned and data path is valid.
;	Entry	None.
;	Exit	Back to diag main loop.
	proc
	CALL	DSKDI		;initialize
	LDK	B,100

:2:	PUSH	BC
	CALL	GNRN		;get next track
	STO	A,SAVTRK
	LDK	B,1
	MOV	A,B
	STO	A,SAVSEC	;SECTOR = 1
	CALL	DREAD		;read sector
	CNZ	DERR		;if disk error
	CALL	GNRN		;get random
	CALL	DELAY		;delay
	POP	BC
	DJNZ	:2		;if not done
	RET
	page
DSKDI:
;Disk diagnostic initialize
;Entry
;SDISK set to disk to test(0 or 1)
	proc
	LD	A,SEC6
	STO	A,RNDV		;set random seed

	LDK	B,5		;RETRY

:2:	PUSH	BC
	CALL	HOMED		;select drive 0, home.
	POP	BC
	JRZ	:3		;if drive ready
	DJNZ	:2		;RETRY FIVE TIMES

	LDK	DE,DNRMSG	;DRIVE NOT READY
	JMP	DIAG1

:3:	LDK	HL,04000H
	STO	HL,DMADR	;SET DMA
	RET
	page
ASKU:
	;Ask user for input, first displaying prompt
;	Entry	DE= FWA of prompt message
;	Exit	A= normalized input from user
	CALL	ESTR		;prompt user
	CALL	GETCH		;get next char
	CMP	ESC
	JZ	DIAG		;if abort
	RET
	page
KEYBT:
	;Perform reading of keyboard and echoing to screen
;	Keeps running till user types in ^Z.
	LDK	DE,KEYTM
	CALL	ESTR		;output prompt
	LDK	HL,4000h
	JMP	ACMDD		;enter A command

KEYTM:
	DBE	cr,lf
	DCE	'Enter keys (till ^Z) : '
	page
TSTMEM:
	;performs a test of memory validating that the
;	memory is working correctly.
;	Fixed limits on memory test are 4000h to EF00h
;	(TEM = EF00h)
;	Entry	none.
;	Exit	To error if any errors occurred during
;		the testing
;	Calls	GETNM

	proc
	LDK	DE,TSMSG
	CALL	ESTR	;prompt user about mem test
	LDK	DE,TEM
	LDK	HL,4000h
	LDK	C,0A5h	;initial test pattern

;	Loop thu testing memory within limits
;	HL= FWA
;	DE= LWA

:2:
	DI
	PUSH	DE	;save LWA
	PUSH	HL	;save FWA
:3:
	STO	C,[hl]	;data to memory
	INC	HL	;update address
	CALL	CDEHL
	JRNZ	:3	;if not all done

;	Now perform test on memory reading
;	what was just written and comparing
;	with pattern C.
	POP	HL	;restore FWA
	PUSH	H
:5:
	DI
	LD	A,[hl]
	CMP	C	;validate good write
	JRZ	:7	;If GOOD compare
	EI
	MOV	B,A	;save BAD data
	PUSH	BC
	CALL	OCRLF	;output new line
	CALL	ADRD	;Output Location in error
	CALL	OSP	;Output space char
	POP	BC
	PUSH	BC
	MOV	A,C
	CALL	NMOUT	;Output good data
	LDK	C,'='
	CALL	COUT
	MOV	A,B
	CALL	NMOUT	;Output BAD data
	POP	BC	;restore pattern
	CALL	BREAK
:7:
	INC	HL
	CALL	CDEHL
	JRNZ	:5	;If not all done
	EI		;allow key entry
	MOV	A,C
	RRC		;shift one position
	MOV	C,A
	LDK	HL,FWAVM+40
	INC	[hl]	;indicate running
	POP	HL
	POP	DE
	CALL	BREAK
	JRZ	:2	;if not data
	MOV	C,A	;next test pattern
	JMP	:2	;keep on looping

TSMSG:
	DBE	cr,lf,'Memory tes'
	DCE	't'
	page
TSERI:
	;Input test routine through serial port
;	Format of input:
;		8 bit binary data, no parity
;		1st two bytes are DW (length)
;		(length) following bytes are placed
;		at 4000h in memory;
;	Exit: JMP 4000h
	Proc

	LK	DE,:lmsg	;length msg
	CALL	ESTR

	CALL	READER		;get chr
	MOV	L,C		;low byte of length
	CALL	READER
	MOV	H,C

	CALL	PBWH		;print out length of test routine
	EX	HL,DE		;DE = length
	LK	HL,4000h	;FWA of test program

:loop:
	MOV	A,D
	OR	E
	JRZ	:xit		;if finished with input, run prgm
	CALL	READER
	STO	A,[hl]		;get & deposit next byte
	STO	A,FWAVM+40	;indicate recieved data
	INC	HL
	DEC	DE
	JR	:loop

:xit:
	LK	DE,:xmsg	;exit message
	CALL	ESTR
	JMP	4000h		;...to user program

:lmsg:
	DBE	cr,lf,'Start input: Len' ! DCE '='
:xmsg:
	DBE	cr,lf,'Program begins'   ! DCE ':'

	space	4,10
GNRN:
	;Get next random number
;	Exit	A= new number to use (0 to MTRK-1)
	proc
	MOV	A,R		;refresh register
	XOR	[hl]
	AND	3Fh		;cannot exceed 28h=40d
	ADD	A,16
	CMP	MTRK
	JC	:4		;if in range
	SUB	MTRK
:4:
	STO	A,[hl]		;update
	RET
	space	4,10
ACMDD:
	;Eotry here from Diagnostic loop HL = 4000h
	proc
:3:
	CALL	CI	;read char
	CPI	EOFC
	JZ	DIAG	;if request to quit
	STO	A,[hl]	;into memory
	INC	HL	;update pointer
	CPI	CR
	JRNZ	:5	;If not carriage return
	STO	LF,[hl]
	INC	HL
:5:
	MOV	C,A
	CALL	COUT	;back to user
	JR	:3	;next character
	space	4,10
ADRD:
PBWH:
	;Print Binary Word in Hex.
;	PBWH outputs to the console the address
;	contained in the H,L registers.
;	Entry	HL= address to be displayed
;	Exit	NONE
;	Calls	PBBH
; DESTROYS: AF, C.

	MOV	A,H	;display First half of address
	CALL	PBBH
	MOV	A,L	;display second half of address
	JR	PBBH
	space	4,10
BREAK:
	;Check for break key.
;	Entry	NONE
;	Exit	To DIAG if char entered is ESC, else
;		return to caller A= char or 0 if none
;	Calls	SKEY, CI
; DESTROYS: A,F/F'S

	CALL	SKEY	;get console status
	RZ		;If not ready
	CALL	CI	;get char
	CMP	ESC
	JZ	DIAG	;if ESC, abort
	RET
	space	4,10
GETCH:
	;returns the next character in the input stream
;	TO the calling program.
;	Entry	NONE
;	Exit	C - next character normalized to UPPER case.
;	Calls	CI,CO,NORM
; DESTROYS: A,C,F/F'S

	CALL	CI	;Get character from terminal
	CALL	CO	;output it
	JMP	NORM

;	END	OCCROM7?.???
