;OCCBIO03.ASM
	TITLE	'Osborne CP/M 2.2 CBIOS.'

*NOTE*	FOR USE WITH OCCTXT6.AST ONLY

*	4D2007-00	MASTER	.ASM
*	2D2007-00	ASSY	.ASM
*	1D2007-00	LISTING	.PRN
*	4D1007-00	MASTER	.COM
*	2D1007-00	ASSY	.C0M

;	+-----------------------+
;	|			|
;	|	C B I O S 	|
;	|			|
;	+-----------------------+

;	Copyright 1981, Osborne.

;	This product is a copyright program product of
;	Osborne and is supplied for use with the Osborne.

;REV	=	1.2
;DATE	=	OCT 18 1981
;DEB

;	Revisions:
;	1.	Extensions to CBIOS added by:
;		Microcode Corporation.
;		Fremont, Ca
;		Y. N. Sahae
;		August 1981
;
;	2.	Programmable function keys added by:
;		Roger W. Chapman
;		October 1981
;
;	3.	Printer protocols added by:
;		Roger W. Chapman
;		October 1981
;
;	4.	Extensions added to BIOS and jump table standardized by:
;		Roger W. Chapman
;		October 1981
;
VERS:	=	22
	space	4,10

	LINK	OCCBIO13.ASM	;Jump Table
	LINK	OCCBIO23.ASM	;CP/M disk definitions
	LINK	OCCBIO33.ASM	;Unit record I/O
	LINK	OCCBIO43.ASM	;Non data transfer disk
	LINK	OCCBIO53.ASM	;cold and warm boot
	LINK	OCCBIO63.ASM	;Disk data transfer I/O
	LINK	OCCBIO73.ASM	;Utility routines
	LINK	OCCBIO83.ASM	;Utility routines
	LINK	OCCRAM2.ASM	;Commom ram definitions

;	END	OCCBIO03.ASM
