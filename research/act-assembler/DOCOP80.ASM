	TITLE	'Alphabetic List of Sorcim Assembler Mnemonics.'
;	Alphabetic List of ACT mnemonics.
;		79-06-14
	LIST	G
nn:			;    0 <= nn   <  256
mmmm:			;    0 <= mmmm <  2**16
;rel:			;*-126 <= rel  <= *+129
dd:			; -128 <= dd   <= +127
p:			;    0 <= p    <= 7
	Aci	nn
	Adc	A
	ADC	A,A
	ADC	A,B
	ADC	A,C
	ADC	A,D
	ADC	A,E
	ADC	A,H
	ADC	A,L
	ADC	A,[hl]
	ADC	A,[IX+dd]
	ADC	A,[IY+dd]
	ADC	A,nn
	Adc	B
	Adc	C
	Adc	D
	Adc	E
	Adc	H
	ADC	HL,BC
	ADC	HL,DE
	ADC	HL,HL
	ADC	HL,SP
	Adc	L
	Adc	M
	ADC	[hl]
	add	A
	ADD	A,A
	ADD	A,B
	ADD	A,C
	ADD	A,D
	ADD	A,E
	ADD	A,H
	ADD	A,L
	ADD	A,[hl]
	ADD	A,[IX+dd]
	ADD	A,[IY+dd]
	ADD	A,nn
	ADD	B
	ADD	C
	ADD	D
	ADD	E
	ADD	H
	ADD	L
	ADD	M
	ADD	[hl]
	ADD	HL,BC
	ADD	HL,DE
	ADD	HL,HL
	ADD	HL,SP
	ADD	IX,BC
	ADD	IX,DE
	ADD	IX,IX
	ADD	IX,SP
	ADD	IY,BC
	ADD	IY,DE
	ADD	IY,IY
	ADD	IY,SP
	ADI	nn
	ANA	A
	ANA	B
	ANA	C
	ANA	D
	ANA	E
	ANA	H
	ANA	L
	ANA	M
	ANA	[hl]
	AND	A
	AND	B
	AND	C
	AND	D
	AND	E
	AND	H
	AND	L
	AND	[hl]
	AND	[IX+dd]
	AND	[IY+dd]
	AND	nn
	ANI	nn
	BIT	p,A
	BIT	p,B
	BIT	p,C
	BIT	p,D
	BIT	p,E
	BIT	p,H
	BIT	p,L
	BIT	p,[hl]
	BIT	p,[IX+dd]
	BIT	p,[IY+dd]
	CALL	mmmm
;		Clear BIT.
	CBIT	p,A
	CBIT	p,B
	CBIT	p,C
	CBIT	p,D
	CBIT	p,E
	CBIT	p,H
	CBIT	p,L
	CBIT	p,[hl]
	CBIT	p,[IX+dd]
	CBIT	p,[IY+dd]
	CC	mmmm		;Call if Carry
	CLC			;CLear Carry & set flags
	CMA			;CoMplement Accumulator
	CMC			;CoMplement Carry
;		CoMPare to accumulator.
	CMP	A
	CMP	B
	CMP	C
	CMP	D
	CMP	E
	CMP	H
	CMP	L
	CMP	M
	CMP	[hl]
	CMP	[IX+dd]
	CMP	[IY+dd]
	CMP	nn
	CM	mmmm
	CNZ	mmmm	;0C4h 
	CNC	mmmm	;0D4h 
	CPE	mmmm	;0ECh 
	CPO	mmmm	;0E4h 
	CPDR			;271q	;ED
	CPD			;251q	;ED
	CPIR			;261q	;ED
	CPI#			;241q	;ED
	CPI	nn	;088h, 0FEh 
	CP	mmmm	;0F4h 
	CZ	mmmm	;0CCh 
	DAA			;027h 
	DAD	B
	DAD	BC
	DAD	D
	DAD	DE
	DAD	H
	DAD	HL
	DAD	SP

	dcr	A
	dcr	B
	dcr	C
	dcr	D
	dcr	E
	dcr	H
	dcr	L
	dcr	M
	dcr	[hl]
	dcx	B
	dcx	BC
	dcx	D
	dcx	DE
	dcx	H
	dcx	HL
	dcx	SP

	DEC	A
	DEC	B
	DEC	BC
	DEC	C
	DEC	D
	DEC	DE
	DEC	E
	DEC	H
	DEC	HL
	DEC	L
	DEC	SP
	DEC	IX
	DEC	IY
	DEC	[hl]
	DEC	[IX+dd]
	DEC	[IY+dd]
	DI			;0F3h 
	DJNZ	rel		;020q	;ED
