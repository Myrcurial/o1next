	page
READ:	;a CP/M 128 byte sector.
;
;	EXIT	A = 0, successful read operation.
;		A = 1, unsucessful read operation.
;		Z bit = 1, successful read operation.
;		Z bit = 0, unsuccessful read operation.

	CALL	MVINFO		;Move information for transfer
	XRA	A		;Set flag to force a read
	STO	A,UNACNT		;Clear sector counter
	CALL	FILL		;Fill buffer with data
	POP	HL
	POP	DE
	LDK	BC,128		;Move 128 bytes
	LDIR
	LD	A,ERFLAG
	ORA	A
	RZ			;If no error
	XRA	A
	STO	A,HSTACT	;Clear host active
	ORI	001h		;Set error flag
	RET
	space	4,20
WRITE:	;the selected 128 byte CP/M sector.
;
;	ENTRY	C = 0, write to a previously allocated block.
;		C = 1, write to the directory.
;		C = 2, write to the first sector of unallocated
;		data block.
;
;	EXIT	A = 0, write was successful.
;		A = 1, write was unsucessful.
;		Z bit = 1, write was successful.
;		Z bit = 0, write was unsucessful.

	CALL	MVINFO		;Move information for transfer
	MOV	A,C		;Write type in c
	STO	A,WRTYPE
	CPI	WRUAL
	JRNZ	WRIT2		;If write to allocated
	LDK	A,2048/128
	STO	A,UNACNT
	LD	HL,SEKTRK
	STO	HL,UNATRK	;UNATRK = SEKTRK
	LD	A,LOGSEC
	INC	A
	JR	WRIT3

WRIT2:	LDK	HL,UNACNT
	LD	A,[hl]
	ORA	A
	JZ	WRIT4		;If no unallocated records
	DEC	[hl]		;dec unalloc record count
	LD	A,UNASEC	;Increment logical sector
	INC	A
	CPI	2*10
	JRNZ	WRIT3		;If not end of track
	LD	HL,UNATRK
	INC	HL
	STO	HL,UNATRK
	XRA	A

WRIT3:	STO	A,UNASEC
	LDK	A,0FFh

WRIT4:	CALL	FILL
	POP	DE
	POP	HL
	LDK	BC,128
	LDIR
	LDK	A,1
	STO	A,HSTWRT	;HSTWRT = 1
	LD	A,ERFLAG
	ORA	A
	RNZ			;If any errors occurred

	LD	A,WRTYPE	;write type
	CPI	WRDIR		;to directory?
	CZ	FLUSH		;Force write of directory
	LD	A,ERFLAG
	ORA	A
	RET
	page
;	FILL - fill host buffer with approprite host sector.
;
;	ENTRY	A = 0, Read required if not in buffer.
;		0therwise read not required.
;
;	EXIT	On exit the stack will contain the following
;		values:
;	      POP     x         ;x = host record address.
;	      POP     y		;y = caller's buffer address.

FILL:	STO	A,RDFLAG	;Save read flag
	LDK	DE,HSTBUF	;initial offset
	LDK	HL,128		;128 byte records
	LD	A,SEKSEC	;Get logical sector
	EX	DE,HL
	RRC
	JRNC	FILL3		;If low bit not set
	ADD	HL,DE		;Add bias to offset
FILL3:	EX	DE,HL
	ADD	HL,HL
	ANI	07Fh		;Mask sector
	STO	A,SEKSEC
	LD	HL,DMAADR
	XTHL			;Set return parameters
	PUSH	DE
	PUSH	HL		;Set return address

	LDK	HL,HSTACT	;host active flag
	LD	A,[hl]
	STO	1,[hl]		;always becomes 1
	ORA	A
	JRZ	FILL6		;If host buffer inactive
	LDK	HL,HSTSEC
	LDK	DE,SEKSEC
	LDK	B,SEKDSK-SEKSEC+1
FILL4:	LD	A,[de]
	CMP	[hl]
	JRNZ	FILL5		;If mis-match
	INC	HL
	INC	DE
	DJNZ	FILL4		;If all bytes not checked
	RET

FILL5:	CALL	FLUSH		;Flush host buffer

FILL6:	LD	A,SEKDSK	;Move disk and type
	STO	A,HSTDSK
	STO	A,ACTDSK
	LD	HL,SEKTRK
	STO	HL,HSTTRK
	STO	HL,ACTTRK
	LD	A,SEKSEC
	STO	A,HSTSEC
	STO	A,ACTSEC
	LD	A,RDFLAG
	ORA	A
	RNZ			;If no read required

	LDK	A,0		;Read
	JR	FINAL
	space	4,10
;	FLUSH - Write out active host buffer onto disk.

FLUSH:
	LDK	HL,HSTWRT
	LD	A,[hl]
	ORA	A
	RZ			;If host buffer already on disk
	STO	0,[hl]
	LD	A,HSTDSK	;Move disk and type
	STO	A,ACTDSK
	LD	HL,HSTTRK
	STO	HL,ACTTRK
	LD	A,HSTSEC
	STO	A,ACTSEC
	LDK	A,3		;Write flag
;	JMP	FINAL
	space	4,10
FINAL:		;Preform final transfer processing.
;
;	ENTRY	A = 0 .. read disk.
;		  = 3 .. write disk.
;	Calls: Rom resident routine to read/write ONE
;		sector only.

	MOV	E,A
	LDK	D,0
	LDK	HL,ROMVEC+3*13
	ADD	HL,DE
	STO	HL,SAVADR
	LDK	HL,ACTSEC
	INC	[hl]		;update sector+1
	LDK	A,MRTRY		;Set retry count
FNL1:	STO	A,RTRY		;Clear retry count
	LD	HL,SAVADR
	EX	DE,HL
	LDK	B,1		;indicate one sector xfer
	CALL	ROMJMP		;process read or write
	STO	A,ERFLAG	;set possible error flag
	RZ			;If no errors

	LD	A,RTRY		;Get retry counter
	DEC	A
	JRNZ	FNL1		;If not permanent error
	ORI	01h
	STO	A,ERFLAG	;Set error flag
	RET


;	endx	OSBBIOS6.asm
