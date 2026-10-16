;ROM 2.0'S BOOT SCREEN (#247 step 8, turn 3) -- the code, its home, and where it
;stands.  Option 1 was chosen (2026-10-15): the screen's code is a third content
;id in the softROM (PRESENT(3)), served out of a 4096-byte blob in the Pico's
;flash, and the monitor keeps a ~60-byte stub that fetches it into RAM at 4000H
;and jumps.  The stub fits the 72 free bytes and the guard passes -- measured.
;
;WHAT IS PROVEN
;  * the stub + the blob assemble in ONE ACT80 pass: the blob's `ORG 4000H`
;    segment works, and the listing puts SCRN40 at 4000H, ending 40B7H
;  * the vendor's guard does NOT fire: RLWA is the monitor's own end (~0FE8H),
;    so the tail fits with room to spare
;  * the two pieces are independent of the *assembly*: the blob is extracted
;    from the same hex the monitor comes from
;
;WHAT WAS WRONG, AND HOW IT WAS FOUND (2026-10-15, session 4)
;  The new code reported 85 errors, and NOT ONE of them was the assembler's
;  dialect -- the blob assembles clean on its own, and every form in it is a form
;  DOCOP80.asm lists.  There were two defects, both read off the ACT80's own
;  listing:
;  * FIVE comment lines had lost their leading `;` (three of the four-line
;    comment before SCRN, and two of the four-line one before DOOR), so four were
;    assembled as illegal mnemonics -- an `I` marker each, three bytes of junk
;    code each, injected at 0FB4h and 0FD9h -- and the fifth, `prompt's own CALL
;    CI.`, as an unterminated string.  Five errors, and a moved SCRN and DOOR.
;  * the blob sat INSIDE the vendor's `ECHO 0FFFH-RLWA ! DB 0FFH ... ENDM` block.
;    `ECHO` repeats its body, so the blob was assembled and listed `0FFFH-RLWA`
;    = 11 times: ten extra passes over its eight labels, and therefore **80
;    duplicate-label errors**, which are the `D` markers.  The blob goes AFTER
;    the vendor's `ENDM`; that is what the `ENDM` below marks.
;  85 = 80 + 5.  With both fixed the same build reports `no ERRORs, 487 Labels,
;  Program LWA = 40B7h`, and the guard is still silent.
;
;TWO MORE DEFECTS, AND THE ACCEPTANCE FOUND THEM (2026-10-15, turn 4)
;  These two are in the *running* code, and neither is visible in a boot.  They
;  were found the first time the whole chain was measured end to end --
;  tools/emulator-setup/mame-osborne1nx/bootscreen-check.sh, which reads the two
;  video planes back off the machine:
;  * DOOR's `JNZ` tested flags left by its own *length* probe, because
;    `LD A,(NN)` does not set the flags -- so every caller took its "no such
;    content" path however well the door answered, and the machine printed the
;    stock 1.44 sign-on with the door answering OK (measured with a tap on
;    2800h/2801h: 40 03 written, 01 00 00 read back).
;  * the frame trailer's *sum* was read from the half's own 0FFEh instead of the
;    window's 1FFEh -- the magic check below had it right and this did not -- so
;    the check could never pass and the code returned before the blit: the screen
;    stayed the bright fill with no character written anywhere.
;  Fixed, the monitor is 128 bytes (`0F67h`-`0FE6h`, 21 free to the guard) and the
;  frame lands on both planes; with no splash mounted the run measures the
;  fallback instead, which is what says the frame is this code's doing.
;
;HOW THE LISTING IS READ (and why throttling was not the answer)
;  `o1keys.sh` now takes `O1_MAME_EXTRA` (default `-nothrottle`), so a run can be
;  throttled -- but the listing never needs watching.  The ACT80's `L=` option
;  sends it to a *file*: `ACT80 B:ROM2 H=B: L=B:` leaves ROM2.PRN on drive B,
;  complete and readable, at full speed.  Its markers are one character in the
;  left column: `E` error, `I` illegal mnemonic, `U` undefined symbol, `D`
;  duplicate label, `L` no code, `-` conditional false, `$` a Z80-relative fixup.
;
;THE LIST WINDOWS BELOW ARE PART OF THE DIAGNOSIS: `LIST -L,-R` turns the
;vendor's listing off and `LIST *` turns it back on for this code, so a run lists
;~65 lines instead of 4700.

	LIST	*		;ROM 2.0's own code, listed: the vendor's stays off
;ROM 2.0'S BOOT SCREEN (#247).  The screen's code is 182 bytes and the tail has
;72 (docs/o1-rom-2.0.md 4.7), so the code lives in the interposer's flash and this
;is the stub that fetches it: PRESENT(3) puts it in window page 1, the LDIR copies
;it to RAM at 4000H, and the jump enters it.  The RAM code prints the fallback
;text, fills the attribute array bright, draws the frame if there is one, puts the
;payload back, and RETs -- which returns to this CALL's caller, the sign-on
;prompt's own CALL CI.
;
;With no screen code in the flash the door answers 09H and the stock sign-on
;message is printed instead, so an interposer without the blob is a 1.44
;(docs/rom-pico-protocol.md 4.2).
;
;4000H is bank-1 RAM, mirrored in bank 2 and unclaimed before CBOOT
;(docs/rom-pico-protocol.md 6).  The code has to run from RAM because page 1 is
;where the frame goes: presenting the frame evicts the code.
DOORQ:	=	2800H		;the ROM service: the request register
DOORR:	=	2801H		;... and its reply register

