	page
;*****
;
;	Revisions:
;	YNS	20AUG81		Initial release
;	YNS	29AUG81		Expanded trans. table to include ctl/numerics
;	YNS	01SEP81		Added parallel port support 
;	YNS	05SEP81		Invert data to/from parallel port
;	YNS	06SEP81		Return character in C as well as A from
;				all input routines. 
;	YNS	08SEP81		Fixed "some" ieee bugs
;	YNS	20SEP81		Recode ieee drivers to send untalk and
;				unlisten commands after each char xfr.
;	YNS	29SEP81		Add auto horiz. scroll
;	RWC	14OCT81		Reassignment in dispatch table
;				Redefinition of iobyte assignments
;				Printer protocols added to serial list device
;				Function key decoding added
;	RWC	20OCT81		Horizontal scroll toggle added
;	RWC	24OCT81		Horizontal scroll modified 
;
;*****


;
; the following routines will use the IOBYTE to transfer 
; control to the appropriate device driver
; 
;--------------
; return console status
;
CNSTA:	proc
	ldk	hl,ptr_cstat	; status table
	jr	godispch	; call appropriate rtn
;------------
; read input character from device
;
CNIN:	proc
	ldk	hl,ptr_cinp	; table of input rtns
	jr	godispch
;-------------
; put output character to device
; c contains output character
;
CNOUT:	proc
	ldk	hl,ptr_cout	; table of output rtns
godispch:
	mvi	b,1		;number of shifts required to align
				;CONSOLE field
	jmp	dispch
;---------------
; list device character output
;
LST:	proc
   	mvi	b,4
	ldk	hl,ptr_list	;table of list routines
	jmp	dispch
;---------------
; output to punch
;
PNCH:	proc
	mvi	b,6
	ldk	hl,ptr_pnch	; punch routines
	jmp	dispch
;----------------
; reader input
;
RDR:	proc
    	mvi	b,8
	ldk	hl,ptr_rdr	; reader routines
	jmp	dispch
	space	4,10
;	L i s t   S t a t u s.
;
;	Return the ready status for the list device.
;
;	EXIT	A = 0 (zero), list device is not ready to
;		accept another character.
;		A = FFh (255), list device is ready to accept
;		a character.
;	The list status is returned depending upon the iobyte fields
;	LIST field (bits 6,7)
;		=0:	status of crt. (always ready)
;		=1:	status of serial printer
;		=2:	status of parallel printer
;		=3:	status of ieee port (always ready)
;
LSTST:	proc
	mvi	b,4		;number of left shifts thru carry
				;to align LIST field of IOBYTE
	ldk	hl,ptr_lst	;list status routines
	jmp	dispch	



	page
dispch:	proc
;	on entry here reg B contains the left shift count
;	required to align the iobyte field to bit 1 position.
;	and reg HL contains address of select table

	lda	iobyte
dspch1:
	ral
	djnz	dspch1
	ani	6		;get select field*2
	mov	e,a
	ldk	d,0		; de = iobyte field * 2
	dad 	de
	mov	e,m
	inx	hl
	mov	h,m		; get the routine address
	mov	l,e		; into hl and xchange with pc
	pchl
;
; addresses of routines
;
ptr_cstat:
	dw	const		; keyboard status
	dw	sistat		; serial port input status
	dw	pistat		; parallel input status
	dw	ieinstat	; status of input device on IEEE port
ptr_rdr:
ptr_cinp:
	dw	keyinp		; get input from keyboard
	dw	spinp		; serial port input
	dw	parinp		; parallel input
	dw	ieinp		; ieee port input
ptr_pnch:
ptr_cout:
	dw	crtout		; output character to crt
	dw	spout 		; serial port output
	dw	parout		; parallel output
	dw	ieout		; ieee port output
ptr_lst:
	dw	crstat
	dw	sostat		; serial output status
	dw	postat		; parallel output status
	dw	ieostat		; ieee output status
ptr_list:
	dw	crtout
	dw	prtout
	dw	parout
	dw	ieout
;
	page
;	C O N S O L   S T A T U S
;
;	This routine samples the Console status and returns the
;	following values in the A register.
;
;	EXIT	A = 0 (zero), means no character
;		currently ready to read.
;
;		A = FFh (255), means character
;		currently ready to read.

