	TITLE	'ACT 6800 Alphabetic Mnemonic List.'
;ACT 6800 Alphabetic Mnemonic List.
	LIST	G

nn:	EQU	0	;    0 <= nn   < 256	08 bit Immediate
zz:			;    0 <= zz   < 256	Direct
mmmm:	EQU	0FFFEh	;    0 <= mmmm < 2**16	Extended
;rel:			;*-126 <= rel  <= *+129	PC Relative

	ABA		;Add B to A

	ADCA	#nn	;Add with Carry
	ADCA	zz
	ADCA	endt
	ADCA	nn,X
	ADCA	,X
	ADCA	X
	ADC A	#nn
	ADC A	zz
	ADC A	mmmm
	ADC A	nn,X
	ADC A	,X
	ADC A	X

	ADCB	#nn
	ADCB	zz
	ADCB	mmmm
	ADCB	nn,X
	ADCB	,X
	ADCB	X
	ADC B	#nn
	ADC B	zz
	ADC B	mmmm
	ADC B	nn,X
	ADC B	,X
	ADC B	X

	ADDA	#nn	;Add
	ADDA	zz
	ADDA	mmmm
	ADDA	nn,X
	ADDA	,X
	ADDA	X
	ADD A	#nn
	ADD A	zz
	ADD A	mmmm
	ADD A	nn,X
	ADD A	,X
	ADD A	X

	ADDB	#nn
	ADDB	zz
	ADDB	mmmm
	ADDB	nn,X
	ADDB	,X
	ADDB	X
	ADD B	#nn
	ADD B	zz
	ADD B	mmmm
	ADD B	nn,X
	ADD B	,X
	ADD B	X

	ANDA	#nn	;Logical And
	ANDA	zz
	ANDA	mmmm
	ANDA	nn,X
	ANDA	,X
	ANDA	X
	AND A	#nn
	AND A	zz
	AND A	mmmm
	AND A	nn,X
	AND A	,X
	AND A	X

	ANDB	#nn
	ANDB	zz
	ANDB	mmmm
	ANDB	nn,X
	ANDB	,X
	ANDB	X
	AND B	#nn
	AND B	zz
	AND B	mmmm
	AND B	nn,X
	AND B	,X
	AND B	X

	ASL	A	;Arithmetic Shift Left
	ASL	B
	ASL	mmmm
	ASL	nn,X
	ASL	,X
	ASL	X

	ASR	A	;Arighmetic Shift Right
	ASR	B
	ASR	mmmm
	ASR	nn,X
	ASR	,X
	ASR	X

	BCC	rel	;Branch if Carry Clear
	BCS	rel	;Branch if Carry Set
	BEQ	rel	;Branch if Equal to zero
	BGE	rel	;Branch if Greater or Equal
	BGT	rel	;Branch if Greater Than
	BHI	rel	;Branch if Higher

	BITA	#nn	;Bit Test
	BITA	zz
	BITA	mmmm
	BITA	nn,X
	BITA	,X
	BITA	X
	BIT A	#nn
	BIT A	zz
	BIT A	mmmm
	BIT A	nn,X
	BIT A	,X
	BIT A	X

	BITB	#nn
	BITB	zz
	BITB	mmmm
	BITB	nn,X
	BITB	,X
	BITB	X
	BIT B	#nn
	BIT B	zz
	BIT B	mmmm
	BIT B	nn,X
	BIT B	,X
	BIT B	X

