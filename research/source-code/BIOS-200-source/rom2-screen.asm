;ROM 2.0'S BOOT SCREEN (#247 step 8, turn 3) -- written, measured, and NOT in the
;monitor's tail, because it does not fit there.  This file is the code; the
;finding is the header; the decision is which home it gets.
;
;WHAT IT IS.  docs/rom-pico-protocol.md 4.1's sequence: clear BIT 9, fill the
;attribute array bright, print the fallback text, PRESENT(1) the frame's
;character half, check its trailer (six bytes of O1NEXT and the 16-bit sum over
;the 4088 before them), LDIR it over the text, PRESENT(2) and the attribute half,
;then PRESENT(0) to put the payload back for the hand-over.
;
;WHY IT IS NOT IN rom2.diff.  The 1.44 layout leaves 150 bytes above 0F67H,
;HCBOOT took 77 of them (0F67H-0FB3H, docs/o1-rom-2.0.md 4.7), and 72 are free to
the vendor's own guard (rom144.asm: IF RLWA > 0FFBH / .9 ERROR CODE TOO LARGE).
;This code is 182 bytes, and the assembler says so in its own words:
;
;    I 1021  .9   ERROR   CODE TOO LARGE..
;    2 ERRORs, 484 Labels, 81B9h bytes not used.   Program LWA = 1102h.
;
;Measured 2026-10-15 with tools/research/rom2asm.sh: with this code in the tail
;(and HCBOOT's 77 bytes in front of it) the guard fails at 0FB4H+182 = 106AH --
;110 bytes past the guard, and past the end of the 4 KB part.  The pieces:
;
;    the attribute fill: ENADIM, 4096 x FFH via LDIR, DISDIM           17 B
;    the fallback text: 21 characters and the OSTR call                28 B
;    the door helper: opcode, operand, poll, length, result code       22 B
;    three PRESENT calls (1, 2, 0)                                     24 B
;    the trailer: the 6-byte magic and the 16-bit sum over 4088 bytes  53 B
;    two LDIR blits of 4096 bytes                                      22 B
;    the latch writes around the attribute blit                         4 B
;    labels, returns and the odd long jump                             12 B
;                                                                     ----
;                                                                     182 B
;
;THE THREE HOMES, for the maintainer to choose (all three fit):
;
;  A. **a third content id in the softROM** -- PRESENT(3) serves this code from
;     a 4096-byte blob in the Pico's flash, beside the frame.  The monitor keeps
;     a ~21-byte stub: PRESENT(3), copy page 1 to RAM, jump.  The code runs from
;     RAM (bank-2 4000H-EFFFH is bank-1 RAM, unclaimed before CBOOT), which is
;     also where it can write the latch and the video RAM freely.  No payload
;     change, and the screen code stays *firmware*, like the frame it draws.
;  B. **the payload's spare** -- window page 1, 1E0FH-1FFFH, 497 bytes, where the
;     hand-over stub already lives.  The same stub, but the code travels with the
;     payload and rom2image.py has to place it.
;  C. **docs/o1-rom-2.0.md 4.7's Plan B** -- a banked loader, paged in by a
;     trampoline.  Buys 4 KB, costs paging machinery and a device change.
;
;The monitor's share is 21 bytes in A or B (the stub), or 43 with the fallback
;text left in the ROM -- of 72 free.  The rest of the tail stays spare.
;
;THE DOOR IS AT 2800H/2801H, NOT 2300H/2301H.  The onboard selects check two
;address bits each, so 2301H is the floppy's track register as well as the
;keyboard's row 0, and a reply ANDed with a track register reads "not ready" for
;ever (docs/rom-pico-protocol.md 2, docs/o1-mainboard-schematic.md 7a).
;
;This file is not assembled by anything yet: rom2asm.sh patches rom2.diff into
;rom144.asm and this is not in it.  It is the code the chosen home will carry.

;ROM 2.0'S BOOT SCREEN (#247).  docs/rom-pico-protocol.md 4.1: fill the attribute
;array bright, print the fallback text, ask for the frame's character half and
;check its trailer, blit it over the text, then the attribute half, then put the
;payload back -- because the frame and the payload are the same 4096 bytes of
;window page 1, and the hand-over needs the payload.
;
;THE DOOR IS AT 2800H/2801H, NOT 2300H/2301H.  The onboard selects check two
;address bits each, so 2301H is the floppy's track register as well as the
;keyboard's row 0, and a reply ANDed with a track register reads "not ready" for
;ever (docs/rom-pico-protocol.md 2, docs/o1-mainboard-schematic.md 7a).

SCRN:
	PROC

;1. the character RAM, not the attribute plane: F000H-FFFFH is the video RAM
;again (docs/rom-pico-protocol.md 4.1 step 1)
	DISDIM

;2. every cell bright.  The array is not a blank slate -- 24 of its 4096 cells
;read 7FH, dim, at the sign-on -- so this is not optional
	ENADIM
	LK	HL,0F000H
	STO	0FFH,[HL]
	LK	DE,0F001H
	LK	BC,0FF0H
	LDIR
	DISDIM

;3. the fallback, which is what stays on screen if there is no frame
	LDK	DE,SMSG
	CALL	OSTR

;4. PRESENT(1): the frame's character half into page 1
	LK	B,040H
	LK	C,1
	CALL	DOOR
	JNZ	SDONE		;no frame: the text stays, which is the whole point

;5. the trailer, at 0FF8H of the half: six bytes of magic, then the 16-bit sum of
;the 4088 bytes before them
	LK	HL,1FF8H
	LDK	DE,SMAG
	LK	C,6
SM1:	LD	A,[DE]
	LD	B,A
	LD	A,[HL]
	CMP	B
	JNZ	SDONE
	INC	HL
	INC	DE
	DEC	C
	JRNZ	SM1

	LK	HL,1000H
	LK	DE,0
	LK	BC,0FF8H
SS1:	LD	A,[HL]
	ADD	A,E
	MOV	E,A
	JRNC	SS2
	INC	D
SS2:	INC	HL
	DEC	BC
	MOV	A,B
	ORA	C
	JRNZ	SS1
	LD	A,0FFEH
	CMP	E
	JNZ	SDONE
	LD	A,0FFFH
	CMP	D
	JNZ	SDONE

;6. the blit: one LDIR of 4096 bytes, 21.5 ms at 4 MHz
	LK	HL,1000H
	LK	DE,0F000H
	LK	BC,1000H
	LDIR

;7. PRESENT(2), and the attribute half if it validates: that is the 9th bit, and a
;bad one costs only the bright fill that has already happened
	LK	B,040H
	LK	C,2
	CALL	DOOR
	JNZ	SPAY
	ENADIM
	LK	HL,1000H
	LK	DE,0F000H
	LK	BC,1000H
	LDIR
	DISDIM

;8. PRESENT(0): the payload back (docs/rom-pico-protocol.md 4.1 step 7)
SPAY:	LK	B,040H
	LK	C,0
	CALL	DOOR

SDONE:	RET


;THE DOOR.  B is the opcode and C its operand; the result code comes back in A.
;The transaction is the mailbox protocol's: the reply register reads 0 while the
;firmware is not ready, then the length, then the bytes (docs/mailbox-protocol.md
;3), so this is the ROM's own copy of what MOUNT.COM does on the other door.
DOOR:
	PROC
	MOV	A,B
	STO	A,2800H
	MOV	A,C
	STO	A,2800H
DR1:	LD	A,2801H
	ORA	A
	JZ	DR1
	LD	A,2801H		;the length
	LD	A,2801H		;the result code
	RET


;the fallback text: 21 characters, and the last one carries bit 7, which is the
;terminator OSTR looks for.  It replaces IMSG's 182 bytes, so it pays for itself
SMSG:	DB	'o1next - press retur'
	DB	'n'+80H

SMAG:	DB	'O1NEXT'
