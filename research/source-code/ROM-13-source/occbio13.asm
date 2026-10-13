	page
;*****
;	Revisions:
;	YNS	18AUG81		change bios jump vector to call new routines
;	RWC	05OCT81		standardize cpm jump table (change calls to jumps)
;	RWC	16OCT81		added function key table and user defined switches
;
;*****


MRTRY:	=	5		;Maximum number of retries.
msize:	=	60
;ccp:	=	(msize-8)*1024	;location of ccp
CCP:	=	100H
bios:	=	ccp+1600h
bdos:	=	ccp+806h


	MSG	'Assemblying BIOS for LWA of ', LWAMEM,'h.'

;	CP/M to host disk constants

HSTSIZ:	=	256		;Blocking/Deblocking buffer size
FPYSIB:	=	2048/128	;Sectors in floppy disk block

;	CP/M disk control block equates which define the
;	disk types and maximum storage capability of each
;	disk type.

DSKS1:	=	0	;Single density, single sided.

S1DSM:	=	((40-3)*2*10)/FPYSIB

;	BDOS constants on entry to write

WRALL:	=	0		;write to allocated
WRDIR:	=	1		;write to directory
WRUAL:	=	2		;write to unallocated
	space	4,10
;	ROM equates.

ENROM:	=	0		;Port to enable ROM
DIROM:	=	1		;Port to disable ROM

	page
;	Macro for generating Control Blocks for disk drives
;	The format of these disk control blocks are as follows:
;	16 bits = -> translation table.
;	48 bits = Work area for CP/M.
;	16 bits = -> DIRBUF.
;	16 bits = -> Parameter block.
;	16 bits = -> check vector.
;	16 bits = -> allocation vector.

NDSK:	SET	0		;Number of disk drives
NOFDD:	SET	0		;Number of floppy disk drives
ALVSZ:	SET	0		;Allocation vector size
CSVSZ:	SET	0		;Check vector size

	LIST	D,G,M
DPHGEN	MACRO	TYPE,XLATE,DIRBUF,DPBADR
NDSK:	SET	NDSK+1
	DW	%2
	DW	0,0,0
	DW	%3
	DW	%4
	DW	CSV+CSVSZ
	DW	ALV+ALVSZ
NOFDD:	SET	NOFDD+1
CSVSZ:	SET	CSVSZ+(64/4)
ALVSZ:	SET	ALVSZ+((S1DSM+7)/8)
	ENDM

;	Make sure Systext agrees with assembled size

	space	4,10
;	Macro for generating the Disk Parameter Blocks.
;
;	Disk type definition blocks for each particular mode.
;	The format of these areas are as follow:
;	8 bit = disk type code
;	16 bit = Sectors per track
;	8 bit  = Block shift
;	8 bit  = BS mask
;	8 bit  = Extent mask
;	16 bit = Disk size/1024 - 1.
;	16 bit = Directory size.
;	16 bit = Allocation for directory.
;	16 bit = check area size.
;	16 bit = offset to first track.

DPBGEN	MACRO	TYPE,SPT,BSH,BSM,EXM,DSM,DIRSIZ,ALVMSK,OFFSET
	DB	%1
	DW	%2
	DB	%3,%4,%5
	DW	%6-1,%7-1,REV (%8)
	DW	(%7+3)/4
	DW	%9
	ENDM
	page
;	The following jump table defines the entry points
;	into the CBIOS for use by CP/M and other external
;	routines; therfore the order of these jump cannot
;	be modified.  The location of these jumps can only
;	be modified by 400h locations, which is a restriction
;	of MOVCPM.

	ORG	BIOS

	jmp	CBOOT		;Cold boot
	jmp	WBOOT		;Warm boot
	jmp	cnsta		;Console status (input)
CONIN:	jmp	cnin		;Console input
CONOUT:	jmp 	cnout		;Console output
LIST:	jmp	lst		;List output
PUNCH:	jmp	pnch		;Punch output
READER:	jmp	rdr		;Reader input
	JMP	HOME		;Set track to zero
RSELDK:	JMP	SELDSK		;Select disk unit
	JMP	SETTRK		;Set track
	JMP	SETSEC		;Set sector
	JMP	SETDMA		;Set Disk Memory Address
RRDK:	JMP	READ		;Read from disk
RWDK:	JMP	WRITE		;Write onto disk
LISTST:	jmp	lstst		;Return LST: device status
	JMP	SECTRN		;Sector translation routine

;	Extensions
RRI:	JMP	ROMRI
	JMP	ROMJMP
FMTJ:	CALL	ROMCDE		;Rom resident call
SBAUD:	CALL	ROMCDE

;	IEEE-488 vectors
ieb1c:	CALL	ROMCDE		;Control Out
ieb2c:	CALL	ROMCDE		;Status In
ieb3c:	CALL	ROMCDE		;Go To Standby
ieb4c:	CALL	ROMCDE		;Take Control
ieb5c:	CALL	ROMCDE		;Output Interface Message
ieb6c:	CALL	ROMCDE		;Output Device Message
ieb7c:	CALL	ROMCDE		;Input Device Message
ieb8c:	CALL	ROMCDE		;Parallel Poll
	call	romcde		;extensions
	call	romcde		;  for
	call	romcde		;    memory-mapped video
	jmp	acictl		;hook for serial command port write
	jmp	acistat		;hook for serial status port read
;
;;;;;;;;;;;;;;;;;;;;;;;
;
;	This area is reserved data storage area for 
;	the set-up program to install printer drivers,
;	function keys, auto boot command, iobyte value,
;	and auto horizontal scroll flag
;						RWC
;;;;;;;;;;;;;;;;;;;;;;;
;
iobite:	db	40h		;default to serial printer=40h
				;	  parallel printer=80h
				;	      IEEE printer=c0h
prnter:	db	00h		;default to standard serial=0
				;Qume 		ETX/ACK    =1
				;Diablo		XON/XOFF   =2
ahsenb: db	TRUE		;auto horizontal scroll enable
brate:	db	si.120		;default baud rate = 1200
scrsze:	db	128		;default screen size = 128
;
xltbl:	dw	cntrl0		;Fixed length table
	dw	cntrl1		;contains pointers
	dw	cntrl2		;to strings 
	dw	cntrl3		;to decode
	dw	cntrl4		;function keys
	dw	cntrl5
	dw	cntrl6
	dw	cntrl7
	dw 	cntrl8
	dw	cntrl9
	dw	up
	dw	right
	dw	down
	dw	left
	dw	eotbl		;end of table address
;
acmd:	db	1		;auto command = 0 ignore auto boot
				;	      = 1 auto on cold boot
				;	      = 2 auto on warm boot
				;	      = 3 auto on both
cauto:	db	cautol		;length of auto command here
	db	'AUTOST '	;auto command goes here
cautol:	=	*-cauto-1
;
cntrl0:	db	'0'		;Variable length table 
cntrl1:	db	'1'		;is placed here by set-up
cntrl2: db	'2'		;program, with xlttbl
cntrl3:	db	'3'		;pointing to the entries
cntrl4:	db	'4'		;
cntrl5:	db	'5'		;Default values for the
cntrl6:	db	'6'		;control numerics
cntrl7:	db	'7'		;are the numbers on the keys
cntrl8:	db	'8'
cntrl9:	db	'9'		;
up:	db	'K'-40h		;Default values 
right:	db	'L'-40h		;for the cusor
down:	db	'J'-40h		;keys are standard
left:	db	'H'-40h		;values for CP/M
eotbl:	=	*
;
				;space reseverd for full function
				;key decoding and 16 byte auto
				;boot command
	
	