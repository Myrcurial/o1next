	page
;	MVINFO	Move information necessary for transfer.

MVINFO:
	XRA	A
	STO	A,ERFLAG		;Clear error flag
	LD	A,TEMSEC
	STO	A,SEKSEC
	RET
	space	4,10
;	Print message terminated by zero byte.
;
;	ENTRY	HL -> message buffer, terminated by zero.
;
;	EXIT	HL -> zero byte + 1.
;		A = 0.
;		Z bit set.
;
;	Destroys only HL, Flags, and A registers.

PRINT:	LD	A,[hl]		;Get a character
	ORA	A
	INC	HL
	RZ			;If zero the terminate
	PUSH	HL
	MOV	C,A
	CALL	CONOUT		;Output to the console
	POP	HL
	JR	PRINT

SAVADR:	DS	2		;Disk transfer routine vector

