
	TITLE	'Monitor Main Loop.'
	DISDIM			;disable DIM
	JMP	BMON		;reset/restart

USER:	;Exit to user program from 'G' command
	EI ! RET		;Exit from G command
ILINT:	;Here on unknown interrupt
	DI
	DISDIM
	STO	SP,IESTK	;save interrupted proc stack
	LDK	SP,ISTK		;insure stack in RAM
	ALPUSH			;save all registers
	LDK	A,'I'
	STO	A,MPCHR		;set prompt to inter level

EXITI:	;Exit interrupt code via exiting to RAM and
;	then enable or disable ROM code depending on
;	the value contained in ROMRAM cell.
	LD	A,H.VIO		;clear interrupt
	LD	A,ROMRAM
	OR	A
	JNZ	RORAME		;if return to RAM, CPM
	ALLPOP
	LD	SP,IESTK	;get users stack back
	EI ! RET

BMON:	DI
	LDK	SP,ROMSTK
	XRA	A
	STO	A,SEC6
	STO	A,SDISK		;set disk to drive 0
	STO	A,VRTOFF	;OFFSET TO ZERO USED IN COUT
	CALL	HINT		;Initialize hardware
	LDK	HL,(high MRAM)*100h
	STO	HL,SSAVE	;Initialize User stack in ram
	LDK	HL,0
	STO	HL,LDSEL	;clear select and last track
	LDK	DE,IBMSG
	CALL	OSTR		;Output initial message
	JR	BMON1		;continue
	ORG	NMIA
	DI
	JMP	BMON		;NMI
	page
;	Main start up for Monitor.
;	Get 1st user response.
BMON1:	CALL	CI		;Get next character
	CMP	CR
	LK	HL,DSKSWP	;disk swap cell
	LK	C,0		;boot from A:
	STO	C,[hl]		;set to A=A, B=B
	JZ	CBOOT		;if cold boot
	INC	[hl]	;swap drives: A=B, B=A
	CMP	'"'
	JZ	CBOOT		;if cold boot off of B
	CMP	'D'-40h
	JZ	DIAG		;if enter debugger
	JR	BMON
	page
HINT:
;Initialize all dependent hardware.
;Entry	None.
;Exit	All hardware initialized.
;Set flag indicating in ROM
	PROC
	ENAROM
	DISDIM			;disable DIM bit
	LDK	HL,GKEY
	STO	HL,INTBL+(4*2)	;set keyboard interrupt
	IM2
	LDK	A,high INTBL
	MOV	I,A		;set interrupt page

;	Initialize keyboard
	XRA	A
	STO	A,0EFF0H
	STO	A,BELCNT	;clear bell timer cell
	STO	A,LKEY		;clear last key cell
	STO	A,ECHOP		;clear echo to list dev
	STO	A,ESCH		;clear ESC hold flag
	LDK	HL,KEYLST
	LDK	B,KL_LEN*KLE_LEN
:1:
	STO	A,[HL]
	INC	HL
	DJNZ	:1

	CMA
	STO	A,IDAY		;set date invalid for SETUP.COM
	STO	A,KEYLCK	;indicate NOT locked
	LDK	A,VLL
	STO	A,LLIMIT	;set max line limit

;	Now function PIA to set starting address
;	and continue to move display window over
;	the first display line.
;	Set cursor as 1-40 on 1st line.
	CALL	SPAO		;set up for output
	LDK	C,VFLO
	CALL	OPAD		;set for -10 char positions

;	Set beginning line to 0
	XRA	A
	STO	A,PIABD		;set data reg
	MOV	C,A
	CALL	OPBD		;set line

;	Intialize IEEE port
	ldk	c,1
	call	ie.co

;	Reset-Master clear the SIO (ACIA)
	LK	C,SI.S16	;select 16x clock for 1200 baud
	CALL	SIRST		;reset

;	Set default seek to as defined by systext
	LDK	A,SEEKTM	;defined from systext
	STO	A,SEKDEL	;set seek step rate

;	Set default prompt char
	LDK	A,PMCHR
	STO	A,MPCHR		;set up default
	EI ! RET

romjp1:	ldk	de,1633h	;offset in bios jump table
	jr	biojp
romjp2:	ldk	de,1636h	;offset in bios jump taple
biojp:	ld	hl,ccpadr
	add	hl,de		;form address
	jmp	[hl]

