;	Sector Translation Tables.
	org	BIOS+256

XLTS:	;Translation table 2 to 1
	DB	 0, 1,   4, 5,   8, 9,  12,13, 16,17
	DB	 2, 3,   6, 7,  10,11,  14,15, 18,19
;	Translation 3 to 1
;	DB	 0, 1,   6, 7,  12,13,  18,19
;	DB	 2, 3,   8, 9,  14,15
;	DB	 4, 5,  10,11,  16,17
;	Translation 4 to 1
;	DB	 0, 1,   8, 9,  16,17
;	DB	 2, 3,  10, 11, 18,19
;	DB	 4, 5,  12, 13
;	DB	 6, 7,  14, 15
	IF	(*-XLTS) <> (MSEC*2)
	MSG	'Translation table error',ERROR
	ENDIF
	space	4,10
;	Control Blocks for disk drives

DPBASE:
	DPHGEN	DSKS1,XLTS,DIRBUF,DPBS1+1	;Drive A:

	DPHGEN	DSKS1,XLTS,DIRBUF,DPBS1+1	;Drive B:
	space	4,10
;	Disk type definition blocks for each particular mode.

DPBS1:		;Single density, single sided.

	DPBGEN	DSKS1,2*MSEC,4,15,1,S1DSM,64,1000000000000000b,3

.AL	IF	ALVSZ <> ALVS
	MSG	'Allocation problems ALVS<> ALVSZ, ALVSZ= ',ALVSZ
.9	ERROR
.AL	ENDIF


;	endx	OSBBIOS2