nokey	equ	00h		;indicates key not present
		
CONST:	proc
;	check if any translated keys are pending
	ld	a,count
	ora	a
	jrnz	const5
;	if no xlated keys pending, check keyhit flag

	LD	A,LKEY		;Get Key hit flag
	xri	nokey
	RZ			;If data not available
const5:
	ORI	0FFh
	RET
	page
;**
; Routine name: KEYINP - gets keystroke from rom kbd driver.  Translates
;			 the codes 80h to 8fh as per table. 
;
; Outputs: A = translated code in ASCII
; All registers are destroyed
;

basvl0	equ	80h			;lowest value of translatable keys
xltkey	ds	2
;
KEYINP:	proc
;	if there are no xlated keys waiting then
;	call the keyboard driver in rom

	call	ahscrl
	ldk	hl,count
	ld	a,[hl]			;get number of xlated keys
	ora	a
	jrz	kin10			;if keys pending then
	ld	ix,xltkey		;get base address in IX reg
	db	0DDh,7Eh		;simulate LD  A,(IX+COUNT)
count:	db	0			;to get next key from table
	inc	[hl]			;increment count
	ret

kin10:
	ldk	e,low(conin)
	call	romcd1

;	When console has returned this code will check
;	for function key and preform some translation

	cpi	80h		;function keys have value
	rc			;80h-8dh
	cpi	8Eh		;do a shift to make pointer 
	rnc			;into table and return if not function key
	sla	a		;
	mov	e,a		;
	ldk	d,0		;
	ldk	ix,xltbl	;
	add	ix,de		;
 	ld	l,[ix+0]
	ld	h,[ix+1]
	ld	e,[ix+2]
	ld	d,[ix+3]
	sto	de,xltkey
	sbc	hl,de
	mov	a,l
	sto	a,count		;
	jr	keyinp		;
;
;
        page
;**
; routine:	CRSTAT
;		returns status of crt.
;		crt is always ready
;		IEOSTAT returns status of ieee
;		ieee always appears to be ready

ieostat:
CRSTAT:	proc
	ori	0FFh
	ret


;**
; routine name: CRTOUT
;
; inputs: C: output character

EF_ESC:	=	8		;escape flag bit definitions
EF_GR:	=	1
;
CRTOUT:	proc
	lda	esch
	and	ef_esc+ef_gr
;	push	af
	jrnz	crt10
	mov	a,c
	cpi	14h
	jrnz	crt10
	ld	a,ahsenb
	cma
	sto	a,ahsenb
;	pop	af
	ret
crt10:
;	call	outch
;	pop	af
;	rnz
;	mvi	a,cr
;	cmp	c
;	cz	ahscrl
;	ret
	

;	sbrt: outch - calls rom cout routine
outch:
	ldk	e,low(conout)	  ;output to crt
	jmp	romcd1

;	sbrt: ahscrl - does auto horizontal scroll if required.
ahscrl:	proc
	ld	a,ahsenb
	or	a
	rz

	ld	hl,curs		;get cursor
	add	hl,hl

;	check for cursor in home window
	ldk	a,100
	cmp	l
	jrc	rhc		;jump if cursor not in home window
	ld	a,piaad		;check for screen at home
	sub	vflo
	rz			;screen at home
	xra	a		;home screen
	jr	scrl

rhc:
;	check right-hand margin
	ld	a,piaad		;a=horizontal screen position
	sub	vflo
	add	a,100		;window size*2 (49)
	cmp	l
	jc	:30		;move screen when cursor about to go off
				;the right hand margin
;	check left hand margin
	sub	90
	cmp	l		;check left margin
	rc			;cursor in window return
	mov	a,l
	sub	10
	rz			;return if cusor at column 2
	jr	scrl

:30:
	mov	a,l
	sub	100
scrl:
	rar
	add	a,' '
	lk	hl,escsq+3
	sto	a,[hl]
	ld	a,piabd
	and	1fh
	add	a,' '
	dec	hl
	sto	a,[hl]			;escsq+2 = vert. coords
	dec	hl
	dec	hl			;point to start of esc seq
	lk	b,4
