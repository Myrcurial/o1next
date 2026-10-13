	TITLE	'Disk I/O routines.'

;	Disk interface definitions and functions.

;	1792 functions.
DML	=	4		;= 15 ms delay on function
LTRKB	=	3125		;length of a track
;	Note: Shugart says LTRKB = 3125...
NRTRYS	=	4		;Number of retries
MSECB	=	10h		;Multi-sector r/w bit

;	FUNCTION CODES
D.RES	=	00H		;RESTORE
D.SEK	=	14H		;SEEK
D.STP	=	20H		;STEP
D.STPI	=	40H		;STEP IN
D.STPO	=	60H		;STEP OUT
D.RDS	=	80H		;READ SECTOR
D.WRTS	=	0A0H	;WRITE SECTOR
D.RDA	=	0C0H	;READ ADDRESS
D.RDT	=	0E0H	;READ TRACK
D.WRTT	=	0F0H	;WRITE TRACK
D.FINT	=	0D0H		;FORCE INTERRUPT

;	Disk status and command registers
D.CMDR	=	H.FDC		;Disk command reg	(write)
D.STSR	=	H.FDC		;Status reg		(read)
D.TRKR	=	D.CMDR+1	;track reg
D.SECR	=	D.CMDR+2	;Sector reg
D.DATR	=	D.CMDR+3	;Data reg		(r/w)

;	Status definitions
BS.BSY	=	0		;Busy
DS.BSY	=	1 shl BS.BSY

BS.DRQ	=	1
DS.INX	=	1 shl BS.DRQ	;Index mark detected
DS.DRQ	=	DS.INX		;DR is full on read, empty on write

BS.TK0	=	2
DS.TK0	=	1 shl BS.TK0
DS.LSD	=	DS.TK0		;lost data

DS.CRC	=	08h		;CRC error in ID field

BS.SEK	=	4
DS.SEK	=	1 shl BS.SEK	;Seek error
DS.RNF	=	DS.SEK		;Record NOT found

DS.HDL	=	20h		;Head loaded
DS.WTF	=	DS.HDL		;Write fault

DS.WTP	=	40h		;Write protected
DS.NRY	=	80h		;Drive NOT ready

;	Disk timing counts
D.DEL	=	20		;Delay after function
	page
SDMA:
	;Set DMA
SETDMA:
;	Entry	BC = DMA address
	STO	BC,DMADR
	RET
	space	4,10
SETTRK:
	;Set track
;	Entry	BC = track
	STO	BC,SAVTRK
	RET
	space	4,10
SETSEC:
	;Set Sector
;	Entry	C= sector number (1 to MSEC)
	MOV	A,C
	STO	A,SAVSEC
	RET
	space	4,10
HOME:
;Home selected disk drive
	XRA	A			;reset track to 0
	STO	A,SAVTRK
	RET
	PAGE
SDRV:
	;Select Drive
;	Entry	SDISK= drive
;	Exit	A= 0, if drive is ready
;	Calls	OPBD, DELAY
;	Uses	A,B
	proc
	LD	A,SDISK
SDRV1:
	LK	HL,DSKSWP	;disk drive swap cell
	XOR	[hl]		;swap A for B if DSKSWP=1
	AND	1		;Can only be 0 or 1
	CMP	1
	JRNZ	:2		;if not drive 1
	LDK	A,40h
:2:
	ADI	40h
	MOV	C,A
	LD	A,PIABD
	MOV	B,A
	AND	1100_0000b	;get drive bits only
	CMP	C
	JZ	RDSKD		;if drive already selected

;	Check to see if this drive is the same as the last
;	one selected.
;	IF true, go to 3
;	else
;	  Save current trk register in LDSEL and
;	  set trk reg to last track used for newly selected
;	  drive
;	end
	LD	A,LDSEL		;last selected disk
	CMP	C
	JRZ	:3		;if same drive
	MOV	A,C
	STO	A,LDSEL		;set to new drive
	PUSH	BC
	LDK	HL,LDTRK
	LD	C,[hl]		;get last accessed track for new drive
	LD	A,D.TRKR	;get current track
	STO	A,[hl]		;save in table
	MOV	A,C
	STO	A,D.TRKR	;set trk register to last selected
	POP	BC

;	Set drive select perserving vio offset values
:3:
	CALL	RDSKD		;RESET CONTROLLER
	LDK	B,5		;NUMBER OF TRIES