SCRN:
	PROC
	LK	B,040H		;PRESENT
	LK	C,3		;... content 3: the screen code
	CALL	DOOR
	JNZ	SCRN44		;no such content: the 1.44's own message instead
	LK	HL,1000H	;the code, out of window page 1
	LK	DE,4000H	;... to RAM
	LK	BC,1000H	;4096 bytes: the whole page
	LDIR
	JMP	4000H		;... and enter it; its RET returns to our caller
SCRN44:	LDK	DE,IMSG
	CALL	OSTR		;the stock sign-on message
	RET
;THE DOOR, and both callers share it -- the stub above and the RAM code below.
;B is the opcode, C its operand, and the result code comes back in A *with the
;flags set from it*, because the flags are what both callers test.  The
;transaction is the mailbox protocol's: the reply register reads 0 while the
;firmware is not ready, then the length, then the bytes (docs/mailbox-protocol.md
;3).  The address is 2800H/2801H, not 2300H/2301H, because the onboard selects
;check two address bits and 2301H is the floppy's track register as well as the
;keyboard's row 0 (docs/rom-pico-protocol.md 2, docs/o1-mainboard-schematic.md 7a).
;
;THE `ORA A` BEFORE THE `RET` IS NOT DECORATION, AND ITS ABSENCE WAS THE FIRST
;DEFECT THE EMULATOR FOUND IN THIS CODE (2026-10-15, #247 turn 4).  `LD A,(NN)`
;DOES NOT SET THE FLAGS, so `JNZ` after `CALL DOOR` was testing the flags left by
;the *length* probe -- non-zero whenever the door answered at all -- and every
;caller took its "no such content" path whatever the reply said.  The assembly
;was right, the device was right, the door answered OK, and the machine printed
;the stock 1.44 sign-on anyway: measured, not deduced (a read/write tap on the
;door showed 40 03 written and 01 00 00 read back, and the stock message on the
;screen).  The result code is read once, into A, and the flags come from *it*.
;
;AND ONE READ IS ENOUGH because every reply this code asks for is one byte long --
;PRESENT answers with the result code alone.  A longer reply (INFO's three, ECHO's
;two) is left part-read, which the protocol allows: a write abandons a pending
;reply (mailbox-protocol.md 3).  This code never sends one.
;
;THE LINE HAS NO COMMENT ON PURPOSE.  `rom2.diff` is what the assembler is given,
;and the build has a measured size sensitivity (docs/rom-13-reconstruction.md 7):
;a source two bytes longer put the hex file's tail on a record the emulator's
;floppy write-back damages, and the same two bytes came back.  So the code lines
;here and in the diff are byte-identical and carry no prose; the reasoning is
;this comment block, which emits nothing.
DOOR:
	PROC
	MOV	A,B
	STO	A,DOORQ
	MOV	A,C
	STO	A,DOORQ
DR1:	LD	A,DOORR		;the length
	ORA	A
	JZ	DR1
	LD	A,DOORR		;the result code
	ORA	A
	RET
RLWA	=	*		;LWA OF ROM RESIDENT CODE

	MSG	'LENGTH OF THIS ROM IS = ',RLWA-1
	IF	RLWA > 0FFBH
.9	ERROR	CODE TOO LARGE..
	ENDIF

	ECHO	0FFFH-RLWA  !	DB   0FFH
	ENDM			;THE VENDOR'S OWN, AND THE BLOB MUST FOLLOW IT.  `ECHO`
				;repeats its body, so code placed *inside* this block
				;is assembled and listed `0FFFH-RLWA` times -- 11 here,
				;which is 10 extra passes over the blob's 8 labels and
				;80 duplicate-label errors.  Measured 2026-10-15 (#247).
	ORG	4000H		;THE SCREEN'S CODE, where the stub puts it (#247)
SCRN40:
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
;3. the barebones sign-on, which is what stays if there is no frame.  Short on
;purpose: the text is cheap here, and the art's own caption inside the X says the
;same thing in its own words
	LDK	DE,SMSG
	CALL	OSTR
;4. PRESENT(1): the frame's character half into page 1
	LK	B,040H
	LK	C,1
	CALL	DOOR
	JNZ	SCRET		;no frame: the text stays, which is the whole point
;5. the trailer, at 0FF8H of the half: six bytes of magic, then the 16-bit sum of
;the 4088 bytes before them.  THE SUM IS AT 1FFEH, NOT 0FFEH -- the *half's*
;0FFEh is the *window's* 1FFEh, and reading 0FFEh reads the ROM's own byte (0FFh
;from the vendor's fill) so the sum can never match.  That was the second defect
;the emulator found (2026-10-15, #247 turn 4): the magic check below is right and
;the sum check was not, and the code returned before the blit -- the screen stayed
;the bright fill, with no character written anywhere.  Measured, not deduced.
	LK	HL,1FF8H
	LDK	DE,SMAG
	LK	C,6
SM1:	LD	A,[DE]
	MOV	B,A
	LD	A,[HL]
	CMP	B
	JNZ	SCRET
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
	LD	A,1FFEH
	CMP	E
	JNZ	SCRET
	LD	A,1FFFH
	CMP	D
	JNZ	SCRET
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
;8. PRESENT(0): the payload back, because the frame and the payload are the same
;4096 bytes of page 1 and the hand-over needs it (docs/rom-pico-protocol.md 4.1)
SPAY:	LK	B,040H
	LK	C,0
	CALL	DOOR
SCRET:	RET
;the barebones fallback: the last character carries bit 7, which is the terminator
;OSTR looks for
SMSG:	DB	'o1next  rom 2.0 2026',CR,LF
	DB	'press return to begi'
	DB	'n'+80H
SMAG:	DB	'O1NEXT'
