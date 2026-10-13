	TITLE	'B o o t   C P / M   f r o m   d i s k.'

;	The CBOOT entry point gets control from the cold start
;	loader and is responsible for the basic system initial-
;	ization.  This includes outputting a sign-on message and
;	initializing the following page zero locations:

;	   0,1,2: Set to the warmstart jump vector.
;	       3: Set to the initial IOBYTE value.
;	       4: Default and logged on drive.
;	   5,6,7: Set to a jump to BDOS.

;	Before any data is read in, the maximum drive step rate
;	must be determined:
;		1. set slowest seek
;		2. home drive A:
;		3. seek track #12
;		4. speed up step rate
;		5. seek 4 tracks outward (12=>8,8=>4,4=>0)
;		6. if error, slow down step rate by 1,
;			load in CP/M, boot, exit, etc.
;		7. else try faster step rate
;			(if not fastest, GOTO #4 above)
;		8. if stepping fastest rate, boot CP/M.

;	The exit address is to the CCP routine.


;	The WBOOT entry point gets control when a warm start
;	occurs, a ^C from the console, a jump to BDOS (function
;	0), or a jump to location zero.  The WBOOT routine reads
;	the CCP and BDOS from the appropriate disk sectors.
;	WBOOT must also re-initialize locations 0,1,2 and 5,6,7.
;	The WBOOT routines exits with the C register set to the
;	appropriate drive selection value.  The exit address
;	is to the CCP routine.

;	Disk layout Definition
;	--Note: Tracks 0, 1, and 2 are reserved for CPM.--
;	Track 0-----------
;	  1 thru 8	CCP		2k
;	  9 thru 10	BDOS
;	Track 1-----------
;	  1 thru 10	BDOS
;	Track 2-----------
;	  1 thru 2	BDOS		3.5k
;	  3 thru 10	CBIOS		2k
	page
CBOOT:
;Entry
;C= drive to boot from

;Exit	A= drive
	Proc
	LDK	A,MSEC		;read 10 sectors of trk 3
	STO	A,TEM
	MOV	A,C
	EX	AF,AF'

;SET "CCPADR"

	CALL	HOMED		;HOME DRIVE
	ORA	A
	JRNZ	:2		;IF ERROR

	LDK	HL,0D000H
	STO	HL,DMADR	;SET DMA
	STO	A,SAVTRK	;set track
	INC	A
	STO	A,SAVSEC	;set sectoR
	MOV	B,A
	CALL	RDTRY		;READ SECTOR ONE
	JRZ	:1		;IF GOOD

:2:	LDK	DE,BRDEMG	;REPORT BOOT READ ERROR
	CALL	ODER
	JR	CBOOT		;try again

:1:	LD	A,0D002H	;get ccp address/100h + 3
	sub	3
	LDK	L,0
	mov	h,a

;BOOT SYSTEM

	EX	AF,AF'		;RECOVER DRIVE TO BOOT FROM
	PUSH	HL
	CALL	BCPM		;boot system
	POP	HL
	ld	a,sdisk
	STO	HL,CCPADR
	ldk	de,1600h	;offset for bios
	add	hl,de		;address of bios in hl
	jmp	[hl]		;enter cpm
	PAGE
WBOOT:
	Proc
	LDK	A,2		;don't read CBIOS
	STO	A,TEM		;save sectors
	LD	A,CDISK		;Current logged in drive
	LD	HL,CCPADR
	PAGE
BCPM:
;Boot CPM from disk
;ENTRY
;A	=	DRIVE TO BOOT FROM
;HL	=	DMA ADDR FOR CCP
;TEM	=	Number of sectors to read from track 3.

;EXIT
;A	=	0 IF NO ERROR
;ZBIT	=	SET IF NO ERROR

	proc
	STO	A,SDISK		;Set drive to boot from
	STO	HL,DMADR	;SET DMA

BCPM1:	LDK	B,5		;RETRY
:HLOOP:	PUSH	BC
	CALL	HOMED		;home drive
	POP	BC
	OR	A
	JRZ	:1		;IF GOOD
	DJNZ	:HLOOP		;LOOP
	JR	BCPME		;if drive NOT ready

:1:	STO	A,SAVTRK	;set track
	INC	A
	STO	A,SAVSEC	;set sector=1

;	Read in 1st two tracks

	LDK	B,2
:TLOOP:	PUSH	BC
	LDK	B,MSEC
	CALL	RDTRY		;read 1st track
	POP	BC
	JRNZ	BRDE		;if read error
	STO	HL,DMADR	;update DMA
	LDK	HL,SAVTRK
	INC	[HL]		;SAVTRK=SAVTRK+1
	DJNZ	:TLOOP		;if not all tracks

;	Now read in requested number of sectors
;	from track 3.

	LD	A,TEM
	MOV	B,A
	CALL	RDTRY		;read requested number of sectors
	JRNZ	BRDE		;if read error

	LDK	HL,HSTACT
	LDK	DE,(LOGSEC-HSTACT)+1
	CALL	FILLZ		;clear Host BIOS cells
	LDK	A,0FFh
	STO	A,UNASEC
	LDK	A,VLL-1
	STO	A,LDTRK		;set other drive NOT int
	XRA	A		;Clear error indicator
	RET
	PAGE
RDTRY:
;READ AND RETRY ROUTINE
;ENTRY
;B	=	NUMBER OF SECTORS TO READ

;EXIT
;ZBIT	=	SET IF NO ERROR
	PROC
	LDK	C,5

:1:	PUSH	BC
	CALL	DREAD
	POP	BC
	RZ			;IF GOOD
	DEC	C
	JRNZ	:1		;LOOP
	ORA	A		;SET FLAGS FOR A REG
	RET
	PAGE
BCPME:
;HERE ON DRIVE NOT READY
	LDK	DE,DNRMSG

BCPME1:
;Output error message and return to BCPM

	CALL	ODER
	JR	BCPM1		;try again

BRDE:
;HERE ON BOOT READ ERROR

	LDK	DE,BRDEMG
	JR	BCPME1		;output error

DNRMSG:	DCE	'HOME ERR'
BRDEMG:	DCE	'READ ERR'

;	END	OCCROM2?.???