rel:

	BLE	rel	;Branch if Less or Equal
	BLS	rel	;Branch if Less
	BLT	rel	;Branch if Less Than
	BMI	rel	;Branch if Minus
	BNE	rel	;Branch if Not Equal
	BPL	rel	;Branch if Plus
	BRA	rel	;Branch
	BSR	rel	;Branch to SubRoutine
	BVC	rel	;Branch if Overflow Clear
	BVS	rel	;Branch if Overflow Set

	CBA		;Compare B to A

	CLC		;Clear Carry

	CLI		;Clear Interrupt

	CLR	A	;Clear
	CLR	B
	CLR	mmmm
	CLR	nn,X
	CLR	,X
	CLR	X

	CLV		;Clear Overflow

	CMPA	#nn	;Compare
	CMPA	zz
	CMPA	mmmm
	CMPA	nn,X
	CMPA	,X
	CMPA	X
	CMP A	#nn
	CMP A	zz
	CMP A	mmmm
	CMP A	nn,X
	CMP A	,X
	CMP A	X

	CMPB	#nn
	CMPB	zz
	CMPB	mmmm
	CMPB	nn,X
	CMPB	,X
	CMPB	X
	CMP B	#nn
	CMP B	zz
	CMP B	mmmm
	CMP B	nn,X
	CMP B	,X
	CMP B	X

	COM	A	;Complement
	COM	B
	COM	mmmm
	COM	nn,X
	COM	,X
	COM	X

	CPX	#mmmm	;Compare Index
	CPX	zz
	CPX	mmmm
	CPX	nn,X
	CPX	,X
	CPX	X

	DAA		;Decimal Adjust A

	DEC	A	;Decrement
	DEC	B
	DEC	mmmm
	DEC	nn,X
	DEC	,X
	DEC	X

	DES		;Decrement SP

	DEX		;Decrement X

	EORA	#nn	;Exclusive OR
	EORA	zz
	EORA	mmmm
	EORA	nn,X
	EORA	,X
	EORA	X
	EOR A	#nn
	EOR A	zz
	EOR A	mmmm
	EOR A	nn,X
	EOR A	,X
	EOR A	X

	EORB	#nn
	EORB	zz
	EORB	mmmm
	EORB	nn,X
	EORB	,X
	EORB	X
	EOR B	#nn
	EOR B	zz
	EOR B	mmmm
	EOR B	nn,X
	EOR B	,X
	EOR B	X

	FCC	nn	;Special 6800 pseudos
	FCB	nn
	FDB	mmmm
	RMB	nn

	INC	A	;Increment
	INC	B
	INC	mmmm
	INC	nn,X
	INC	,X
	INC	X

	INS		;Increment SP

	INX		;Increment X

	JMP	mmmm	;Jump
	JMP	nn,X
	JMP	,X
	JMP	X

	JSR	mmmm	;Jump to SubRoutine
	JSR	nn,X
	JSR	,X
	JSR	X

	LDAA	#nn	;Load Accumultor
	LDAA	zz
	LDAA	mmmm
	LDAA	nn,X
	LDAA	,X
	LDAA	X
	LDA A	#nn
	LDA A	zz
	LDA A	mmmm
	LDA A	nn,X
	LDA A	,X
	LDA A	X

	LDAB	#nn
	LDAB	zz
	LDAB	mmmm
	LDAB	nn,X
	LDAB	,X
	LDAB	X
	LDA B	#nn
	LDA B	zz
	LDA B	mmmm
	LDA B	nn,X
	LDA B	,X
	LDA B	X

	LDS	#mmmm	;Load SP
	LDS	zz
	LDS	mmmm
	LDS	nn,X
	LDS	,X
	LDS	X

	LDX	#mmmm	;Load X
	LDX	zz
	LDX	mmmm
	LDX	nn,X
	LDX	,X
	LDX	X

	LSR	A	;Logical Shift Right
	LSR	B
	LSR	mmmm
	LSR	nn,X
	LSR	,X
	LSR	X

	NEG	A	;Negate
	NEG	B
	NEG	mmmm
	NEG	nn,X
	NEG	,X
	NEG	X

	NOP		;No Operation

	ORAA	#nn	;Logical OR
	ORAA	zz
	ORAA	mmmm
	ORAA	nn,X
	ORAA	,X
	ORAA	X
	ORA A	#nn
	ORA A	zz
	ORA A	mmmm
	ORA A	nn,X
	ORA A	,X
	ORA A	X

	ORAB	#nn
	ORAB	zz
	ORAB	mmmm
	ORAB	nn,X
	ORAB	,X
	ORAB	X
	ORA B	#nn
	ORA B	zz
	ORA B	mmmm
	ORA B	nn,X
	ORA B	,X
	ORA B	X

	POP	A	;General Pop
	POP	B

	PSHA		;Push
	PSHB

	PULA		;Pull
	PULB

	PUSH	A	;General Push
	PUSH	B

	ROL	A	;Rotate Left
	ROL	B
	ROL	mmmm
	ROL	nn,X
	ROL	,X
	ROL	X

	ROR	A
	ROR	B
	ROR	mmmm
	ROR	nn,X
	ROR	,X
	ROR	X

	RTI		;Return from Interrupt

	RTS		;Return from Subroutine

	SBA		;Subtract B from A

	SBCA	#nn	;Subtract with Carry
	SBCA	zz
	SBCA	mmmm
	SBCA	nn,X
	SBCA	,X
	SBCA	X
	SBC A	#nn
	SBC A	zz
	SBC A	mmmm
	SBC A	nn,X
	SBC A	,X
	SBC A	X

	SBCB	#nn
	SBCB	zz
	SBCB	mmmm
	SBCB	nn,X
	SBCB	,X
	SBCB	X
	SBC B	#nn
	SBC B	zz
	SBC B	mmmm
	SBC B	nn,X
	SBC B	,X
	SBC B	X

	SEC		;Set Carry

	SEI		;Set Interrupt

	SEV		;Set Overflow

	STAA	zz	;Store Accumulator
	STAA	mmmm
	STAA	nn,X
	STAA	,X
	STAA	X
	STA A	zz
	STA A	mmmm
	STA A	nn,X
	STA A	,X
	STA A	X

	STAB	zz
	STAB	mmmm
	STAB	nn,X
	STAB	,X
	STAB	X
	STA B	zz
	STA B	mmmm
	STA B	nn,X
	STA B	,X
	STA B	X

	STS	zz	;Store SP
	STS	mmmm
	STS	nn,X
	STS	,X
	STS	X

	STX	zz	;Store X
	STX	mmmm
	STX	nn,X
	STX	,X
	STX	X

	SUBA	#nn	;Subtract Accumulator
	SUBA	zz
	SUBA	mmmm
	SUBA	nn,X
	SUBA	,X
	SUBA	X
	SUB A	#nn
	SUB A	zz
	SUB A	mmmm
	SUB A	nn,X
	SUB A	,X
	SUB A	X

	SUBB	#nn
	SUBB	zz
	SUBB	mmmm
	SUBB	nn,X
	SUBB	,X
	SUBB	X
	SUB B	#nn
	SUB B	zz
	SUB B	mmmm
	SUB B	nn,X
	SUB B	,X
	SUB B	X

	SWI		;Software Interrupt

	TAB		;Transfer A to B

	TAP		;Transfer A to P

	TBA		;Transfer B to A

	TPA		;Transfer P to A

	TST	A	;Test
	TST	B
	TST	mmmm
	TST	nn,X
	TST	,X
	TST	X

	TSX		;Transfer SP to X

	TXS		;Transfer X to S

	WAI		;Wait for Interrupt

endt:	RMB	0


	END
	