	TITLE	'Keyboard and Console Routines.'

;	Assembly constant
@KEY	=	1		;production keyboard

;	Control keys
CBELL	=	'G'-40h		;Ring the Bell
MCUP	=	'K'-40h		;Move cursor up
MCDOWN	=	LF		;Move cursor down
MCLEFT	=	BKS		;Move cursor left
MCRIGH	=	'L'-40h		;Move cursor right
VCLRS	=	'Z'-40h		;Clear and home cursor
VHOME	=	'^'-40h		;Home Cursor


;	Escape keys
VLOCK:	=	'#'		;Lock Keyboard
VUNLK	=	'"'		;Unlock Keyboard
VCAD:	=	'='		;Cursor Addressing
VSAD:	=	'S'		;Screen Addressing
VINC:	=	'Q'		;Insert Char
VDELC:	=	'W'		;Delete char
VINL:	=	'E'		;Insert line
VDELL:	=	'R'		;Delete line
VCEOL:	=	'T'		;Clear to end of line
VSHI:	=	')'		;Start half intensity
VEHI:	=	'('		;end
VSUL:	=	'l'		;Start underline
VEUL:	=	'm'		;end

VSGH:	=	'g'		;Start graphics
VEGH:	=	'G'		;End

;ARROW KEYS

UP	=	8AH
RIGHT	=	8BH
DOWN	=	8CH
LEFT	=	8DH

SKEY:
	;Get status of keyboard
;	Exit	Cbit set if no data ready
	LD	A,KEYLCK
	OR	A
	RZ			;if locked keyboard
	LD	A,LKEY
	ORA	A		;CHECK FOR ZERO
	RZ
	ORI	0FFH		;IF NOT ZERO MAKE 0FFH
	RET			;IF DATA
	space	4,10
CI:
RKEY:
	;Read next key from keyboard
;	Exit	A= last key
	proc
	CALL	SKEY
	JRZ	RKEY		;if NO data
	DI
	LD	A,LKEY		;GET CHARACTER
	MOV	C,A
	XRA	A
	STO	A,LKEY		;clear key from hold
	MOV	A,C
	EI
	RET
	space	4,10
NORM:
	;Normalize to UPPER case
;	Entry	A= char
;	Exit	A= CHAR
	CMP	'a'
	RC			;if upper
	CMP	'z'+1
	RNC			;if not lower
	SUI	'a'-'A'
	RET

REPD	=	45		;initial rep delay
REPK	=	5		;repeat constant

	page
UPTIM:
	;Update time via 60hz interrupt
;	Time is kept in video memory as
;	hhmmss	(3 locations)
;	Routine also checks to see if the disk drive motor
;	should be turned off by updating DACTIVE
;	...Routine ALSO checks to see if bell is currently
;	ringing: if so, decrement counter.
;	if counter turns zero, shut off bell.
	Proc
	LDK	HL,BELCNT
	XOR	A
	OR	[hl]	;cell=zero ?
	JRZ	:2	;if bell now off
	DEC	[hl]	;...bell is on. decrement counter
	JRNZ	:2	;if bell should stay on awhile yet
	LD	A,PIABD
	AND	1101_1111b	;clear bell bit
	MOV	C,A
	CALL	OPBD
:2:
	DEC	HL		;HL => DACTVE
	LD	A,[hl]
	OR	A
	JRZ	:3		;if inactive
	DEC	[hl]		;reset delay
	CZ	DDRV		;if deselect drive
:3:
	DEC	HL		;HL => SEC6
	DEC	[hl]
	RNZ			;if not 1 sec transition
	STO	59,[hl]		;60th tick is NOW
	XOR	A		;A:=0, CY:=0 for DAA
	DEC	HL		;HL => SECS
	LD A,[hl] ! INC A ! DAA ! STO A,[hl]
	CMP	60h
	RC			;if not 60 secs
	STO	0,[hl]		;reset seconds
	DEC	HL
	LD A,[hl] ! INC A ! DAA ! STO A,[hl]
	CMP	60h
	RC			;if not 60 minutes
	STO	0,[hl]
	DEC	HL
	LD A,[hl] ! INC A ! DAA ! STO A,[hl]
	CMP	25h
	RC			;if time <= 24:59:59
	STO	1,[hl]
	RET
	page
CO:
	;Output routine for monitor
;	Entry	C= char
;		CO will process ^p to toggle
;		echo to list device ala cpm.
;	Exit	C=C=A.
	proc
	MOV	A,C
	CMP	'P'-40h
	JRNZ	:5		;if not toggle echo list
	LD	A,ECHOP
	CMA
	STO	A,ECHOP		;toggle list echo
:2:
	MOV	A,C		;perserve A
	RET

:5:
	CALL	COUT		;output char
	LD	A,ECHOP
	OR	A
	JRZ	:2		;if no echo to list
	JMP	LIST		;echo it
	page

;	Bit definitions for ESCH flag byte
;	Note Bit 7 is currently free.
EF_X:	=	64		;B6= extegting X-coordinate
EF_SCR:	=	32		;B5= Screen/Cursor Addressing
EF_ADR:	=	16		;B4= expegting address-chr
EF_ESC: =	8		;B3=$last char was ESC
EF_UN:  =	4		;B2= Underline mode
EF_HA:  =	2		;B1= Half Intensity mode
EF_GR:  =	1		;B0= Graphics mode
EF_MSK: =	EF_UN+EF_HA+EF_GR  ;Mask to get mode.
	space	4,10
;	Vector (branch) table for video output mode selection
;	controlled by ESCH mode
ESCHTB:
	DW	VNORM		;0 Normal mode
	DW	VGRAPH		;1 Graphics mode
	DW	VHALF		;2 Half intensity mode
	DW	VHA_GR		;3 Half and graphics
	DW	VUNDER		;4 Underline mode
	DW	VUN_GR		;5 Under and graphics
	DW	VUN_HA		;6 Under and half intensity
	DW	VUN_HA_GR	;7 Under and half and graphics
	space	4,10