:5:
	LDK	A,250
	CALL	DELAY
	LK	A,250		;2ND DELAY
	CALL	DELAY
	LD	A,D.STSR
	AND	DS.INX
	RZ			;IF INDEX
	DJNZ	:5		;KEEP TRYING
	OR	80H OR DS.INX	;INDICATE NOT READY
	RET

	space	4,10
DDRV:
	;Deselect drive
;	Entry	SDISK = current disk drive
	LD	A,PIABD
	AND	1_1111b
	MOV	C,A
	JMP	OPBD		;deselect last drive
	page
PSEKC:
	;Perform seek type command
;	Entry	A= command to perform without r1, and r0.
;		PSEKC will or in the low two bits as defined
;		by SEKDEL.
;	Exit	A= last value of D.STSr
	LDK	HL,SEKDEL
	OR	[hl]		;or in delay time for seek
	CALL	FDSK		;function disk
	RNZ			;if Drive NOT ready
	JMP	WBUSY
	space	4,10
SELDSK:
	;Select disk in register C
	MOV	A,C		;drive to home
	CALL	SDRV1		;C= drive
	JR	HOMED1

HOMED:
	;Home disk drive
;	Entry	SDISK= drive
;	Exit	A=0 if drive on home.
	proc
	CALL	SDRV		;select drive
HOMED1:
	LDK	A,D.RES
	CALL	PSEKC		;perform seek command
	CMP	-1
	JRZ	SKEX1		;if error
	BIT	BS.SEK,A
	JRNZ	SKEX1		;if error
	BIT	BS.TK0,A
	JRZ	:4		;if NOT home
	IF	ODEBUG
	CALL	LDSKS1		;list status ****
	ENDIF
	XRA	A		;clear A
SKEX1:
	PUSH	AF
	LDK	A,-1
	STO	A,DACTVE	;start counter
	CALL	STAT17		;save disk controller regs
	POP	AF
	RET

;	Here if drive NOT homed, possible NOT ready
:4:
	AND	80h
	JR	SKEX1
	space	4,10
SEEK:
	;Seek to track defined by SAVTRK
;	Entry	SAVTRK set to track
;		SAVSEC set to sector number
;	Exit	A= 0, if no error, else status
;		MUST NOT destroy DE, HL pair
	proc
	CALL	SDRV		;select drive

;	Here if drive already selected
;	Check to see if SEEK is necessary by
;	comparing SAVTRK to controller track
;	register
	LD	A,SAVTRK
	STO	A,D.DATR	;set track wanted
	MOV	C,A
	LD	A,D.TRKR
	CMP	C
	JRZ	:8		;if on track

;	Disk seek required, function controller
;	with SEEK command
	LDK	A,5

SEEKA:
	STO	A,RTRY		;update retry count
	LDK	A,D.SEK
	CALL	PSEKC		;perform seek command
	MOV	C,A
	AND	DS.CRC or DS.SEK
	JRNZ	:10		;if error


;	Now read-address and verify on-track
	CALL	DRDAS		;read address
	JRNZ	:10		;if error
	LDK	HL,DSTSB
	LD	A,SAVTRK
	CMP	[hl]
	JRZ	:8		;if ON track
	LD	A,RTRY
	DEC	A
	JRNZ	SEEKA		;if not max retrys

;	here if seek error
:10:
	MOV	A,C
	ORI	80h		;indicate movement error
	JR	SKEX1

;	Now set the sector register to requested
;	Sector
:8:
	CALL	WBUSY		;wait for FDC quiescence
	LD	A,SAVSEC
	STO	A,D.SECR	;set sector register
	XRA	A		;indicate good
	RET
	space	4,10
DRDAS:
	;Read Address info.
;	Exit	D.STSB = data bytes
;		MUST NOT destroy DE pair
	proc
	LDK	A,D.RDA
	CALL	FDSK		;function disk

;	Get status bytes
	LDK	HL,DSTSB
	LDK	B,6

	DI
	PUSH	DE		;save DE
:2:
	LDK	DE,4000		;time out
:3:
	LD	A,D.STSR
	BIT	BS.BSY,A
	JRZ	RWEX		;if possible error
	BIT	BS.DRQ,A
	JRNZ	:4		;if data ready
	DEC	DE
	MOV	A,D
	OR	E
	JRNZ	:3		;if NOT time out
	LK	C,SEKTMO	;seek time out
	JR	RWEX		;error exit

:4:
	LD	A,D.DATR
	STO	A,[hl]		;save byte
	INC	HL
	DJNZ	:2		;if not done
	POP	DE
	XRA	A		;indicate good
	EI ! RET
	space	4,10
