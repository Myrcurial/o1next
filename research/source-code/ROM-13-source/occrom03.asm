	TITLE	'Osborne-One Monitor for Model 1 system.'

;	+-------------------------------+
;	|				|
;	|	Osborne-One Monitor	|
;	|				|
;	+-------------------------------+

;VER	=	REV 3
;DATE	=	349

;Developed for use with the new cbios

CCP	=	0
	ORG	0		;FWA of memory

ALPUSH:	MACRO
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	PUSH	IX
	PUSH	IY
	ENDM

ALLPOP:	MACRO
	POP	IY
	POP	IX
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	ENDM
	PAGE
	LINK	OCCROM13.ASM	;ROM STANDARDS

	LINK	OCCROM23.ASM	;CPM BOOT

	LINK	OCCROM33.ASM	;CONSOL ROUTINES

	LINK	OCCROM43.ASM	;PIA ROUTINES

	LINK	OCCROM53.ASM	;SIA ROUTINES

	LINK	OCCROM63.ASM	;DISK ROUTINES

	LINK	OCCROM73.ASM	;DIAGNOSIC ROUTINES

	LINK	OCCROM83.ASM	;FORMAT ROUTINE

	LINK	OCCROM93.ASM	;UTILITES

	LINK	OCCRAM2.ASM	;RAM LOCATIONS
;	Endx