VALIDE:
	;Valid ESC-Sequence Table
;	3 bytes per entry:ascii char , "DW"-Vector.
;	no. of entries is VALETS
;	Following body of table is 2 byte No-Match adrs
	DB	VCAD !	DW	ESCCAD	;Cursor Addressing
	DB	VSAD !	DW	ESCSAD	;Screen Addressing
	DB	VSGH !	DW	ESCSGR  ;Set graphics mode
	DB	VEGH !	DW	ESCCGR	;Clr graphics mode
	DB	VSHI !	DW	ESCSHA	;Set half int. mode
	DB	VEHI !	DW	ESCCHA	;Clr half int. mode
	DB	VSUL !	DW	ESCSUN  ;Set underline mode
	DB	VEUL !	DW	ESCCUN	;Clr underline mode

	DB	VCLRS !	DW	ESCZZ	;Clear screen to blanks
	DB	VINC !	DW	EINSRT	;Insert char
	DB	VDELC !	DW	EDELC	;Delete char
	DB	VINL !	DW	ESCEE	;Insert line
	DB	VDELL !	DW	ESCRR	;Delete line
	DB	VCEOL !	DW	EEOL	;Clear to end of line
	DB	VLOCK !	DW	ESCLCK	;Lock Keyboard
	DB	VUNLK !	DW	ESCULK	;Unlock Keyboard
:end:
	DW	COUT2	;No Match exit
;	Ignore char upon undefined ESC-Sequence
;	(to treat undefined char after ESC as a regular
;	 data char, should go to COUT2).
VALETS:	=	(:end-VALIDE)/3		;# of entries in table
	space	4,10
VALIDC:
	;Valid control character table
;	3 bytes per entry: Ascii char , "DW"- Vector
;	no. of entries is VALCTS
;	Following body of table is 2 byte No-Match adrs
	DB	CR	! DW  VC_CR	;carriage return routine
	DB	LF	! DW  VC_LF	;line feed
	DB	BKS	! DW  VC_BKS	;back space
	DB	MCRIGH	! DW  VC_MCRT	;move cursor right
	DB	MCUP	! DW  VC_MCUP	;move cursor up
	DB	CBELL	! DW  VC_BEL	;Ring bell
	DB	VCLRS	! DW  VC_CLRS	;clear screen
	DB	VHOME	! DW  VC_HOME	;Cursor Home

	DW	VOUT97		;No match--ignore undef control char

VALCTS:	=	((*-2)-VALIDC)/3	;Number of valid entries
	page
COUT:
	;General output routine to Video Screen
;	ENTRY	C=Character,  CURS=Cursor,  ESCH=Flag+Mode
;	EXIT	CURS & ESCH updated,  A=Character
;		(bc, de, hl preserved)

;	ESCH is flag + mode byte as follows
;	=00       Normal mode & Last chr Esc flag false
;	=08       Normal mode & Last chr Esc flag True
;	=01,02,04 Mode is Graphics, Half, or Under, respectively
;		   , and Last chr Esc flag is False.
;	=3,5,6,7    As above, but mode is combination
;	=9-15     Last chr Esc flag True;otherwise like 1-7.

	proc

;RESET VETICAL OFFSET WITH VRTOFF

	PUSH	AF
	PUSH	BC
	LD	A,PIABD		;PRESENT VALUE
	AND	11100000B	;HOUSEKEEPING
	MOV	B,A
	LD	A,VRTOFF	;LAST VERTICAL OFFSET
	AND	00011111B	;ONLY VIDIO
	ORA	B		;ADD HOUSEKEEPING
	MOV	C,A
	CALL	OPBD		;SET OFFSET
	POP	BC
	POP	AF

	PUSH	HL
	PUSH	DE
	PUSH	BC
	LD	HL,CURS		;HL will usually be cursor/
	LD	A,ESCH
	MOV	B,A		;B will be ESCH for a while
	AND	EF_ESC		;test flag bit
	JRNZ	PSTESC		;IF last chr was ESC

;Current chr is NOT ESCaped. Is this chr ESC?

	MOV	A,C		;Chr
	CMP	ESC
	MOV	A,B		;(A=ESCH)
	JRZ	:ESC		;if this chr = ESC
	space	4,10
;Here with A=B= ESCH
:out:
	PUSH	HL
	LDK	HL,ESCHTB
	AND	EF_MSK		;Mode bits only
	ADD	A,A		;Times two
	MOV	E,A
	LDK	D,0		;DE = offset
	ADD	HL,DE		;HL = tbl addrs
VECTOR:
				;entry point.  note hl on stack.
	LD	A,[HL]		;1st byte (low order adrs)
	INC	HL
	LD	H,[HL]		;2nd byte (hi order adrs)
	MOV	L,A		;HL=adrs from table
	XTHL			;Restore hl from stack ;stack=tbl adrs
	MOV	A,C		;Chr.  note B=ESCH byte value
	RET			;enter routine per table adrs.

COUT2:
	MOV	A,B		;recall ESCH value
	JR	:out		;output chr per current settings

:ESC:
	;Current chr is ESC. Set flag and exit
	OR	EF_ESC		;indicate last char= ESC
	STO	A,ESCH
	JMP	VOUT97		;Exit
	space	4,17
PSTESC:
	;Last chr was ESC
;Entry
;A	=	EF_ESC
;B	=	ESCH
;C	=	Char to output
;HL	=	curs
	Proc
	BIT	4,B		;is this chr really an address?
	JRNZ	SETXY		;...if chr is part of an addr

;no cursor/screen addressing in effect:
	XOR	B		;Clr EF_ESC bit (for next time)
	MOV	B,A		;Set up B = ESCH byte value.
	STO	A,ESCH
	PUSH	HL		;save Curs
	LDK	HL,VALIDE	;Branch table adrs
	LDK	E,VALETS	;Table size
	MOV	A,C		;Chr to A
	JR	LOOKUPB		;Go to routine to branch per tbl
	space	4,15
