	TITLE	'ACD#EG - Example ACT program using Link.'
;ACD#EG - Example ACT program using Link.
;		79/07/03


@ILIST	SET	1	;Select list of comdecks
	Link	UTIL.acd	;Note that UTIL will be read after this
				;file is finished.

	ORG	100h
ACD#EG:			;Entry from system
	EX	[sp],HL	;nonsensical program
	LDK	DE,80h
	LDK	HL,0	;wipe out low core
	CALL	FILLZ	;call subroutine in UTIL.acd
	JMP	[hl]

;	Note that this assembly is missing an END statement.
;	This is the last line in file ACD#EG.ASM.
