	page
;*****
;	Revisions:
;	YNS	18AUG81		added iobyte function to listst
;				modified romcde routine
;	YNS	30AUG81		moved const and listst to osbbios9.asm
;	YNS	23SEP81		saved hl in ROMCDE routine when returning
;				to RAM as IEEE routines return status in
;				HL
;	RWC	09NOV81		Preserved value of HL when calling ROM
;				routines, HL used in VLDDR, VLDIR, & STODIM
;				preserved HL & DE on exit
; 
;*****


SETRRM:	;Set ROM-RAM flag
;	Entry	A= port to output (setting ROM or RAM enable)
;	Exit	none.
;	Uses	A
	DI
	PUSH	BC
	MOV	C,A
	OT,C	A
	STO	A,ROMRAM
	POP	BC
	EI ! RET
	space	4,10
ROMRI:	;Exit ROM resident Interrupt routine.
	LD	A,ROMRAM
	MOV	C,A		;port
	OT,C	A		;set ROM or RAM enabled
	POP	IY
	POP	IX
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	LD	SP,IESTK	;reset to interrupt entry stk
	EI ! RET
	space	4,10
ROMCDE:	;Call ROM resident processor
;	Entry	DE = resident processor to call biased
;		by CBIOS jump vector.
;	NOTE: ROM jump vector must match CBIOS vector
;
;	Entry at ROMCD1 with low digit of CBIOS vector in reg E

	POP	DE		;Get calling address
	MOV	A,E
	SUI	3
	MOV	E,A
ROMCD1:
	LDK	D,high (ROMVEC)

ROMJMP:	;Entry here to jump to ROM function code directly
;	Entry	DE = ROM jump address
;		BC, HL, IX = any parameters
	
	sto	hl,stohl
	DI
	LDK	HL,0
	ADD	HL,SP		;Old stack to HL
	LDK	SP,BIOSTK
	PUSH	HL		;Save old stack pointer
	ld	hl,stohl	;get user hl
	ENAROM
	push	de		;ROM jump address to IY
	pop	IY
	CALL	GOROM
	DI
	PUSH	AF		;save status returned
	DISROM
	POP	AF
	pop	iy		;Restore old stack pointer
	MOV	SP,iy
	EI ! RET

GOROM:	EI
	JMP	[IY]

STOHL:	DS	2