:50:
	push	bc
	push	hl
	ld	c,[hl]
	call	outch
	pop	hl
	pop	bc
	inc	hl
	djnz	:50	
	ret	

escsq	db	esc			;set screen coord escape sequence
	db	'S'
	db	0			;** y coord
	db	0			;** x coord

	page
;**
; routine:	SOSTAT
;		gets status of output device attached to serial port
SOSTAT:	proc
	call	acistat		;get 6850 status
	ani	si.trdy
	rz			;return with not ready status
	ori	true
	ret

;**
; routine:	SISTAT
;		gets status of input device attached to serial port
SISTAT: proc
	call	acistat
	ani	si.rrdy
	rz			;return with not ready status
	ori	true
	ret

;**
; routine:	SPINP
;		Inputs a character from the serial port 
;		Uses the reader (sp) driver in ROM
;
SPINP:	proc
	ldk	e,low(reader)
	jmp	romcd1

;**
; routine:	SPOUT
;		Outputs character in reg c to the serial port (list device)
;		calls the list (sp) driver in ROM
;
SPOUT:	proc
	ldk	e,low(list)
	call	romcd1
	ret

;**
; routine does serial i/o and does printer protocols
;

xon:	=	11h
xoff:	=	13h
etx:	=	3
ack:	=	6
;
prtout:
	call	spout
	ld	a,prnter
	ora	a
	rz
	ani	2
	jrnz	xonxof
	mvi	a,0dh
	cmp	c
	rnz
	ldk	c,etx
	call	spout
prt10:
	call	spinp
	cpi	ack
	jrnz	prt10
	ret
xonxof:
	call	sistat
	ora	a
	rz
	call	spinp
	cpi	xoff
	rnz
prt20:
	call	spinp
	cpi	xon
	jrnz	prt20
	ret



;**
; routine:	ACICTL
;		outputs character in c to the ACIA CTL port.
;
ACICTL:	proc
	call	sw2rom
	mov	a,c
	sta	h.sctrl
	jmp	sw2ram		

;**
; routine:	acistat
;		returns usart status in A
;	The ringin signal is read from the pia at address 2c00
;	and merged in at the overrun error bit of the acia status
riport	equ	h.vio+1
ribit	equ	040h
ormask	equ	020h	

acistat: proc
	call	sw2rom
	lda	riport			;read in ringin signal
	rrc				;shift ring in to overrun err
					;position
	ani	ormask			;get ring in 
	mov	c,a
	lda	h.ssts			
	ani	0ffh-ormask		;remove overrun error bit
	ora	c			;merge ring in bit
	jmp	sw2ram

	page

;***
;	IEEE drivers:
;	
;	The routines IEINSTAT, IEINP and IEOUT are used to
;	transfer characters to and from an IEEE device attached to the
;	OSBORNE IEEE port.  The address of the device is specified in
;	the cell IE_ADRS.  No facility is provided at present to allow a
;	transient programme to specify the device address.  Thus the device
;	attached must be addressable as 0 (zero).
;	The function IEINSTAT returns the status of the input device.  
;	Unfortunately there is no standard way by which an IEEE device
;	indicates that it has a character.  In order to determine this, one
;	has to read the character device.  As a CP/M transient can call
;	IEINSTAT many times before calling IEINP to read a char, and IEINSTAT
;	has to read the char to determine the status, the character read has to
;	be buffered till call to IEINP is made.  IEINSTAT reads the device
;	only when the buffer is empty.  As zeros are used to indicate
;	that the bfr is empty, a null character can not be read from the
;	IEEE device. 

;	IEEE control codes
ie_talk	equ	40h			;make talker
ie_utlk equ	5fh			;make untalk
ie_lstn equ	20h			;make listener
ie_ulstn equ	3fh			;make unlisten


ie_adrs	db	0			;device address (can be moved to
					;BMRAM)
ie_char db	0			;ie inp char buffer
 
;**
; routine:	IEINSTAT
;		gets status of the input device attached to ieee port
;
;		if a char is present in ie_char then
;			return with true status
;		else
;			make device talker
;			read the device
;			if char read then
;			  store in bfr
;			endif
;			make untalk
;			return with status of buffer
;		endif

