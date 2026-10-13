	TITLE	'ACT 6502 Alphabetic Mnemonic List.'
;ACT 6502 Alphabetic Mnemonic List.
	LIST	G

nn:	EQU	0	;    0 <= nn   < 256	Immediate
zz:			;    0 <= zz   < 256	Zero Page
mmmm:	EQU	0FFFFh	;    0 <= mmmm < 2**16
;rel:			;*-126 <= rel  <= *+129



	ADC	#nn	;Add with Carry
	ADC	zz
	ADC	zz,X
	ADC	[zz,X]
	ADC	[zz],Y
	ADC	mmmm
	ADC	mmmm,X
	ADC	mmmm,Y

	AND	#nn	;Logical And
	AND	zz
	AND	zz,X
	AND	[zz,X]
	AND	[zz],Y
	AND	mmmm
	AND	mmmm,X
	AND	mmmm,Y

	ASL	A	;Arithmetic Shift Left
	ASL	zz
	ASL	zz,X
	ASL	mmmm
	ASL	mmmm,X
	
	BCC	rel	;Branch if Carry Clear
	BCS	rel	;Branch if Carry Set
	BEQ	rel	;Branch if Equal	(Z=1)

	BIT	zz	;Bit test
	BIT	mmmm
rel:
	BMI	rel	;Branch if Minus	(S=1)
	BNE	rel	;Branch if Not Equal	(Z=0)
	BPL	rel	;Branch if Plus		(S=0)
	BRK		;Software Interrupt
	BVC	rel	;Branch if no Overflow	(V=0)
	BVS	rel	;Branch if Overflow	(V=1)

	CLC		;Clear Carry flag
	CLD		;Clear Decimal flag
	CLI		;Clear Interrupt mask (EI)
	CLV		;Clear Overflow flag

	CMP	#nn	;Compare
	CMP	zz
	CMP	zz,X
	CMP	[zz,X]
	CMP	[zz],Y
	CMP	mmmm
	CMP	mmmm,X
	CMP	mmmm,Y

	CPX	#nn	;Compare X
	CPX	zz
	CPX	mmmm
	CPY	#nn	;Compare Y
	CPY	zz
	CPY	mmmm

	DEC	zz	;Decrement memory
	DEC	zz,X
	DEC	mmmm
	DEC	mmmm,X
	DEX		;Decrement X
	DEY		;Decrement Y

	EOR	#nn	;Exclusive OR
	EOR	zz
	EOR	zz,X
	EOR	[zz,X]
	EOR	[zz],Y
	EOR	mmmm
	EOR	mmmm,X
	EOR	mmmm,Y

	INC	zz	;Increment memory
	INC	zz,X
	INC	mmmm
	INC	mmmm,X
	INX		;Increment X
	INY		;Increment Y

	JMP	mmmm	;Jump
	JMP	[mmmm]
	JSR	mmmm	;Jump Subroutine

	LDA	#nn	;Load Accumulator
	LDA	zz
	LDA	zz,X
	LDA	[zz,X]
	LDA	[zz],Y
	LDA	mmmm
	LDA	mmmm,X
	LDA	mmmm,Y
	LDX	#nn	;Load X
	LDX	zz
	LDX	zz,Y
	LDX	mmmm
	LDX	mmmm,Y
	LDY	#nn	;Load Y
	LDY	zz
	LDY	zz,X
	LDY	mmmm
	LDY	mmmm,X

	LSR	A	;Logical Shift Right
	LSR	zz
	LSR	zz,X
	LSR	mmmm
	LSR	mmmm,X

	NOP		;No operation
	ORA	#nn	;OR Accumulator
	ORA	zz
	ORA	zz,X
	ORA	[zz,X]
	ORA	[zz],Y
	ORA	mmmm
	ORA	mmmm,X
	ORA	mmmm,Y

	PHA		;Push A
	PHP		;Push status flags
	PLA		;Pull (Pop) A
	PLP		;Pull status

	ROL	A	;Rotate Left
	ROL	zz
	ROL	zz,X
	ROL	mmmm
	ROL	mmmm,X
	ROR	A	;Rotate Right
	ROR	zz
	ROR	zz,X
	ROR	mmmm
	ROR	mmmm,X

	RTI		;Return from Interrupt
	RTS		;Return from Subroutine
	SBC	#nn	;Subtract with Borrow/Carry
	SBC	zz
	SBC	zz,X
	SBC	[zz,X]
	SBC	[zz],Y
	SBC	mmmm
	SBC	mmmm,X
	SBC	mmmm,Y
	SEC		;Set Carry flag
	SED		;Set Decimal flag
	SEI		;Set Interrupt mask (DI)

	STA	zz	;Store Accumulator
	STA	zz,X
	STA	[zz,X]
	STA	[zz],Y
	STA	mmmm
	STA	mmmm,X
	STA	mmmm,Y
	STX 	zz	;Store X
	STX	zz,Y
	STX	mmmm
	STY	zz	;Store Y
	STY	zz,X
	STY	mmmm
	TAX		;Move X <- A
	TAY		;Move Y <- A
	TSX		;Move X <- SP
	TXA		;Move A <- X
	TXS		;Move SP <- X
	TYA		;Move A <- Y

	END