rel:
	EI			;0FBh 
	EX	AF		;010q	Zilog
	EX	DE,HL
	EX	[sp],HL
	EX	[sp],IX
	EX	[sp],IY
	EXX			;331q	Zilog
	HLT			;166q 
	IM0			;106q	;ED
	IM1			;126q	;ED
	IM2			;136q	;ED
	INC	A
	INC	B
	INC	BC
	INC	C
	INC	D
	INC	DE
	INC	E
	INC	H
	INC	HL
	INC	L
	INC	SP
	INC	IX
	INC	IY
	INC	[hl]
	INC	[IX+dd]
	INC	[IY+dd]
	INDR			;272q	;ED
	IND			;252q	;ED
	INIR			;262q	;ED
	INI			;242q	;ED
	inr	A
	inr	B
	inr	C
	inr	D
	inr	E
	inr	h
	inr	L
	inr	M
	inr	[hl]
	inx	B
	INX	BC
	inx	D
	INX	DE
	inx	H
	INX	HL
	INX	SP
	IN,C	A
	IN,C	B
	IN,C	C
	IN,C	D
	IN,C	E
	IN,C	H
	IN,C	L
	IN,C	[hl]
	IN	nn
	JMP	mmmm
	JMP	[hl]
	JMP	[ix]
	JMP	[iy]
	JNZ	mmmm	;0C2h 
	JM	mmmm	;0FAh 
	JC	mmmm	;0DAh 
	JNC	mmmm	;0D2h 
	JPE	mmmm	;0EAh 
	JPO	mmmm	;0E2h 
	JP	mmmm	;0F2h 
	JZ	mmmm	;0CAh 
	JRC	rel		;070q	;ED
	JRNC	rel		;060q	;ED
	JRNZ	rel		;040q	;ED
	JRZ	rel		;050q	;ED
	JR	rel		;030q	;ED
	LDAX	B
	LDAX	BC		;0Ah 
	LDAX	D
	LDAX	DE
	LDA	mmmm	;03Ah 
	LDDR			;270q	;ED
	LDD			;250q	;ED
	LDIR			;260q	;ED
	LDI			;240q	;ED
	LD	A,[bc]		;012q
	LD	A,[de]		;032q
	LD	A,[hl]		;176q
	LD	A,[IX+dd]
	LD	A,[IY+dd]
	LD	A,mmmm		;072q
	LD	B,[hl]		;106q
	LD	B,[IX+dd]
	LD	B,[IY+dd]
	LD	BC,mmmm		;113q	ED
	LD	C,[hl]		;116q
	LD	C,[IX+dd]
	LD	C,[IY+dd]
	LD	D,[hl]		;126q
	LD	D,[IX+dd]
	LD	D,[IY+dd]
	LD	DE,mmmm		;133q	ED
	LD	E,[hl]		;136q
	LD	E,[IX+dd]
	LD	E,[IY+dd]
	LD	H,[hl]		;146q
	LD	H,[IX+dd]
	LD	H,[IY+dd]
	LD	HL,mmmm		;052q
	LD	IX,mmmm		;052q	DD
	LD	IY,mmmm		;052q	FD
	LD	L,[hl]		;156q
	LD	L,[IX+dd]
	LD	L,[IY+dd]
	LD	SP,mmmm		;173q	ED
	LHLD	mmmm		;052q 
	LK	A,nn
	LK	B,nn
	LK	BC,mmmm
	LK	C,nn
	LK	D,nn
	LK	DE,mmmm
	LK	E,nn
	LK	H,nn
	LK	HL,mmmm
	LK	IX,mmmm
	LK	IY,mmmm
	LK	L,nn
	LK	SP,mmmm
	LXI	B,mmmm
	LXI	BC,mmmm
	LXI	D,mmmm
	LXI	DE,mmmm
	LXI	H,mmmm
	LXI	HL,mmmm
	LXI	SP,mmmm
	MOV	A,A
	MOV	A,B
	MOV	A,C
	MOV	A,D
	MOV	A,E
	MOV	A,H
	MOV	A,I		;ED
	MOV	A,L
	MOV	A,R		;ED
	MOV	A,[hl]
	MOV	B,A
	MOV	B,B
	MOV	B,C
	MOV	B,D
	MOV	B,E
	MOV	B,H
	MOV	B,L
	MOV	B,[hl]
	MOV	C,A
	MOV	C,B
	MOV	C,C
	MOV	C,D
	MOV	C,E
	MOV	C,H
	MOV	C,L
	MOV	C,[hl]
	MOV	D,A
	MOV	D,B
	MOV	D,C
	MOV	D,D
	MOV	D,E
	MOV	D,H
	MOV	D,L
	MOV	D,[hl]
	MOV	E,A
	MOV	E,B
	MOV	E,C
	MOV	E,D
	MOV	E,E
	MOV	E,H
	MOV	E,L
	MOV	E,[hl]
	MOV	H,A
	MOV	H,B
	MOV	H,C
	MOV	H,D
	MOV	H,E
	MOV	H,H
	MOV	H,L
	MOV	H,M
	MOV	H,[hl]
	MOV	I,A		;ED
	MOV	L,A
	MOV	L,B
	MOV	L,C
	MOV	L,D
	MOV	L,E
	MOV	L,H
	MOV	L,L
	MOV	L,M
	MOV	L,[hl]
	MOV	M,A
	MOV	M,B
	MOV	M,C
	MOV	M,D
	MOV	M,E
	MOV	M,H
	MOV	M,L
	MOV	R,A		;ED
	MOV	SP,HL
	MOV	SP,IX
	MOV	SP,IY
	MOV	[hl],A
	MOV	[hl],B
	MOV	[hl],C
	MOV	[hl],D
	MOV	[hl],E
	MOV	[hl],H
	MOV	[hl],L
	MVI	A,nn
	MVI	B,nn
	MVI	C,nn
	MVI	D,nn
	MVI	E,nn
	MVI	H,nn
	MVI	L,nn
	MVI	M,nn
	MVI	[hl],nn
	NEG			;104q	;ED
	NOP			;00 
	OR	A
	OR	B
	OR	C
	OR	D
	OR	E
	OR	h
	OR	L
	OR	[hl]
	OR	[IX+dd]
	OR	[IY+dd]
	OR	nn
	ORA	A
	ORA	B
	ORA	C
	ORA	D
	ORA	E
	ORA	H
	ORA	L
	ORA	M
	ORA	[hl]
	ORI	nn
	OTDR			;273q	;ED
	OTIR			;263q	;ED
	OT,C	A
	OT,C	B
	OT,C	C
	OT,C	D
	OT,C	E
	OT,C	h
	OT,C	L
	OT,C	[hl]
	OUTD			;253q	;ED
	OUTI			;243q	;ED
	OUT	nn	;088h, 0D3h 
	PCHL			;0E9h 
	POP	AF
	POP	PSW	;Intel
	POP	BC
	POP	B	;Intel
	POP	DE
	POP	D	;Intel
	POP	hL
	POP	H	;Intel
	POP	IX
	POP	IY
	PUSh	AF
	PUSH	PSW	;Intel
	PUSh	BC
	PUSH	B	;Intel
	PUSh	DE
	PUSH	D	;Intel
	PUSh	HL
	PUSH	H	;Intel
	PUSh	IX
	PUSH	IY
	RAL			;017h 
	RAR			;01Fh 
	RC			;0D8h 
	RETI			;115q	;ED
	RETN			;105q	;ED
	RET			;0C9h 
	RIM			;020h	;8085 only
	RLC#	A
	RLC#	B
	RLC#	C
	RLC#	D
	RLC#	E
	RLC#	H
	RLC#	L
	RLC#	[hl]
	RLC#	[IX+dd]
	RLC#	[IY+dd]
	RLC
	RLD			;157q	;ED
	RL	A
	RL	B
	RL	C
	RL	D
	RL	E
	RL	h
	RL	L
	RL	[hl]
	RL	[IX+dd]
	RL	[IY+dd]
	RM			;0F8h 
	RNC			;0D0h 
	RNZ			;0C0h 
	RPE			;0E8h 
	RPO			;0E0h 
	RP			;0F0h 
	RRC#	A
	RRC#	B
	RRC#	C
	RRC#	D
	RRC#	E
	RRC#	H
	RRC#	L
	RRC#	[hl]
	RRC#	[IX+dd]
	RRC#	[IY+dd]
	RRC			;00Fh 
	RRD			;147q	;ED
	RR	A
	RR	B
	RR	C
	RR	D
	RR	E
	RR	h
	RR	L
	RR	[hl]
	RR	[IX+dd]
	RR	[IY+dd]
	RST	nn	;083h, 0C7h 
	RZ			;0C8h 
	SBB	A
	SBB	B
	SBB	C
	SBB	D
	SBB	E
	SBB	H
	SBB	L
	SBB	M
	SBB	[hl]
