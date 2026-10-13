	TITLE	'FORMAT'
FORMT:
	;Format one track
;	in IBM 3740 format consisting of 40 tracks, with each
;	track containing 10 sectors.
;	Drive already selected and ready
;	Entry	BC = FWA of buffer
;		BUF+0= DW length
;		BUF+2= beginning of data
;		SAVTRK = next track to format
;		SAVSEC = 1
;	Exit	track formatted

	proc
	PUSH	BC		;save address
	LD	A,SAVTRK
	LDK	HL,D.TRKR	;PRESENT TRACK
	OR	[HL]
	JZ	:2		;if already on track
	LDK	A,D.STPI
	CALL	PSEKC		;perform step IN
:2:
	LDK	A,D.WRTT	;request write track
	DI
	CALL	FDSK		;request write
	POP	HL		;FWA of buffer
	EI
	RNZ			;if error
	DI

;	Load BC with length and set
;	HL = FWA of data to xmit to disk
	LD	C,[hl] ! INC HL
	LD	B,[hl] ! INC HL	;BC = length of xfer

;	Now write out data
:4:
	CALL	XDD		;xfer to disk
	JRNZ	:11		;if error


;	Pad rest of track with FFh
:10:
	LD	A,D.STSR
	OR	A
	JRZ	:11		;if all done
	AND	DS.DRQ
	JRZ	:10
	LDK	A,0FFh
	STO	A,D.DATR	;pad
	JR	:10		;continue

;	Exit A=0, if no error
:11:
	EI
	RET


;	END	OCCROM8?.???
