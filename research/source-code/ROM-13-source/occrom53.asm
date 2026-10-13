	TITLE	'SIO - Serial I/O Processors.'
SIRST:
	;Master reset SIO
;	Entry	C= SI.S16 or SI.S64 for 1200/300 baud
	LDK	A,SI.MRST
	STO	A,H.SCTRL	;master reset
	MOV	A,C
	STO	A,ACIAD		;last-command cell
	STO	A,H.SCTRL	;select SIO
	RET
	space	4,10
READER:
	;Input one byte from reader port
;	Entry	None
;	Exit	A=C= character read
	LD	A,H.SSTS
	AND	SI.RRDY
	JRZ	READER		;if not ready

	LD	A,H.SREC	;get data
	MOV	C,A		;A=C
	RET
	space	4,10
SLST:
	;Get list device status
;	Exit	A= 0, if NOT ready
	LD	A,H.SSTS
	AND	SI.TRDY		;ck for Xmit buf empty
	RET			;set status
	space	4,10
LIST:
	;Output one byte to list port
PUNCH:
	;Output one byte to punch port
;	Entry	C= character to output
;	Exit	C=C.

:wait:
	LD	A,H.SSTS
	AND	SI.TRDY		;wait for CTS go-ahead
	JRZ	:wait		;if CTS high, wait again

	MOV	A,C
	STO	A,H.SXMT	;send chr
	RET


;	END	OCCROM5?.???