VNORM:
	;NORMAL mode character processing.
;	Entry	A= char to output
;		HL=curs
	CMP	' '
	JRC	:2		;IF control chr
VBRIGH:
	DI ! ENADIM		;9th bit memory
	STO	BRTBIT,[hl]		;set this chr BRIGHT
	DISDIM ! EI
	JMP	VOUT80

:2:
	PUSH	HL		;Save Curs
	LDK	HL,VALIDC	;Branch table adrs
	LDK	E,VALCTS	;Table size
;	JMP	LOOKUPB		;Scan table of valid control chrs
;				;and branch to appropriate routine.
	space	4,20
LOOKUPB:
	;Logic to scan 3 byte branch table
;	NOT a subroutine---do not CALL.
;	Entry	HL =1st byte of table (match code)
;			(2nd,3rd bytes = branch adrs)
;			(table repeats [3 byte entries])
;		E is table size (no. of entries)
;			(table body is followed with
;			2 byte "No-Match" adrs)
;		Stack has HL saved as top entry.
;		C = char
;		A = value to scan for possible match
	CMP	[HL]
	INC	HL	;(2nd byte of this 3 byte entry)
	JRZ	VECTOR	;If match process
	INC	HL	;(3rd byte of this entry)
	INC	HL	;1st byte of next entry
	DEC	E	;Dec count of entries remaining
	JRNZ	LOOKUPB	;Continue thru body of table
	JR	VECTOR	;No-Match.  hl=points to vector
	page
;	Processing for modes other than normal.
;	--------------------------------------

;VGRAPH	=	VOUT80	;Normal mode EXCEPT: cntl chrs are printed

VUNDER:
	;Underline only
	CMP	' '
	JRC	VNORM		;if cntl-chr, process as normal
;	JR	VUN_GR		;continue

VUN_GR:
	;Underlined Graphics
	OR	80h		»underline bit
	JR	VBRIGH		;set this chr BRIGHT

VUN_HA:
	;Underline and Half intensity
	CMP	' '
	JRC	VNORM		;if cntl-chr, process as normal
;	JR	VUN_HA_GR

VUN_HA_GR:
	;Underline, Half Intensity, Graphics
	OR	80h	;set underline bit
;	JR	VHA_GR

VHALF:
	;Half Intensity
	CMP	' '
	JRC	VNORM		;if cntl-chr, process as normal
;	JR	VHA_GR

VÈA_GR:
	;C=Chr, HL=Curs
	DI
	ENADIM
	STO	DIMBIT,[hl]		;set dim field bit
;	LD	E,[hl]			;diagnostic
	DISDIM
	EI
	JMP	VOUT80		;continue
	space	4,22
SCREEN:
	;SetXY for Screen movement
;	Entry	B= ESCH
;		A= new co-ord val, NO OFFSET
	Proc
	BIT	6,B
	JRNZ	:sX	;if X-coordinate

:sY:
	AND	0001_1111b	;mod 32
	MOV	C,A
	STO	A,VRTOFF	;SET VERTICAL OFFSET FOR COUT
	LD	A,PIABD
	AND	1110_0000b
	OR	C
	MOV	C,A
	CALL	OPBD		;set Y coordinate
	JR	:exitY

:sX:
	ADD	A,A		;double A
	ADD	A,VFLO		;PIA A-reg magic offset constant
	AND	1111_1110b	;clear bit 0 => no 1/2 chr shift
	MOV	C,A
	CALL	OPAD		;set X coordinate
	CBIT	5,B		;finished screen-addressing
	JR	:exitX
	space	4,10
SETXY:
	;Set X-Y value for Cursor/Screen Addressing
;	Entry	HL= cursor_addr
;		B = ESCH
;		C = chr
;	Exit	to VOUT90; ESCH updated
	CALL	UN_CUR
	LDK	A,-(' ')
	ADD	C	;remove cursor bias
	BIT	5,B	;cursor/screen addressing?
	JRNZ	SCREEN	;if screen addressing

;cursor addressing:
	ADD	HL,HL	;shift HL left
	BIT	6,B	;X/Y coordinate?
	JRNZ	:cX	;if X coordinate

:cY:
	MOV	H,A	;save
	LD	A,PIABD
	ADD	H	;offset by start-Y co-ord of video
	RAR		;bit0(A) -> CY, shift A right
	RR	L	;CY -> bit7(L)
	OR	0F0h	;turn on upper nybl
	MOV	H,A	;HL= new cursor addr
;	JR	:exitY

:exitY:
	LDK	A,0100_0000b	;next addr-chr will be X-coord
	OR	B
	JR	:exit2

:cX:
	RAL		;trash 7th bit
	SRA	H	;bit0(H) -> CY, bit7 stays 1
	RAR		;... CY -> bit7(A)
	MOV	L,A
;	JR	:exitX

:exitX:
	LDK	A,EF_MSK
	AND	B	;finished addressing: reset addr bits
:exit2:
	STO	A,ESCH
	JMP	VOUT90
	page
;	Control Code character processing

VC_HOME: ;Home Cursor
	Proc
	CALL	UN_CUR
	LD	A,PIABD
	RAR			;bit0 => CY
	LDK	L,0
	RR	L		;CY => bit7, trash bit0
	MOV	H,A
	JR	:fixhl		;HL := HL or F000h
	space	4,7
VC_MCUP:      ;Move Cursor Up.
;		A=C=Chr=MCUP.  HL=Curs.
	CALL	UN_CUR
	PUSH	HL		;old cursor must be on stack
	LDK	BC,(-VLL)
	JR	:fwa		;...at this entry point
	space	4,28
VC_BKS:
	;HL=Curs=current (old) char
	CALL	UN_CUR		;clear 80h bit
	LDK	A,7Fh
	AND	L
	JRZ	:wrap		;if must wrap from col 0 to LLIMIT
	DEC	HL
	JR	VOUT90		;Exit