IEINSTAT: proc
	lda	ie_char
	ora	a
	jz	iei10			;if char present then
	ori	0ffh			  ;return with true status
	ret
iei10:					;endif
					  ;make talker
	lda	ie_adrs
	adi	ie_talk			  ;get primary address
	mov	c,a
	ldk	e,low(ieb5c)
	call	romcd1			  ;output interface message 
	ora	a
	jrnz	iei10			  ;try again if error
;	
;	***secondary address output may be added here***

iei20:					;read a char.	
	ldk	e,low(ieb7c)
	call	romcd1
	bit	7,l
	jrz	iei30			;if error then
	xra	a			  ;inicate no char recvd
iei30:
	sta	ie_char			;stor the char
;
;		
iei40:			;make untalk
	mvi	c,ie_utlk	 
	ldk	e,low(ieb5c)
	call	romcd1
	ora	a
	jrnz	iei40

;	return with status of the char
	lda	ie_char
	ora	a
	rz			
	ori	0ffh
	ret

;**	
; routine:	IEINP
;		Reads a character from IEEE port 

IEINP:	proc
	call	ieinstat
	jrz	ieinp			;wait till char avail
	ldk	hl,ie_char
	ld	a,[hl]
	sto	0,[hl]			;clear the buffer
	ret


;**
; routine:	IEOUT
;		Outputs the character in reg C to IEEE port
;		Uses ROM resident primitives.
;
IEOUT:	proc
	push	bc			;save the char
					  ;make listener
ieo05:
	lda	ie_adrs
	adi	ie_lstn			  ;get primary address
	mov	c,a
	ldk	e,low(ieb5c)
	call	romcd1			  ;output interface message 
	ora	a
	jrnz	ieo05			  ;try again if error
;
;	***secondary address output may be added here***
;
ieo20:					;	
	mvi	b,0			;do not send eoi
	pop	b
ieo22:
	push	b			;save char again in case of retry
	ldk	e,low(ieb6c)
	call	romcd1
	pop	b
	ora	a
	jrnz	ieo22			;try again if error
;
;					;make unlisten
ieo40:
	mvi	c,ie_ulstn
	ldk	e,low(ieb5c)
	call	romcd1
	ora	a
	jrnz	ieo40

	ret
	page
;***
;	The Parallel port is actually the IEEE port driven with the centronix
;	protocol.  The bit assignements of the PIA and PIB are as follows:
;	PIA0-7 = data bus
;	PIB0 = 0, data bus is output. 1, data bus is input
;	PIB1 = set to 1.
;	PIB2 = set to 0.
;	PIB3 = 0 output, 1 Input
;	PIB4 = not used
;	PIB5 = output strobe. Active = 1.
;	PIB6 = 0, printer busy. 1, printer is ready.
;	PIB7 = not used.
;
; 	CA2 = going low indicates to device that we are busy.
;	CA1 = low to high transition gates input data to port a.
;
;	The port is bidirectional but only one direction
;	can be active at any time. The direction of port is determined
;	by which routines are called.  If postat or parout are
;	called, it is made an output port and an input port if
;	pistat or parinp are called.

;	port registers
pa.dta	equ	h.ieee+0
pa.dir	equ	pa.dta
pa.ctl	equ	h.ieee+1
pb.dta	equ	h.ieee+2
pb.dir	equ	pb.dta
pb.ctl	equ	h.ieee+3

;	port ctl register constants.
pa.cdr	equ	00101010b	;to address port a direction 
pa.cdt	equ	00101110b	;to address port a data and set
				;port a in input program handshake mode.
pb.cdr	equ	00000000b	;to address port b direction
pb.cdt	equ	00000100b	;to address port b data

;	direction register constants
pa.dro	equ	0ffh		;port a output mode
pa.dri	equ	00h		;port a input mode
pb.dr	equ	0bfh		;port b direction		
pb.dto	equ	00000010b	;port b data for output
pb.dti	equ	00001011b	;port b data for input

pp.ordy	equ	01000000b	;output rdy bit in pib
pp.irdy equ	10000000b	;input rdy bit in pia ctl reg
strb	equ	00100000b	;strobe bit in port b

;	port modes
pp.undef equ	0
pp.out	equ	1
pp.in	equ 	2

