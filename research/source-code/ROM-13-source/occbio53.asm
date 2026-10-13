	page
;*****
;	Revisions:
;	RWC	20OCT81		warm boot makes dir 2 files across
;	RWC	19OCT81		included baud rate and screen size initalization
;	RWC	14OCT81		change iobyte to variable
;				modified auto start feature
;	YNS 	20AUG81		change iobyte defaults
;
;*****

	;	B o o t   C P / M   f r o m   d i s k.
;
;	The CBOOT entry point gets control from the cold start
;	loader and is responsible for the basic system initial-
;	ization.  This includes outputting a sign-on message and
;	initializing the following page zero locations:
;
;	   0,1,2: Set to the warmstart jump vector.
;	       3: Set to the initial IOBYTE value.
;	       4: Default and logged on drive.
;	   5,6,7: Set to a jump to BDOS.
;	   40-41: Points to where Date and Time are kept
;
;	Register C must contain the selected drive, which is
;	zero to select the A drive.  The exit address is to
;	the CCP routine.
;
;
;	The WBOOT entry point gets control when a warm start
;	occurs, a ^C from the console, a jump to BDOS (function
;	0), or a jump to location zero.  The WBOOT routine reads
;	the CCP and BDOS from the appropriate disk sectors.
;	WBOOT must also re-initialize locations 0,1,2 and 5,6,7.
;	The WBOOT routines exits with the C register set to the
;	appropriate drive selection value.  The exit address
;	is to the CCP routine.
;

CBOOT:	;Entry	A= drive to boot off of.
	MOV	B,A		;save requested drive
	DISROM
	MOV	A,B		;restore requested drive
	STO	A,CDISK		;force requested drive
	LDK	SP,CCP

;**********************

	ld	a,iobite	;get iobyte value
	STO	A,IOBYTE	;Set I/O byte to default
	ld	a,brate
	mov	c,a
	call	sbaud		;set baud rate
	lda	scrsze
	sta	llimit		;set screen size
	ldk	a,1
	JR	BCCP		;Do CP/M

WBOOT:				;Warm boot
	LDK	SP,CCP
	CALL	HOME		;flush any buffer

BCPM:	LDK	DE,ROMVEC+3*1	;Set ROM vector address
	LDK	BC,CCP
	CALL	ROMJMP
	ORA	A
	JRNZ	BCPM		;If error in read
	mvi	a,2		;indicate warm boot

BCCP:	;Entry	A = 01, if cold boot
;		A = 02, if warm boot
	PUSH	AF		;Save flags
	LDK	BC,DBUF		;Set default data transfer address
	CALL	SETDMA
	LDK	HL,HSTBUF
	STO	HL,DMADR	;set ROM DMA address

;	Clear console control ESC cell
	XRA	A
	STO	A,ESCH		;clear ESC
	inc	a		;a=1  make directory list two files across
	sto	a,ccp+04b2h	;change to ccp

;	Set-up low core pointer cells
	LDK	A,0C3h		;Store jumps in low memory
	STO	A,0
	STO	A,5
	LDK	HL,BIOS+3
	STO	HL,1
	LDK	HL,BDOS
	STO	HL,6
	LDK	HL,IDAY
	STO	HL,TIMPTR	;set date-time pointer
	LDK	HL,CAUTO

;Digital Research has informed SORCIM that CP/M 2.2
;CANNOT be booted off B:.
;Manipulation of CDISK is kept here to avoid the bugs
;which would appear with its disappearance.
;Booting off B: is accomplished with the RAM cell DSKSWP.
	pop	bc		;cold/warm indicator in b
	ld	a,acmd
	and	b
	jrz	done
	ld	a,[hl]
	ORA	A
	JRZ	DONE
	LDK	DE,CCP+7
	LDK	B,0
	MOV	C,A
	LDIR			;Move command line to buffer
	ldk	de,0
	jr	done1

SIGNON:
	DB	'Z'-40h
	DB	'Osborne Computer System'
	DB	CR,LF,MSIZE/10+'0',MSIZE mod 10 + '0'
	DB	'K CP/M ',VERS/10+'0','.',VERS mod 10 + '0'
	DB	CBIOSV+'@',CR,LF,0

done:
	mvi	a,2
	cmp	b
	jrz	done0
	ldk	hl,signon
	call	print
done0:
	ldk	de,3
done1:
	ldk	hl,ccp
	add	hl,de
	ld	a,cdisk
	mov	c,a
	jmp	[hl]

;	Endx	OSBBIOS5.asm