:wrap:
	PUSH	HL		;save old cursor
	LDK	BC,-(VLL+1)
	ADD	HL,BC		;HL = prev_line, (-1)st column
	LD	A,LLIMIT	;LLIMIT = #columns on screen
	MOV	C,A
	LDK	B,0
:fwa:
	ADD	HL,BC
	XTHL			;get old cursor, save new
	ADD	HL,HL		;shift line# into H reg.
	LD	A,PIABD
	OR	1110_0000b	;A = line# of UL corner
	CMP	H		;set Zflag: @home?
	POP	HL		;get new cursor...
	JRNZ	:fixhl		;if NOT @video home
	LDK	BC,(24*VLL)	;wrap constant
	ADD	HL,BC
:fixhl:
	LDK	A,0F0h
	OR	H		;modulo result: keep cursor
	MOV	H,A		;inside video memory.
	JR	VOUT90
	space	4,8
VC_BEL:
	;Ring the bell via setting PIAB 2**5 bit
	LD	A,PIABD
	OR	0010_0000b	;bell bit
	MOV	C,A
	CALL	OPBD		;function PIAB
	LDK	A,30		;ring bell for 30 ticks
	STO	A,BELCNT	;... = 1/2 second
	JR	VOUT97		;exit no change
	space	4,10
VC_CLRS: LDK	HL,FWAVM
	CALL	CLRLN		;clear 1st line
	LDK	BC,LVMEM-VLL
	PUSH	DE
	POP	IX
	CALL	VLDIR		;clear remaining lines
	LD	A,PIABD		;Reset for 1st line of display mem
	AND	not(1_1111b)
	MOV	C,A
	CALL	OPBD
	XRA	A		;ZERO A
	STO	A,VRTOFF	;SET VERTICAL OFFSET FOR COUT
	LDK	HL,FWAVM	;new cursor
	JR	VOUT90		;Exit
	space	4,8
VC_CR:
	CALL	UN_CUR		;erase cursor
	LDK	A,80h		;Carriage Return
	AND	L
	MOV	L,A
	JR	VOUT90

VC_LF:
	CALL	DO_LF		;Line Feed
	JR	VOUT90
	space	4,3
VC_MCRT	;Move Cursor Right
	CALL	UN_CUR
	LD	A,[hl]
;	JR	VOUT80		;re-echo current chr
	page
;	Exit points for COUT

;	Here to store new data and to update cursor
VGRAPH:
VOUT80:
	STO	A,[hl]		;This exit path stores A (new char)
	MOV	E,L
	CBIT	7,E		;E = col(cursor)
	LD	A,LLIMIT
	DEC	A		;A = last_legal_col
	SUB	E		;A = last_legal_col - col(cur)
	JRNZ	VOUT85		;if not @LLIMIT
	LDK	A,80h
	AND	L
	MOV	L,A		;do CR...
	CALL	DO_LF2		;...and LF.
	JR	VOUT90

VOUT85:
	INC	HL		;move cursor

;	Here if NO cursor update
VOUT90:
	LD	A,[HL]		;This exit path turns on 80h bit

;	Here if new data already in A
VOUT95:
	RAL			;Make this chr cursor
VOUT96:
	CMC			;invert cursor bit
	RAR
	STO	A,[hl]
	STO	HL,CURS		;update cursor

;	Here if no change to cursor, restore reg and exit
VOUT97:
	POP	BC
	POP	DE
	POP	HL
	MOV	A,C		;Exit with A=chr
	RET			;return, end of cout subr.
	space	4
:First	=	VOUT97 - (127 + 2)	;earliest possible JR

:Last	=	VOUT80 + (128 - 2)	;latest possible JR
	page
ESC_LCK: ;Lock Keyboard
	Proc
	XOR	A
	JR	:2

ESC_ULK: ;Unlock Keyboard
	LDK	A,0FFh
:2:
	STO	A,KEYLCK
	JR	VOUT97
	space	4,5
EEOL:
	;Erase to end of line
	PUSH	HL	;save cursor
	CALL	CLRLN
	POP	HL
	JR	VOUT90
	space	4,12
ESC_CAD:
	;Cursor Addressing
	LDK	A,EF_MSK
	AND	B
	OR	EF_ESC or EF_ADR	;next chr will be Y-coord
:exit3:
	STO	A,ESCH
	JR	VOUT97

ESC_SAD:
	;Screen Addressing
	LDK	A,EF_MSK
	AND	B
	OR	EF_ESC or EF_ADR or EF_SCR
	JR	:exit3
	page
;Subroutine for use with EDELC and EINSRT:
;Calculate #chrs to move; if move zero chrs, never return.
	Proc
:calc:
	LDK	A,VLL-1	;A= max #chrs to be moved
	MOV	C,L
	CBIT	7,C	;C = col(cursor)
	SUB	C	;A = #chrs to move
	JRZ	:end	;if move zero characters
	MOV	C,A
	LDK	B,0	;BC = #chrs to move
	RET

:end:
	POP	HL	;trash return_addr
	POP	HL	;cursor_addr
	JR	VOUT90
	space	4,14
EDELC:
	;Delete Character
	PUSH	HL		;save cursor_addr
	CALL	:calc		;calculate BC
;	MOV	D,H
;	MOV	E,L		;DE = cursor_addr
	PUSH	HL
	POP	IX
	INC	HL		;HL = cursor_addr + 1
	CALL	VLDIR		;move characters
	STO	' ',[hl]	;last chr becomes blank
	DI ! ENADIM		;enable 9th bit memory
	DEC	HL		;HL = last chr on this line
	STO	BRTBIT,[hl]		;set chr BRIGHT
	DISDIM ! EI		;main memory
	POP	HL		;restore cursor_addr
	JR	VOUT90		;next
	space	4,14