DREAD:
	;Read disk sectors.
;	Entry	SDISK= drive
;		B = number of sectors to read
;		    Number from 1 to MSEC
;		DMADR= FWA for data.
;	Exit	DSTSB= A= 0, if no error
;		HL = next DMA
;	Uses	All registers
	proc
	MOV	D,B		;save sectors
	CALL	SEEK		;seek to track, set sector
	JRNZ	RWEX1		;if seek error
	MOV	B,D
	LDK	C,0
	PUSH	BC
	LDK	A,D.RDS
	DEC	D
	JRZ	:3		;if NOT multi-sectors
	OR	MSECB		;add 'm' cit
:3:
	CALL	FDSK
	POP	BC
	CMP	-1
	JRZ	RWEX1		;if drive NOT ready

;	Now xfer bytes from controlles to DMA.
	DI
	LD	HL,DMADR
:5:
	PUSH	BC
	ldk	bc,lsecb
	call	dmard
	jrnz	rwex		;if error
;	LDK	B,low LSECB
;:6:
;	LD	A,D.STSR
;	BIT	BS.BSY,A
;	JRZ	RWEX		;if possible error
;	BIT	BS.DRQ,A
;	JRZ	:6		;if no data
;	LD	A,D.DATR
;	STO	A,[hl]
;	INC	HL
;FOR EDIT
;	DJNZ	:6		;if not all data

;	Now check if multi sector

	POP	BC
	DJNZ	:5		;continue
	XRA	A
	JR	RWEX1

;	here on error
RWEX:
	CALL	STAT17		;save disk controller regs
	POP	DE		;restore stack
	OR	80h		;if busy cleared, indicate with 80h
RWEX1:
	OR	A		;set status
	PUSH	AF
	LDK	A,-1
	STO	A,DACTVE
	POP	AF
	EI ! RET
	space	4,10
DWRT:
	;Write to disk
;	Entry	SDISK= drive
;		B= Number of sectors to xmit.
;		DMADR= FWA of data
;	Exit	same as DREAD
;	Uses	All registers
	proc
	MOV	D,B
	CALL	SEEK
	JRNZ	RWEX1		;if seek error
	MOV	B,D
	PUSH	BC
	LDK	A,D.WRTS
	DEC	D
	JRZ	:3		;if NOT multi-sectors
	OR	MSECB		;add 'm' bit
:3:
	CALL	FDSK
	POP	BC

;	Now xfer bytes to controller from DMA.
	DI
	LD	HL,DMADR
:5:
	PUSH	BC
	LDK	BC,LSECB	;length of std sector
:6:
	CALL	XDD		;xfer to disk
	JRNZ	RWEX		;if error

;	Now check if multi sector
	POP	BC
	DJNZ	:5		;continue
	XRA	A
:8:
	JR	RWEX1

	PAGE
DMARD:
;TRANSFER DATA FROM CONTROLER TO MEMORY
;ENTRY
;BC	=	LENGTH
;HL	=	FWA OF BUFFER

;EXIT
;HL	=	NEXT ADDRESS
;A	=	80 IF BUSY DROPPED BEFORE BC=0
	PROC
	LDK	DE,D.STSR

:LOOP:	LD	A,[DE]
	BIT	BS.BSY,A
	JRZ	:1		;DROPPED BUSY BEFORE BC = 0
	BIT	BS.DRQ,A
	JZ	:LOOP		;if no data
	LD	A,D.DATR
	STO	A,[HL]		;TO MEMORY
	INC	HL
	DEC	BC
	MOV	A,B
	OR	C
	JNZ	:LOOP		;if not done
	RET

:1:	ORI	080H
	RET
	PAGE
XDD:
;Xfer data from memory to disk
;ENTRY
;BC	=	LEANTH
;HL	=	FWA

;EXIT
;HL	=	NEXT ADDR
;A	=	80 IF BUSY DROPPED BEFORE BC=0

	PROC
	LDK	DE,D.STSR

:LOOP:	LD	A,[DE]
	BIT	BS.BSY,A
	JRZ	:1
	BIT	BS.DRQ,A
	JZ	:LOOP		;if no data
	LD	A,[HL]
	STO	A,D.DATR	;send to controller
	INC	HL
	DEC	BC
	MOV	A,B
	OR	C
	JNZ	:LOOP		;if not done
	RET

:1:	ORI	80H
	RET
	page
FDSK:
	;Function disk routine