COPYR:	DB	'c. 1981 OCC'


	page
	ORG	100h
;	Jump vector for debugger and CP/M
RVEC:	JMP	CBOOT		;cold boot
	JMP	WBOOT		;warm boot
	JMP	SKEY		;keyboard status
	JMP	CI		;keyboard input
	JMP	COUT		;console output
	JMP	LIST		;list output
	JMP	PUNCH		;punch output
	JMP	READER		;reader input

;	Disk I/O
	JMP	HOME
	JMP	SELDSK		;select disk
	JMP	SETTRK		;set track
	JMP	SETSEC		;set sector
	JMP	SETDMA		;set DMA
	JMP	DREAD		;Disk read
	JMP	DWRT		;Disk write
	JMP	SLST		;List device status
	RET ! NOP ! NOP		;Sector translate

;	End of standard CP/m functions
RORAME:	JMP	romjp1
	JMP	romjp2
	JMP	FORMT		;Format one track
	JMP	SIRST		;SIO reset
	JMP	IE.CO		;IEEE	Control Out
	JMP	IE.SI		;	Status In
	JMP	IE.GTS		;	Go To Standby
	JMP	IE.TC		;	Take Control
	JMP	IE.OIM		;	Output Interface Message
	JMP	IE.ODM		;	Output Device Message
	JMP	IE.IDM		;	Input Device Message
	JMP	IE.PP		;	Parallel Poll
	JMP	VLDDR		;VIDEO BLOCK MOVE
	JMP	VLDIR
	JMP	STODIM		;STO reg B IN [HL]
	JMP	XDD		;DMA from memory to disk
	JMP	DMARD		;DMA from disk to memory	
	PAGE
OSTR:
;OUTPUT STRING TO CONSOLE
;ENTRY
;DE	=	FWA OF SOURCE
;NOTE :		OSTR RECOGNIZES 7F AS AN ESCAPE SEQUENCE
;TO REPEAT CHAR N TIMES.  FORMAT IS:
;7F, REPEAT COUNT, CHAR

	PROC
	LD	A,[DE]
	OR	A
	PUSH	AF
	AND	07FH
	CMP	07FH
	MOV	C,A
	JRNZ	:4		;IF NOT REPEAT
	INC DE ! LD A,[DE] ! DEC A
	MOV	B,A		;REPEAT COUNT
	INC DE ! LD A,[DE]	;GET REPEAT CHAR
	MOV	C,A
:2:	CALL	CO		;OUTPUT CHAR
	DJNZ	:2		;IF NOT DONE
:4:	CALL	CO		;OUTPUT IT
	INC	DE
	POP	AF
	JP	OSTR		;IF NOT DONE
	RET
	PAGE
	TITLE	'MONITOR ROM CONSTANTS.'
IBMSG:
	DB	'Z'-40h,lf,lf,lf,lf
	DB	ESC,VSGH
	DB	'Q'-40h
	DB	07Fh, 24, 'W'-40h
	DB	'E'-40h
	DB	ESC,VEGH

	DB	cr,lf
	DB	ESC,VSGH,1, ESC,VEGH
	DB	'  '
	DB	ESC,'l'
	DB	'Osborne System ONE.'
	DB	ESC,'m'
	DB	'   '
	DB	ESC,VSGH,4, ESC,VEGH

	DB	cr,lf
	DB	ESC,VSGH
	DB	'A'-40h
	DB	07Fh,24,' '
	DB	'D'-40h
	DB	ESC,VEGH

	DB	cr,lf
	DB	ESC,VSGH
	DB	'A'-40h
	DB	'     '
	DB	ESC,')'
	DB	' MONITOR 1.3  '
	DB	ESC,'('
	DB	'     '
	DB	'D'-40h
	DB	ESC,VEGH

	DB	cr,lf
	DB	ESC,VSGH
	DB	'Z'-40h
	DB	07Fh, 24, 'X'-40h
	DB	'C'-40h
	DB	ESC,VEGH

	DB	cr,lf,lf,lf
	DB	'Insert disk in Drive '
	DB	ESC,'l'
	DB	'A'
	DB	ESC,'m'
	DB	' and press RETURN'
	DC	'.'

;	END	OCCROM1?.???