EINSRT:
	;Insert Character
	CALL	UN_CUR
	PUSH	HL	;save cursor_addr
	CALL	:calc	;calculate BC
	LDK	A,7Fh
	OR	L
	MOV	L,A	;HL = last_chr on this line
;	MOV	E,A
;	MOV	D,H	;DE = HL
	PUSH	HL
	POP	IX
	DEC	HL
	CALL	VLDDR	;do move
	POP	HL	;restore cursor
	LD	A,[hl]	;get underline bit of this chr.
	RAL		;into CY
	LDK	A,' ' shl 1	;change this chr to ' '
	JR	VOUT96		;exit
	page
;	ESC-Sequence processing.
	Proc
ESCSGR:
	LDK	A,EF_GR		;ESC-g
	JR	:125		;set graphics mode.

ESCSHA:
	LDK	A,EF_HA		;ESC-)  set half intensity
	JR	:125		;go set flag bit

ESCSUN: LDK	A,EF_UN		;ESC-l  set underline
:125:
	OR	B		;Reg B is ESCH Byte value
:130:
	STO	A,ESCH		;store desired value.
	JR	VOUT97		;Exit

ESCCGR: LDK	A,NOT EF_GR	;ESC-G  Clear graphics mode
	JR	:140		;go clear ESCH bit