;	All functions for DSK controller SHALL do so by using
;	this routine.  FDSK sets DACTVE to 0 indicating activity
;	UPTIM uses this cell to turn off select if one sec has
;	occurred.
;	Entry	A= function code
;	Exit	A= 0, if chip accepted function
;		else, A=-1, indicating time-out, See WBUSY
;	Uses A, B, C
	proc
	MOV	B,A		;save function code
	LD	A,PIABD
	AND	1100_0000b
	JRNZ	:1		;if drive active
	PUSH	BC
	CALL	SDRV		;reselect drive
	POP	BC
:1:
	CALL	WBUSY		;Wait for busy to clear
	RM			;if will NOT clear busy

;	Controller NOT busy, issue command
	MOV	A,B
	STO	A,D.CMDR	;function drive

;	Wait for busy to be set
	LDK	C,0
:2:
	LD	A,D.STSR
	RAR			;DS.BSY
	JRC	:3		;if chip went busy
	DEC	C
	JRNZ	:2		;if not time-out
	JR	WBUSYX		;exit, error

;	Set DACTVE indicating activity on drive
:3:
	LDK	A,-1
	STO	A,DACTVE
	XRA	A			;ZERO A
	RET
	space	4,10
WBUSY:
	;Wait for Busy to clear
;	Exit	A= -1, if time out occurred,
;		else
;		A= last status and is positive.
;	Uses	A, C
	proc
	PUSH	BC
	LDK	BC,0
:1:
	LD	A,D.STSR
	RAR			;DS.BSY
	JRNC	:1A		;if NOT busy, proceed
	DEC	BC
	MOV	A,B
	OR	C
	JRNZ	:1		;if not time-out
WBUSYX:
	LDK	A,-1		;indicate error, drive NOT ready
	POP	BC
	OR	A		;set flags
	RET

:1A:
	RAL			;restore A
	POP	BC		;restore BC
	AND	7Fh		;make sure its positive
	RET
	space	4,8
RDSKD:
	;Reset PIA and disk controller
;	selecting drive specified by C
;	Entry	C= drive
;		B= PIABD
	MOV	A,B
	AND	0001_1111b	;get vio offset only
	OR	C
	MOV	C,A
	CALL	OPBD		;function PIO-b
;	JMP	RDSKC

RDSKC:
	;reset disk controller
;	Entry	None
;	Exit	Busy cleared.
;		A= 0.
	LDK	A,D.FINT
	STO	A,D.STSR	;clear controller
	XRA	A		;clear A and flags
	RET

ODER:
	;Output disk error to console
;	Entry	DE= FWA of message
;		SDISK = drive with error
	PUSH	DE
	CALL	OCRLF		;new line
	LD	A,SDISK
	ADD	A,'A'
	MOV	C,A
	CALL	CO		;output drive name
	CALL	O2SP
	POP	DE		;get message
	JMP	ESTR

DERR:
	;Output disk system error
;	Entry	A= status from controller
;	Exit	error output
	PUSH	DE
	PUSH	HL
	PUSH	BC
	PUSH	AF
	LDK	DE,DERMSG
	CALL	ESTR		;output error
	POP	AF		;get status value
	CALL	PBBH		;output status
	CALL	O2SP
	LD	A,SAVTRK
	CALL	PBBH		;output track
	LDK	C,','
	CALL	COUT		;output comma
	LD	A,D.TRKR
	CALL	PBBH		;output controller track
	CALL	O2SP
	LD	A,SAVSEC
	CALL	PBBH		;output sector
	LDK	C,','
	CALL	COUT		;output comma
	LD	A,D.SECR
	CALL	PBBH		;output controller sector

;	Update error counter
	LD	HL,ERCNT
	INC	HL
	STO	HL,ERCNT	;update error count

;	Clear controller
	CALL	RDSKC		;reset disk controller

;	Restore regs
	POP	BC
	POP	HL
	POP	DE
	RET

DERMSG:
	DBE	cr,lf
	DCE	'Dsk ERR (sts trk sec)- '

	space	4,10
STAT17:
	;save 179x status
	;called when disk error discovered:
	;...saves 179x regs in high RAM.
	PUSH BC ! PUSH DE ! PUSH HL
	LK	HL,D.STSR	;1st (lowest) 179x register
	LK	DE,R179x	;register save area
	LK	BC,4		;move 4 bytes
	LDIR
	POP  HL ! POP  DE ! POP  BC
	RET
;	END	OCCROM6?.???
