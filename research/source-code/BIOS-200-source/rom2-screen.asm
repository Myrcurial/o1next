;ROM 2.0'S BOOT SCREEN AFTER #278 (2026-10-17) -- THE TRIGGER, AND WHAT IT COSTS.
;
;WHAT THIS FILE IS
;  The record of the screen code, which is now *in the monitor*: 26 bytes in the
;  free tail above HCBOOT.  It is what the sign-on prompt's `CALL SCRN` reaches
;  (rom2.diff, hunk 2), and it does three things -- fill the attribute array
;  bright, print the fallback, return.
;
;  It is a *record*, not the build.  The build is `rom2.diff`, which
;  tools/research/rom2asm.sh applies to the vendor's source; the code lines below
;  appear in that diff verbatim, and step 3b of that script fails if the two
;  drift (the fragment's code lines have to appear in the source being assembled,
;  in order).  That is why the code lines carry no prose.
;
;WHY IT IS 26 BYTES, AND WHAT THE FRAME PATH GAVE BACK
;  Until 2026-10-17 this code was 212 bytes -- the fill, the text, the door
;  helper, two trailer checks and two LDIR blits -- and it did not fit the 72
;  bytes the vendor's own guard leaves above HCBOOT.  So it lived in the
;  interposer's flash as a 4096-byte page served by PRESENT(3), copied to RAM at
;  4000H by a 51-byte stub, and the frame it blitted was served by PRESENT(1)/(2).
;
;  #278 retired that whole path.  The RP2354B is the display (docs/o1-rom-2.0.md
;  4.9; #277 is its own work): it snoops the Z80's video RAM, plays the animation
;  out of its own flash, and stops on the Z80's first video-RAM write.  So the Z80
;  serves no frame and draws none, and what is left of the screen is the *trigger*:
;
;    fill    19   DISDIM / ENADIM / LD HL,0F000H / LD (HL),0FFH / LD DE,0F001H /
;                 LD BC,0FFFH / LDIR / DISDIM -- every cell bright
;    print    6   LDK DE,IMSG / CALL OSTR
;    return   1   RET
;             --
;             26   against the 72 the stub gave back
;
;  The extent is the assembler's own, not this file's: `rom2asm.sh` reads
;  `Program LWA` and the `LENGTH OF THIS ROM IS = ` message and reports both, and
;  the guard at `IF RLWA > 0FFBH` is what says whether it fits.
;
;THE FILL IS PART OF THE TRIGGER
;  Not decoration, and not optional.  24 of the attribute array's 4096 cells read
;  7FH -- dim -- at the sign-on, so a screen that is not filled bright shows
;  scattered dim cells and the fallback's own dim runs stop being the only ones.
;  All 4096, too: the store covers 0F000H and the LDIR the 4095 after it, because
;  15 cells short is what the emulator measured on 2026-10-17.
;
;THE MESSAGE, AND WHERE IT LIVES
;  `IMSG` is not defined here: it is the vendor's own sign-on message slot at
;  019FH, and #278 put the fallback in it (rom2.diff, hunk 3).  The vendor's
;  182-byte message is gone -- the sign-on dispatch calls SCRN instead of printing
;  it -- and the fallback is 72 bytes of text in that slot with 110 bytes of the
;  vendor's FF fill behind it.  The slot keeps its *length* because there is no
;  ORG between IMSG and the tail: a shorter one would move every routine the CBIOS
;  calls by absolute address (docs/o1-rom-2.0.md 4.2).  The 110 bytes left over
;  are also what 4.7's signature and extension table will take.
;
;  What the message says is checked in two places, and neither is this file.
;  `rom2asm.sh` step 7 checks the slot's shape -- 72 bytes of text, the two lines,
;  bit 7 on the last byte, FF behind it -- and
;  tools/emulator-setup/mame-osborne1nx/bootscreen-check.sh reads the two video
;  planes back off the machine: rows 20 and 22, their own columns, and exactly the
;  three dim runs.  That run is the acceptance, because the text *is* the trigger:
;  move it and the RP2354B no longer sees the sign-on.
;
;HOW THE LISTING IS READ
;  `LIST -L,-R` turns the vendor's listing off and `LIST *` turns it back on for
;  this code, so a run lists ~30 lines instead of 4700.  The ACT80's `L=` option
;  sends the listing to a *file*: `ACT80 B:ROM2 H=B: L=B:` leaves ROM2.PRN on
;  drive B, complete and readable, at full speed.  Its markers are one character
;  in the left column: `E` error, `I` illegal mnemonic, `U` undefined symbol,
;  `D` duplicate label, `L` no code, `-` conditional false, `$` a Z80-relative
;  fixup.

	LIST	*
SCRN:
	PROC
	DISDIM
	ENADIM
	LK	HL,0F000H
	STO	0FFH,[HL]
	LK	DE,0F001H
	LK	BC,0FFFH
	LDIR
	DISDIM
	LDK	DE,IMSG
	CALL	OSTR
	RET
RLWA	=	*		;LWA OF ROM RESIDENT CODE

	MSG	'LENGTH OF THIS ROM IS = ',RLWA-1
	IF	RLWA > 0FFBH
.9	ERROR	CODE TOO LARGE..
	ENDIF
	ECHO	0FFFH-RLWA  !	DB   0FFH
	ENDM