ESCCHA: LDK	A,NOT EF_HA	;ESC-(  Clear half intensity
	JR	:140

ESCCUN: LDK	A,NOT EF_UN	;ESC-m  Clear underline
:140:
	AND	B		;Clear bit
	JR	:130		;Go store ESCH byte

ESCZZ:	=	VC_CLRS	;ESC-Z  Clear screen -same as
				;Control-Z routine.
	page
ESCRR:
	;Delete Line
ESCEE:
	;Insert Line
;	Entry	HL = cursor
;		C  = chr
;	Exit	screen updated
;		HL = new cursor
;		...to VOUT90
	Proc
	CALL	UN_CUR
	LDK	A,1000_0000b
	AND	L
	MOV	L,A		;do CR
	PUSH	HL		;save new cursor
	ADD	HL,HL
	LD	A,PIABD
	ADD	A,24		;A = addr(25th line)
	SUB	H		;A = lines_to_move + 1
	AND	0001_1111b		;mod 32
	MOV	B,A
	LDK	A,VDELL
	CMP	C
	MOV	A,B		;recall #lines to move
	JRZ	:delt		;if deleting a line
	space	3,17
:insrt:
	;Insert a line
	ADD	H		;A = addr(25th line)
	MOV	D,A
	LDK	E,0
	RR D ! RR E		;shift right DE
	DEC	DE		;DE = addr(lst_chr_on_lst_line)
	MOV	A,B		;A = #lines to move
	LDK	HL,-VLL
	ADD	HL,DE		;HL = addr(line above DE)
;DE := DE or F000h; HL := HL or F000h
	JR	:istrt

:icont:
	PUSH	DE
	POP	IX
	CALL	VLDDR		;move 1 line down
:istrt:
	CALL	:vmod
	JRNZ	:icont		;if must move more lines
	INC	HL		;HL => 1st chr of new line
;	JR	:exit
	space	3,3
:exit:
	CALL	CLRLN
	POP	HL		;recover cursor
	JMP	VOUT90	;Main Exit
	space	3,11
:delt:
	POP	DE		;recover new cursor
	PUSH	DE
	LDK	HL,VLL
	ADD	HL,DE		;HL = line_below_cursor
	JR	:dstrt

:dcont:
	PUSH	DE
	POP	IX
	CALL	VLDIR		;move 1 line up
:dstrt:
	CALL	:vmod
	JRNZ	:dcont
	EX	HL,DE		;get addr of line to clear
	JR	:exit
	space	3,13
;HL := HL or F000h; DE := DE or F000h;
;simple mod-4096 arithmetic to keep pointers INSIDE video memory
:vmod:
	PUSH	AF		;save A = #lines to move
	LDK	A,0F0h
	OR	H
	MOV	H,A		;set upper nybl of H
	LDK	A,0F0h
	OR	D
	MOV	D,A		;modulo 4096
	LDK	BC,VLL
	POP	AF
	DEC	A		;decrement line_count
	RET
	space	4,30
CLRLN:
	;Clear to end of line
;	Entry	HL= Cursor
;	Exit	clear to EOL
;	Uses	All.
	proc
	STO	' ',[hl]	;clear cursor...
	DI
	ENADIM
	STO	BRTBIT,[hl]		;set cursor BRIGHT
	DISDIM
	EI
	LD	A,LLIMIT
	DEC	A		;max_#cols => maximum_col_#
	MOV	E,L
	CBIT	7,E
	SUB	E		;A = col(EOL) - col(cursor)
	RZ			;if @EOL, done

	JRNC	:2		;if inside logical_video_line

	LDK	A,VLL
	SUB	E		;...else clr to end of 128-chr line
	RZ			;if cursor @ column #127

:2:
	MOV	C,A
	LDK	B,0		;BC = chrs to move
;	MOV	E,L
;	MOV	D,H
	PUSH	HL
	POP	IX
;	INC	DE		;DE = HL + 1
	INC	IX
	JR	VLDIR
	page
DO_LF:
	;Do Line Feed processing
;	Entry	HL = cursor_addr
;	Exit	Cursor cleared
;		HL updated for current cursor pos
;		window moved if necessary
	proc
	CALL	UN_CUR		;clear cursor
DO_LF2:
	PUSH	HL	;save original cursor
	LDK	BC,VLL	;line length
	ADD	HL,BC
	JRNC	:nowap	;if not wrapping from LWAVM to FWAVM
	LDK	BC,FWAVM
	ADD	HL,BC	;HL = new cursor @ top of VM
:nowap:
	XTHL		;save new cursor, get old
	ADD	HL,HL	;shift HL left
	LD	A,PIABD
	ADD	A,23	;start + 23 = last_video_line
	SUB	H	;A = l_line - curr_line
	AND	0001_1111b	;modulo 32
	JRZ	:vmov	;if cursor is on 24th line of screen
:end:
	POP	HL	;get new cursor
	RET

:vmov:
	LD	A,LLIMIT
	SRL	L	;unshift L register
	SUB	L	;A = LLIMIT - col(cursor)
	JRC	:end	;if cursor is outside logical line

;cursor is on last line of screen, inside of logical line.
;must move screen to follow cursor down through video memory.
	POP	HL
	PUSH	HL
	LDK	A,80h
	AND	L
	MOV	L,A	;HL = beginning of line
	CALL	CLRLN	;erase to EOL
	LD	A,PIABD
	MOV	B,A
	AND	not 31	;A = line zero
	MOV	C,A	;C = housekeeping bits 5..7
	LDK	A,31
	INC	B	;increment line#
	AND	B	;A = line#
	STO	A,VRTOFF	;SET VERTICAL OFFSET FOR COUT
	OR	C	;A = new line# OR housekeeping_bits
	MOV	C,A	;C = new value for OPBD
	CALL	OPBD	;move video screen down 1 line in memory
	POP	HL
	RET
	PAGE
STODIM:
;STORE THE CONTENTS OF THE B REG IN THE ADDR POINTED TO BY THE HL PAIR
;ENTRY
;B	=	VALUE
;HL	=	ADDRESS

;EXIT
;NONE
	PROC
	DI
	ENADIM			;ENABLE DIM
	STO	B,[HL]		;STORE
	DISDIM			;DISABLE DIM
	EI
	RET



VLDDR:
	;Video Block Move
;	Entry	BC, IX, HL set
;	Exit	LDDR on main & 9th bit memory
;	Uses	BC, DE, HL,IX
	PUSH	IX
	POP	DE
	PUSH BC ! PUSH DE ! PUSH HL
	LDDR			;main memory
	POP  HL ! POP  DE ! POP  BC
	DI
	ENADIM
	LDDR			;9th bit memory
	DISDIM
	EI
	RET
	space	4,12
VLDIR:
	;Video Block Move
;	Entry	BC, IX, HL set
;	Exit	LDIR on main & 9th bit memory
;	Uses	BC, DE, HL,IX
	PUSH	IX
	POP	DE
	PUSH BC ! PUSH DE ! PUSH HL
	LDIR			;main memory
	POP  HL ! POP  DE ! POP  BC
	DI
	ENADIM
	LDIR			;9th bit memory
	DISDIM
	EI
	RET
	space	4,10
UN_CUR:
	;Undo/Invert Cursor
;	Entry	HL = cursor_addr
;	Exit	cursor inverted
;	Uses	A, CY.
	LD	A,[hl]		;get the chr
	RAL			;cursor_bit => CY
	CMC			;invert it
	RAR
	STO	A,[hl]		;...
	RET

	PAGE
;KEYBOARD SCANNING & DECODE

GKEY:
	;KEYBOARD INTERRUPT PROCESSOR
;ENTRY
;NONE

;EXIT
;KEYBOARD PROCESSING DONE, RESULT IN LDKEY.
;SYSTEM CLOCK UPDATED BY UPTIM.

	PROC

	DI
	STO	SP,IESTK	;SAVE INTERRUPTED PROCESS STK
	LDK	SP,ISTK		;SET TO RAM INT STK
	ALPUSH

	CALL	UPTIM		;UPDATE SYSTEM CLOCK

	LD	A,KEYLCK
	OR	A
	CNZ	KBDRVR
GKEYX:
	JMP	EXITI		;EXIT INTERRUPT
	PAGE
;	This file contains the 2-key roll over keyboard driver for
;	the OSBORNE 1 comuter.

;	Author:
;	Microcode Corporation.
;	Fremont, CA.
;	Y. N. Sahae
;	September 1981

;	Revisions:

;	2-Key roll over keyboard driver.

;	DESCRIPTION:
;	The keyboard driver gets control via the 60hz interrupt, i.e. once
;	every 16 ms.  It scans the keyboard  to detect any struck keys.  If a
;	key is found, it is entered into the keylist if there is space
;	in the keylist and the key is not already in the list.   At the end of
;	the scan, the keys in the list are proecessed.  If the key is still
;	on,  it is placed in lkey (or special action taken) after translating
;	the keynumber.  A count is also stored in the list and the key will
;	be serviced again at the end of this count if it is still on.  Thus
;	the key will repeat if it is held down.  If a key which is in the
;	list is not on it is removed from the list.
;
;	The keyboard driver consists of the following routines:
;
;	KBDRVR - Examines the keylist, calls CHKEY to determine if key
;	is still on.  Removes the key from the list if it is not on.  If
;	key is on, it decrements the count associated with the key.  when
;	the count goes to zero, it calls KBSERV to service the key.  Calls
;	KBSCAN to enter any new keys into the list.
;
;	KBSCAN - This routine scans the keyboard, detects a struck
;	key and enters it into the keylist.  The key is entered
;	into the keylist if the key is not already present in the keylist
;	and there is an empty slot in the keylist.
;
;	KBSERV - It calls the routine CHKEY to check if shift/ctl or alphlock
;	keys are on.  It then translates the keynumber into the ASCII 
;	code and places it in the LKEY for the CBIOS to read.  For some
;	special cases, it calls	ROM resident routines to process the key.
;
;	CHKEY - It checks if a given key is on.
;
;
;	Data structure:
;	The main structure used is the keylist.  The format of each entry is:
;
;	Byte 0:
;		bit 7 :  Set indicates entry is in use.
;		bit 6 :  Set indicates key has been serviced once.
;		bits 5..3 : contain the row number of struck key.
;		bits 2..0 : contain the column number of struck key.
;	Byte 1:
;		bits 7..0 : contain the repeat count for the key.
;
	PAGE
KBDRVR:
;	Routine name: KBDRVR - Detects and processes keystrokes.
;	Input: none
;	Output: LKEY contains keystroke.

	proc
	call	kbscan		;scan keyboard and enter keys into keylist

;	Examine keylist.  If key found in keylist, call CHKEY to see
;	if key is still on.  remove from list when not on.
	
	LDK	hl,keylst	;point to first entry of keylist
	LDK	b,kl_len	
:10:
	ld	a,lkey
	or	a
	RNZ			;exit when a key is waiting in lkey

	ld	a,[hl]		;get byte 0 of entry
	bit	kl_used,a	
	jrz	:40		;if entry is in use then
	call	chkey		  ;check if still on
	jrnz	:20		  ;if key is now off then
	sto	0,[hl]		    ;remove key from list	
	jr	:40
:20:				  ;else
;	key is on.  decrement its repeat count.  If count goes to zero
;	then it is time to service the key.  
	
	push	hl		    ;save ptr to first byte of entry	
	inc	hl		    ;point to repeat count
	dec	[hl]
	jrnz	:30		    ;exit when not time to service the key.

;	it is time to service the key.  Set the next repeat count 
	
	ex	[sp],hl		    ;point back to the first byte of entry
	ld	a,[hl]		    
	bit	ky_srvd,a	    ;check if it is serviced before
	sbit	ky_srvd,[hl]	    ;set the serviced once flag
	ex	[sp],hl		    ;point back to the repeat count	
	sto	irptct,[hl]	    ;and store rpt count as per serviced flag
	jrz	:22		
	sto	srptct,[hl]
:22:
	and	krow_m+kcol_m
	call	kbserv		    ;call to service the key
:30:
	pop	hl		    ;get ptr to first byte of entry again
				  ;endif
:40:		 		;endif
	echo	kle_len
	 inc	hl		;point to next entry
	ENDM
	djnz	:10		;until	complete list scanned

	RET			;return to exiti code in rom
	PAGE
;**
;	sbrt:	KBSCAN - Scan keyboard and enter detected keys in the
;	keylist.
;	input:
;		none
;	output:
;		keylst = contains any keys detected.

KBSCAN:	proc
	LDK	l,0ffh			;see if any key pressed
	call	rdrow
	rz				;return when none

	LDK	l,row0_m		;get row 0
	call	rdrow

;	LDK	L,1
;	CALL	RDROW
;	PUSH	psw
;	LDK	l,80h
;	CALL	rdrow
;	ANI	08h
;	MOV	B,A
;	POP	PSW
;	OR	B	

	and	11100011b		;remove ctl/shift and alpha lock
	LDK	b,tot_row

;	in this loop, reg b contains totrow- current row being scanned 
:10:
	jrz	:50			;if any key is pressed then

	push	bc			  ;save loop count
	mov	e,a			  ;e = columns
	LDK	a,tot_row
	sub	b			
	ral
	ral
	ral				
	mov	d,a			  ;d = row number * 8
	LDK	c,0			  ;initialize column counter
	
;	scan this row from right to left to get the column number 
:15:					  ;repeat
	srl	e			    ;shift column bit into carry
	jrnc	:30		            ;if a key is found then
					    
;	enter the key whose column number is in c and row*8 is in d 
;	into the keylst provided the key is not already in list and
;	there is an empty slot in the list.

	mov	a,d
	add	a,c			    
	push	bc
	mov	c,a			      ;c = key number
	push	de			      ;save de	
	push	hl			      ;save hl
	LDK	b,kl_len		      ;length of keylist
	LDK	hl,keylst
	LDK	de,0
:18:
	ld	a,[hl]
	bit	kl_used,a		      ;
	jrz	:22			      ;if entry is used then
	and	krow_m+kcol_m
	cmp	c			        ;check with current key
	jrz	:27			        ;exit if this key is in list
	jr	:25
:22:					      ;else (an empty entry is found)
	mov	e,l
	mov	d,h			        ;save adrs of empty entry in de
:25:					      ;endif
	echo	kle_len
	  inc	hl
	ENDM				      ;next entry
	djnz	:18			      ;till list scanned	

;	check if an empty entry was found.
	mov	a,d
	or	a
	jz	:27			      ;if empty entry was found then
	ex	de,hl			        ;hl = empty entry
	sto	c,[hl]			        ;store the key in the list
	sbit	kl_used,[hl]		        ;set used flag
	inc	hl
	sto	DB_ct,[hl]			;store debounce delay
					      ;endif
:27:					      ;restore all regsters
	pop	hl			  
	pop	de
	pop	bc
:30:					    ;endif
	inc	c			    ;increment column number
	xor	a
	cmp	e
	jrnz	:15			  ;until all columns scanned 	

	pop	bc			  ;rstore bc
:50:				     	;endif
	sla	l			;move to next row
	call	rdrow
	djnz	:10
	ret

	PAGE
;**
;	sbrt:	CHKEY - checks if key number is on.
;	input:
;		Reg A = Keynumber
;	output:
;		Z ind clr = Key is off.
;		Z ind set = Key is on.

CHKEY:	proc
	push	hl		;save callers hl
	push	af		;save keynumber
	rar
	rar
	rar			;right justify row number
	call	gtmask
	pop	af		;get key number
	push	de		;save row mask
	call	gtmask		;get col mask (col num is in bits 0..2)
	pop	hl		;move row mask to l
	call	rdrow		;get row of keys adrsed by l
	and	e		;z ind = value of key
	pop	hl
	ret



;**
;	sbrt:	GTMASK - generates mask with one bit set.
;	input:
;		a = bit number (0..7)
;	output:
;		e = mask

GTMASK:	proc
	LDK	e,1
	and	7
:10:
	rz
	sla	e
	dec	a
	jr	:10


;**
;	sbrt:	RDROW - Reads a row of keys
;	input:
;		reg L = lower 8 bits of adrs to read the row
;	output:
;		reg A = row value
;

RDROW:	proc

	LDK	h,high(h.key)		;hl = prt adrs for given row 
	MOV	A,L
	MOV	R,A
	ld	a,[hl]
	xor	0ffh			;invert values
	ret
	PAGE
;**
;	sbrt:	KBSERV - services the key
;	input:
;	    reg A = keynumber
;		[SP]-4 =  pointer to keylst entry (used for slide fnc only)
;	preserves reg B

lft_arw	equ	8dh
rt_arw	equ	8bh
up_arw	equ	8ah
dn_arw	equ	8ch
hm_scrn	equ	'['

KBSERV:
	proc

;	setup hl to point to keycode table entry for this key
	mov	e,a
	LDK	d,0		;used here and later
	LDK	hl,kycdtb
	add	hl,de
	ld	a,[hl]
	cmp	' '+1
	jrc	:12		;ignore shift/ctl etc for chars less than 21h

	push	af
	LDK	l,1		;row 0 adrs
	call	rdrow		;get row containing ctl,shift and alpha key
;
	PUSH	AF
	LDK	L,80H
	CALL	RDROW
	ANI	8
	MOV	E,A
	POP	AF
	OR	E
;
	mov	e,a
	pop	af		;restore keycode
	bit	ctl_ky,e
	jrnz	:50		;go process ctl key
	bit	shft_ky,e	
	jrnz	:30		;go process shift key	
	bit	alph_ky,e
	jrnz	:25		;go process alpha key
;
;	store key code into lkey
:12:
	sto	a,lkey
	ret
:25:				;process alpha key
	cmp	'a'
	jrc	:12		;exit when less than 'a'.  Alpha has no effect
:27:
	cmp	80h
	jrnc	:12		;or when >= 80h
:28:
	xor	20h		;fold char to upper case
	jr	:12

:30:				;process shift key
	cmp	'a'
	jrnc	:27		;goto alpha when char > 'a'
	cmp	'['
	jrc	:35		;goto process shift numerics etc
	jrnz	:28		;invert shift bit for '\'
	LDK	a,']'
	jr	:12		;convert [ to ]
:35:
;	chars ' to > (ascii codes 27h to 3eh) are converted using
;	the shft_tb

	mov	e,a
				;d=0 from before
	LDK	hl,shft_tb - ''''
	add	hl,de
:37:	
	ld	a,[hl]
	jr	:12	


:50:				;process control key
;	if char is between a..z then turn off the 3 high order
;	bits.
;	if char is between ','..'?' it is translated as per table ctl_tb'
;	if char is the arrow keys or the ']'/'[' key the slide functions
;	are called.
	
	cmp	lft_arw
	jrz	slidel
	cmp	rt_arw
	jrz	slider
	cmp	up_arw
	jrz	slideu
	cmp	dn_arw
	jrz	slided
	cmp	hm_scrn
	jrz	dohome		

	BIT	shft_ky,e	;test for cntl shift
	jrz	:52		;if not
	cmp	'/'		;is it ?
	jrnz	:52		;if not '?'
	ldk	a,07fh		;deleat key
	jr	:12

:52:	cmp	'@'
	jrc	:54		;goto translate chars from table
	cmp	'z'+1
	jrnc	:12
	and	1fh
	jr	:12

:54:
	cmp	','
	jrc	:12		;no translation if char below ','
	LDK	hl,ctl_tb-','
	mov	e,a
				;d=0 from above
	add	hl,de
	jr	:37

;	slide functions.
slidel:
	LDK	c,2
	jr	:70
slider:
	LDK	c,-2
:70:
	ld	a,piaad		;get horizontal coord.
	add	a,c
	mov	c,a
:72:
	call	opad		;set pia a data
:74:
;	set repeat count for these keys (override count set by the kbdrvr)
	pop	de		;get return adrs
	pop	hl		;pointer to repeat entry
	sto	sld_rct,[hl]	;repeat count for slide keys
	push	hl
	push	de		;restore stack
	ret

slideu:
	LDK	c,1
	jr	:76
slided:
	LDK	c,-1
:76:				;merge new vertoffset to lower 5 bits of
				;PIAB
	LDK	hl,piabd
	ld	a,[hl]
	add	a,c
	and	1fh		;modify current with +1/or-1
	mov	c,a
	ld	a,[hl]
	and	0e0h
:78:
	or	c
	mov	c,a
	call	opbd
	jr	:74

dohome:
	LDK	c,vflo			;just the fuzz factor
	call	opad			;set horiz to 0
	ld	A,piabd
	AND	0E0H			;HOUSE KEEPING BITS
	MOV	C,A
	LD	A,VRTOFF		;GET LAST VERTICAL OFFSET
	jr	:78			;and the vert to 0 also	

	

;	key code translation tables
kycdtb:
	DB	esc, tab, erc, erc

	DB	erc, cr, '''', '['

	DB	'1', '2', '3', '4'

	DB	'5', '6', '7', '8'

	DB	'q', 'w', 'e', 'r'

	DB	't', 'y', 'u', 'i'

	DB	'a', 's', 'd', 'f'

	DB	'g', 'h', 'j', 'k'

	DB	'z', 'x', 'c', 'v'

	DB	'b', 'n', 'm', ','

	DB	8ah, 8dh, '0', ' '

	DB	'.', 'p', 'o', '9'

	DB	8bh, 8ch, '-', '/'

	DB	';', '\', 'l', '='


shft_tb:
	DB	'"', 00h, 00h, 00h, 00h

	DB	'<', '_', '>', '?', ')'

	DB	'!', '@', '#', '$', '%'

	DB	'^', '&', '*', '(', 00h

	DB	':', 00h, '+', 00h

ctl_tb:
	DB	'{', '_'-40h, '}', '~'

	DB	80h, 81h, 82h, 83h, 84h

	DB	85h, 86h, 87h, 88h, 89h

	DB	00h, 00h, 00H, 60H
 
		;	END	OCCROM3?.???