pp.mode	db	pp.undef
		
;***
; sbrt:		CV2OP.		initializes the port to a parallel output
;				port.
cv2op:	proc
	lda	pp.mode
	cpi	pp.out
	rz			;return when in output mode
;	set port a to output on all lines
	lk	a,pa.cdr
	sta	pa.ctl		;select direction reg
	lk	a,pa.dro
	sta	pa.dir		;output constant to dir. reg to put
;				 a port in output mode
	lk	a,pa.cdt
	sta	pa.ctl		;select port a data reg.

	lk	a,pb.cdr
	sta	pb.ctì		;selecô porô b direction
	lk	a,pb.dr
	sta	pb.dir		;all lines are output except the output
				;busy signal on bit  6
	lk	a,pb.cdt
	sta	pb.ctl		;select data register 	
	lk	a,pb.dto
	sta	pb.dta		;initialize port b data

	lk	a,pp.out
	sta	pp.mode
	ret
;***
; sbrt:		CV2IP.		initializes the port to a parallel input
;				port.
cv2ip:	proc
	lda	pp.mode
	cpi	pp.in
	rz			;return when in input mode
;	set port a to input on all lines
	lk	a,pa.cdr
	sta	pa.ctl		;select direction reg
	lk	a,pa.dri
	sta	pa.dir		;output constant to dir. reg to put
;				 a port in input mode
	lk	a,pa.cdt
	sta	pa.ctl		;select port a data reg.

	lk	a,pb.cdr
	sta	pb.ctì		;selecô porô b direction
	lk	a,pb.dr
	sta	pb.dir		;all lines are output except the output
				;busy signal on bit  6
	lk	a,pb.cdt
	sta	pb.ctl		;select data register 	
	lk	a,pb.dti
	sta	pb.dta		;initialize port b data

	lk	a,pp.in
	sta	pp.mode
	ret


;**
; routine:	POSTAT
;		gets status of the parallel (centronix) printer
;		attached to the ieee port
;
POSTAT:	proc
	call	sw2rom
	call	cv2op		;convert to output
	lda	pb.dta		;get port b data
	ani	pp.ordy
	jrz	pos10
	ori	true		
pos10:
	jmp	sw2ram


;**
; routine:	PISTAT
;		gets status of the input device attached to the
;		parallel port
;
piactl	db	0

PISTAT:	proc
	call	sw2rom
	call	cv2ip
	lda	piactl
	ani	pp.irdy
	jrnz	pis20		;if saved status indicates there is a char
				;in the PIA 
	lda	pa.ctl
	sta	piactl		;this is saved as reading the
				;pia clears the status
	ani	pp.irdy
	jrz	pis30
pis20:
	ori	true	
pis30:
	jmp	sw2ram


;**
; routine:	PARINP
;		inputs a character from parallel port.
PARINP:	proc
	call	pistat
	jrz	parinp		;wait till char in pia
	call	sw2rom
	xra	a
	sta	piactl		;clear saved status
	lda	pa.dta
	cma			;invert data	
	mov	c,a		;also in c
	jmp	sw2ram




;**
; routine:	PAROUT
;		outputs the character in c to the IEEE port treating the
;		port as a parallel port.
PAROUT:	proc
	call	postat
	jrz	parout
	call	sw2rom
	mov	a,c
	cma				;invert data
	sta	pa.dta
	lk	a,pb.dto+strb
	sta	pb.dta			;set strobe
	lk	a,pb.dto
	sta	pb.dta			;clear strobe
	jmp	sw2ram


		
	page
;***
; sbrt:		SW2ROM
;		switches to rom
;		saves all registers
SW2ROM:	proc
	di
	push	af
	enarom
	pop	af
	ei
	ret

;***
; sbrt:		SW2RAM
;		switches to ram
;		preserves all registers
SW2RAM:	proc
	di
	push	af
	disrom
	pop	af
	ei
	ret

xxx:	=	*
	if	xxx>MRAMEX
.9	error	CODE TOO LARGE..
	endif

	
	ORG	BIOS+770H		;This is location ED70h in 60K system
	DW	CCP			;This location needed by ROM for
					;relocating boot loader
					;last sector read bombs out part
					;of BMRAM in 60K system
