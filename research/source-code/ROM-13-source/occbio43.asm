	page
;	H O M E
;
;	Return disk to home.  This routine sets the track number
;	to zero.  The current host disk buffer is flushed to the
;	disk.

HOME:
	CALL	FLUSH		;Flush host buffer
	XRA	A
	STO	A,HSTACT		;Clear host active flag
	STO	A,UNACNT		;Clear sector count
	STO	A,SEKTRK
	STO	A,SEKTRK+1
	RET
	space	4,10
SELDSK:	;Select disk drive for next transfer.
;
;	ENTRY	C  = disk selection value (0..15).
;		DE and 1 = 0, first call for this disk.
;
;	EXIT	HL = 0, if drive not selectable.
;		HL = DPH address if drive is selected.

	MOV	A,C
	CPI	NDSK
	JNC	SELD1		;If invalid drive number
	STO	A,SEKDSK
	MOV	L,C
	MVI	H,0
	ADD	HL,HL		;*2
	ADD	HL,HL		;*4
	ADD	HL,HL		;*8
	ADD	HL,HL		;*16
	MOV	B,E		;save initial bit
	LDK	DE,DPBASE
	ADD	HL,DE		;HL = DPH address
	PUSH	HL
	LDK	DE,100h + (low RSELDK)
	MOV	A,B
	AND	1
	CZ	ROMJMP		;Select the disk in reg C
	POP	HL
	RET

SELD1:	LDK	HL,0
	LDA	CDISK
	SUB	C
	RNZ			;If default drive not in error
	STO	A,CDISK
	RET
	space	4,10
;	S E T   T R A C K.
;
;	Set track number.  The track number is saved for later
;	use during a disk transfer operation.
;
;	ENTRY	BC = track number.

SETTRK:
	STO	BC,SEKTRK	;Set track
	LHLD	UNATRK
	MOV	A,L
	XRA	C
	MOV	C,A
	MOV	A,H
	XRA	B
	ORA	C
	RZ			;If same track
;	JMP	CUNACT
	space	4,10
;	Clear Unallocated block count (force pre-reads).

CUNACT:	XRA	A		;A = 0
	STO	A,UNACNT		;Clear unallocated block count
	RET
	space	4,10
;	Set the sector for later use in the disk transfer.  No
;	actual disk operations are perfomed.
;
;	Entry	BC = sector number.

SETSEC:	MOV	A,C
	STO	A,TEMSEC	;sector to seek
	RET
	space	4,10
;	Set Disk memory address for subsequent disk read or
;	write routines.  This address is saved in DMAADR until
;	the disk transfer is performed.
;
;	ENTRY	BC = Disk memory address.
;
;	EXIT	DMAADR = BC.

SETDMA:
	STO	BC,DMAADR
	RET
	space	4,15
;	Translate sector number from logical to physical.
;
;	ENTRY	DE = 0, no translation required.
;		DE = translation table address.
;		BC = sector number to translate.
;
;	EXIT	HL = translated sector.

SECTRN:
	LDA	UNASEC
	CMP	C
	CNZ	CUNACT		;If sectors do not match
	MOV	A,C
	STO	A,LOGSEC
	MOV	L,C
	MOV	H,B
	ADD	HL,DE
	MOV	L,M
	MVI	H,0
	RET