;			Subtract with Carry/borrow.
	SBC	A,A
	SBC	A,B
	SBC	A,C
	SBC	A,D
	SBC	A,E
	SBC	A,h
	SBC	A,L
	SBC	A,[hl]
	SBC	A,[IX+dd]
	SBC	A,[IY+dd]
	SBC	A,nn
	SBC	HL,BC
	SBC	HL,DE
	SBC	HL,HL
	SBC	HL,SP
	SBIT	p,A
	SBIT	p,B
	SBIT	p,C
	SBIT	p,D
	SBIT	p,E
	SBIT	p,H
	SBIT	p,L
	SBIT	p,[hl]
	SBIT	p,[IX+dd]
	SBIT	p,[IY+dd]
	SBI	nn	;SUB A,nn
	SHLD	mmmm
	SIM			;030h	;8085 only
	SLA	A
	SLA	B
	SLA	C
	SLA	D
	SLA	E
	SLA	H
	SLA	L
	SLA	[hl]
	SLA	[IX+dd]
	SLA	[IY+dd]
	SPHL			;0F9h 
	SRA	A
	SRA	B
	SRA	C
	SRA	D
	SRA	E
	SRA	H
	SRA	L
	SRA	[hl]
	SRA	[IX+dd]
	SRA	[IY+dd]
	SRL	A
	SRL	B
	SRL	C
	SRL	D
	SRL	E
	SRL	H
	SRL	L
	SRL	[hl]
	SRL	[IX+dd]
	SRL	[IY+dd]
	STAX	B
	STAX	BC		;002h 
	STAX	D
	STAX	DE
	STA	mmmm		;062q 
	STC			;067q 
	STO	A,[bc]		;002q
	STO	A,[de]		;022q
	STO	A,[hl]		;167q
	STO	A,[IX+dd]
	STO	A,[IY+dd]
	STO	A,mmmm		;062q
	STO	B,[hl]		;160q
	STO	B,[IX+dd]
	STO	B,[IY+dd]
	STO	BC,mmmm		;103q	ED
	STO	C,[hl]		;161q
	STO	C,[IX+dd]
	STO	C,[IY+dd]
	STO	D,[hl]		;162q
	STO	D,[IX+dd]
	STO	D,[IY+dd]
	STO	DE,mmmm		;123q	ED
	STO	E,[hl]		;163q
	STO	E,[IX+dd]
	STO	E,[IY+dd]
	STO	H,[hl]		;164q
	STO	H,[IX+dd]
	STO	H,[IY+dd]
	STO	HL,mmmm		;042q
	STO	IX,mmmm		;042q	DD
	STO	IY,mmmm		;042q	FD
	STO	L,[hl]		;165q
	STO	L,[IX+dd]
	STO	L,[IY+dd]
	STO	SP,mmmm		;163q	ED
	STO	nn,[hl]		;066q
	STO	nn,[IX+dd]	;066q	DD
	STO	nn,[IY+dd]	;066q	FD
	SUB	A
	SUB	B
	SUB	C
	SUB	D
	SUB	E
	SUB	H
	SUB	L
	SUB	M
	SUB	[hl]
	SUB	[IX+dd]
	SUB	[IY+dd]
	SUB	nn
	SUI	nn
	XCHG			;0EBh 
	XTHL			;0E3h 
	XOR	A
	XOR	B
	XOR	C
	XOR	D
	XOR	E
	XOR	H
	XOR	L
	XOR	[hl]
	XOR	[IX+dd]
	XOR	[IY+dd]
	XOR	nn
	XRA	A
	XRA	B
	XRA	C
	XRA	D
	XRA	E
	XRA	H
	XRA	L
	XRA	M
	XRA	[hl]
	XRI	nn

	END
