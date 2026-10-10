; z80dasm 1.2.0
; command line: z80dasm -a -l -g 0x100 -o research/drive_c/disasm/dcl.asm research/drive_c/extracted/dcl.com

	org 00100h

l0100h:
	jp l025ah		;0100
l0103h:
	dec c			;0103
	ld b,h			;0104
	ld d,d			;0105
	ld c,c			;0106
	ld d,(hl)		;0107
	ld b,l			;0108
	ld b,e			;0109
	jr nz,l0182h		;010a
	ld h,l			;010c
	ld (hl),d		;010d
	ld (hl),e		;010e
l010fh:
	ld l,c			;010f
	ld l,a			;0110
l0111h:
	ld l,(hl)		;0111
l0112h:
	jr nz,l0146h		;0112
l0114h:
	ld l,030h		;0114
l0116h:
	jr c,l0122h		;0116
l0118h:
	dec c			;0118
l0119h:
	ld b,e			;0119
	ld l,a			;011a
l011bh:
	ld (hl),b		;011b
	ld a,c			;011c
l011dh:
	ld (hl),d		;011d
	ld l,c			;011e
l011fh:
	ld h,a			;011f
l0120h:
	ld l,b			;0120
	ld (hl),h		;0121
l0122h:
	jr nz,l014ch		;0122
	ld h,e			;0124
	add hl,hl		;0125
sub_0126h:
	jr nz,l0159h		;0126
	add hl,sp		;0128
	jr c,l015eh		;0129
	jr nz,l0171h		;012b
	ld (hl),d		;012d
	ld l,c			;012e
	halt			;012f
	ld h,l			;0130
	jr nz,l0176h		;0131
	ld a,(l0a2ch)		;0133
	dec c			;0136
	ld b,c			;0137
	ld l,h			;0138
	ld l,h			;0139
	jr nz,l01aeh		;013a
	ld l,c			;013c
	ld h,a			;013d
	ld l,b			;013e
	ld (hl),h		;013f
	ld (hl),e		;0140
	jr nz,l01b5h		;0141
	ld h,l			;0143
	ld (hl),e		;0144
	ld h,l			;0145
l0146h:
	ld (hl),d		;0146
	halt			;0147
	ld h,l			;0148
	ld h,h			;0149
	dec c			;014a
	ld a,(bc)		;014b
l014ch:
	ld a,(de)		;014c
l014dh:
	ld b,e			;014d
	ld h,c			;014e
	ld l,(hl)		;014f
	ld l,(hl)		;0150
	ld l,a			;0151
	ld (hl),h		;0152
	jr nz,l01beh		;0153
	ld l,(hl)		;0155
	ld (hl),e		;0156
	ld (hl),h		;0157
	ld h,c			;0158
l0159h:
	ld l,h			;0159
sub_015ah:
	ld l,h			;015a
	jr nz,l01c1h		;015b
	ld (hl),d		;015d
l015eh:
	ld l,c			;015e
	halt			;015f
	ld h,l			;0160
	ld (hl),d		;0161
	inc h			;0162
l0163h:
	ld b,h			;0163
	ld (hl),d		;0164
	ld l,c			;0165
	halt			;0166
	ld h,l			;0167
	ld (hl),d		;0168
	jr nz,l01d4h		;0169
	ld (hl),e		;016b
	jr nz,l01cfh		;016c
	ld l,h			;016e
	ld (hl),d		;016f
	ld h,l			;0170
l0171h:
	ld h,c			;0171
	ld h,h			;0172
	ld a,c			;0173
	jr nz,l01dfh		;0174
l0176h:
	ld l,(hl)		;0176
	ld (hl),e		;0177
	ld (hl),h		;0178
	ld h,c			;0179
	ld l,h			;017a
	ld l,h			;017b
l017ch:
	ld h,l			;017c
	ld h,h			;017d
	inc h			;017e
l017fh:
	nop			;017f
l0180h:
	ld b,h			;0180
	ld (hl),d		;0181
l0182h:
	ld l,c			;0182
	halt			;0183
	ld h,l			;0184
	jr nz,$+69		;0185
	ld a,(0d9d3h)		;0187
	out (000h),a		;018a
	nop			;018c
	nop			;018d
	nop			;018e
	nop			;018f
	nop			;0190
	nop			;0191
	nop			;0192
	nop			;0193
	nop			;0194
	nop			;0195
	nop			;0196
	nop			;0197
	nop			;0198
	nop			;0199
	nop			;019a
	nop			;019b
	nop			;019c
	nop			;019d
	nop			;019e
l019fh:
	nop			;019f
	ld b,h			;01a0
	ld b,(hl)		;01a1
	ld b,h			;01a2
	jr nz,l01c5h		;01a3
	jr nz,l01c7h		;01a5
	jr nz,l017ch		;01a7
	ret nc			;01a9
	ld d,d			;01aa
	nop			;01ab
	nop			;01ac
	nop			;01ad
l01aeh:
	nop			;01ae
	nop			;01af
	nop			;01b0
	nop			;01b1
	nop			;01b2
	nop			;01b3
	nop			;01b4
l01b5h:
	nop			;01b5
	nop			;01b6
	nop			;01b7
	nop			;01b8
	nop			;01b9
	nop			;01ba
	nop			;01bb
	nop			;01bc
	nop			;01bd
l01beh:
	nop			;01be
	nop			;01bf
	nop			;01c0
l01c1h:
	nop			;01c1
	nop			;01c2
l01c3h:
	ld (bc),a		;01c3
	ld b,h			;01c4
l01c5h:
	ld b,(hl)		;01c5
	ld b,h			;01c6
l01c7h:
	jr nz,l01e9h		;01c7
	jr nz,l01ebh		;01c9
	jr nz,l0220h		;01cb
	ld d,b			;01cd
	ld d,d			;01ce
l01cfh:
	nop			;01cf
	nop			;01d0
	nop			;01d1
	nop			;01d2
l01d3h:
	nop			;01d3
l01d4h:
	nop			;01d4
	nop			;01d5
	nop			;01d6
	nop			;01d7
	nop			;01d8
	nop			;01d9
	nop			;01da
	nop			;01db
	nop			;01dc
	nop			;01dd
	nop			;01de
l01dfh:
	nop			;01df
	nop			;01e0
	nop			;01e1
	nop			;01e2
	nop			;01e3
	nop			;01e4
	nop			;01e5
	nop			;01e6
l01e7h:
	nop			;01e7
	ld b,h			;01e8
l01e9h:
	ld b,e			;01e9
	ld d,l			;01ea
l01ebh:
	jr nz,l020dh		;01eb
	jr nz,l020fh		;01ed
	jr nz,$+69		;01ef
	ld c,a			;01f1
	ld c,l			;01f2
	nop			;01f3
	nop			;01f4
	nop			;01f5
	nop			;01f6
	nop			;01f7
	nop			;01f8
	nop			;01f9
	nop			;01fa
l01fbh:
	nop			;01fb
	nop			;01fc
	nop			;01fd
	nop			;01fe
	nop			;01ff
	nop			;0200
	nop			;0201
	nop			;0202
	nop			;0203
	nop			;0204
	nop			;0205
	nop			;0206
	nop			;0207
	nop			;0208
	nop			;0209
	nop			;020a
l020bh:
	ld (bc),a		;020b
	ld b,h			;020c
l020dh:
	ld b,e			;020d
	ld d,l			;020e
l020fh:
	jr nz,l0231h		;020f
	jr nz,l0233h		;0211
	jr nz,l0258h		;0213
	ld c,a			;0215
l0216h:
	ld c,l			;0216
l0217h:
	nop			;0217
	nop			;0218
l0219h:
	nop			;0219
	nop			;021a
	nop			;021b
	nop			;021c
	nop			;021d
	nop			;021e
	nop			;021f
l0220h:
	nop			;0220
	nop			;0221
	nop			;0222
	nop			;0223
	nop			;0224
	nop			;0225
	nop			;0226
	nop			;0227
	nop			;0228
	nop			;0229
	nop			;022a
	nop			;022b
	nop			;022c
	nop			;022d
	nop			;022e
l022fh:
	ld (bc),a		;022f
	ld b,h			;0230
l0231h:
	ld b,e			;0231
	ld c,(hl)		;0232
l0233h:
	jr nz,l0255h		;0233
	jr nz,$+34		;0235
	jr nz,l027ch		;0237
	ld c,a			;0239
	ld c,l			;023a
	nop			;023b
	nop			;023c
	nop			;023d
	nop			;023e
	nop			;023f
	nop			;0240
	nop			;0241
	nop			;0242
	nop			;0243
	nop			;0244
	nop			;0245
	nop			;0246
	nop			;0247
	nop			;0248
	nop			;0249
	nop			;024a
	nop			;024b
	nop			;024c
	nop			;024d
	nop			;024e
	nop			;024f
	nop			;0250
	nop			;0251
	nop			;0252
l0253h:
	nop			;0253
l0254h:
	nop			;0254
l0255h:
	ld bc,00000h		;0255
l0258h:
	nop			;0258
	nop			;0259
l025ah:
	di			;025a
	ld hl,(0ef0fh)		;025b
	ld (l0258h),hl		;025e
	ld sp,05000h		;0261
	ld hl,(00006h)		;0264
	ld a,l			;0267
	ld de,l014dh		;0268
	cp 006h			;026b
	jr z,l0277h		;026d
l026fh:
	ld c,009h		;026f
	call 00005h		;0271
	jp 00000h		;0274
l0277h:
	ld l,011h		;0277
	ld a,(hl)		;0279
	cp 054h			;027a
l027ch:
	ld de,l0163h		;027c
	jr z,l026fh		;027f
	ld c,019h		;0281
	call 00005h		;0283
	ld (l0255h+2),a		;0286
	ld hl,0005dh		;0289
	ld a,(0005ch)		;028c
	or a			;028f
	jr nz,l029fh		;0290
	ld a,(hl)		;0292
	cp 020h			;0293
	jr z,l02afh		;0295
l0297h:
	cp 044h			;0297
l0299h:
	jr nc,l02afh		;0299
	sub 040h		;029b
	jr c,l02afh		;029d
l029fh:
	dec a			;029f
	ld hl,0006dh		;02a0
	ld (l1516h),a		;02a3
	cp 002h			;02a6
	jr nc,l02afh		;02a8
sub_02aah:
	ld a,002h		;02aa
	ld (l153eh),a		;02ac
l02afh:
	ld a,000h		;02af
	ld b,a			;02b1
	ld (l0255h+1),a		;02b2
	ld a,(hl)		;02b5
	cp 050h			;02b6
	jp z,l033dh		;02b8
	cp 020h			;02bb
	jr z,l0319h		;02bd
l02bfh:
	sub 030h		;02bf
	jr c,l0311h		;02c1
	cp 00ah			;02c3
	jr nc,l0311h		;02c5
	ld c,a			;02c7
	sla b			;02c8
	ld a,b			;02ca
sub_02cbh:
	sla a			;02cb
	sla a			;02cd
	add a,b			;02cf
	add a,c			;02d0
	ld b,a			;02d1
	inc hl			;02d2
	ld a,(hl)		;02d3
	cp 020h			;02d4
	jr nz,l02bfh		;02d6
	ld a,b			;02d8
	or a			;02d9
	jr z,l0311h		;02da
	and 007h		;02dc
	jr nz,l0311h		;02de
	ld a,b			;02e0
	cp 081h			;02e1
	jr nc,l0311h		;02e3
	ld (l0255h+1),a		;02e5
	jr l033dh		;02e8
l02eah:
	ld b,d			;02ea
	ld h,c			;02eb
	ld h,h			;02ec
	jr nz,l035fh		;02ed
	ld (hl),d		;02ef
	ld l,c			;02f0
	ld l,(hl)		;02f1
	ld (hl),h		;02f2
sub_02f3h:
	jr nz,$+100		;02f3
	ld (hl),l		;02f5
	ld h,(hl)		;02f6
	ld h,(hl)		;02f7
	ld h,l			;02f8
	ld (hl),d		;02f9
	jr nz,l036ch		;02fa
	ld h,c			;02fc
	ld (hl),d		;02fd
	ld h,c			;02fe
	ld l,l			;02ff
	ld h,l			;0300
	ld (hl),h		;0301
	ld h,l			;0302
	ld (hl),d		;0303
	inc l			;0304
	jr nz,l0375h		;0305
	ld l,a			;0307
	ld (hl),h		;0308
	jr nz,l0377h		;0309
	ld l,a			;030b
	ld h,c			;030c
	ld h,h			;030d
	ld h,l			;030e
	ld h,h			;030f
	inc h			;0310
l0311h:
	ld de,l02eah		;0311
	ld c,009h		;0314
	call 00005h		;0316
l0319h:
	ld a,000h		;0319
	ld (l0255h),a		;031b
	ld a,0c9h		;031e
	ld (l1638h),a		;0320
	ld de,(l1514h)		;0323
	ld hl,l010fh		;0327
	add hl,de		;032a
	ex de,hl		;032b
	ld hl,01610h		;032c
	ld (hl),e		;032f
	inc hl			;0330
	ld (hl),d		;0331
	ld hl,0001eh		;0332
	add hl,de		;0335
	ex de,hl		;0336
	ld hl,0162eh		;0337
	ld (hl),e		;033a
	inc hl			;033b
	ld (hl),d		;033c
l033dh:
	ld hl,(00006h)		;033d
	ld l,000h		;0340
	ld de,(l1001h)		;0342
	ld a,e			;0346
	or a			;0347
	jr z,l034dh		;0348
	inc d			;034a
	ld e,000h		;034b
l034dh:
	or a			;034d
	sbc hl,de		;034e
	ld (l0253h),hl		;0350
	ld hl,l1100h		;0353
	ld bc,(l1001h)		;0356
	push hl			;035a
	add hl,bc		;035b
	push hl			;035c
	pop ix			;035d
l035fh:
	pop hl			;035f
	ld d,001h		;0360
l0362h:
	rrc d			;0362
	jr nc,l036bh		;0364
l0366h:
	ld e,(ix+000h)		;0366
	inc ix			;0369
l036bh:
	ld a,d			;036b
l036ch:
	and e			;036c
	jr z,l0375h		;036d
	ld a,(l0254h)		;036f
	dec a			;0372
	add a,(hl)		;0373
	ld (hl),a		;0374
l0375h:
	inc hl			;0375
	dec bc			;0376
l0377h:
	ld a,b			;0377
	or c			;0378
	jr nz,l0362h		;0379
	ld hl,(00001h)		;037b
	ld de,00007h		;037e
	add hl,de		;0381
	ld e,(hl)		;0382
	inc hl			;0383
	ld d,(hl)		;0384
	ld b,d			;0385
	ex de,hl		;0386
	inc hl			;0387
	ld e,(hl)		;0388
	inc hl			;0389
	ld d,(hl)		;038a
	ld a,d			;038b
	cp b			;038c
	jr nz,l03ach		;038d
	ex de,hl		;038f
	ld e,(hl)		;0390
	inc hl			;0391
	ld d,(hl)		;0392
	ld a,d			;0393
	cp b			;0394
	jr nz,l03ach		;0395
	ex de,hl		;0397
	ld a,0cdh		;0398
	cp (hl)			;039a
	jr z,l03a2h		;039b
	inc hl			;039d
	inc hl			;039e
	cp (hl)			;039f
	jr nz,l03ach		;03a0
l03a2h:
	inc hl			;03a2
	ld e,(hl)		;03a3
	inc hl			;03a4
	ld d,(hl)		;03a5
	ld hl,01642h		;03a6
	ld (hl),e		;03a9
	inc hl			;03aa
	ld (hl),d		;03ab
l03ach:
	ld hl,(l0258h)		;03ac
	ld (l1630h),hl		;03af
	ld hl,(l1514h)		;03b2
	ld de,l1100h		;03b5
	add hl,de		;03b8
	ex de,hl		;03b9
	ld hl,(00001h)		;03ba
	ld l,000h		;03bd
	push hl			;03bf
	ld bc,00030h		;03c0
	ldir			;03c3
	ld hl,(l0253h)		;03c5
	ld de,l0500h		;03c8
	add hl,de		;03cb
	ex de,hl		;03cc
	pop hl			;03cd
	ld b,010h		;03ce
l03d0h:
	ld (hl),0c3h		;03d0
	inc hl			;03d2
	ld (hl),e		;03d3
	inc hl			;03d4
	ld (hl),d		;03d5
	inc hl			;03d6
	inc de			;03d7
	inc de			;03d8
	inc de			;03d9
	djnz l03d0h		;03da
	ld de,l1109h		;03dc
	ld a,(l0255h)		;03df
	or a			;03e2
	jr nz,l03eah		;03e3
	ld hl,l0400h		;03e5
l03e8h:
	add hl,de		;03e8
	ex de,hl		;03e9
l03eah:
	ld hl,(00006h)		;03ea
	ld l,009h		;03ed
	ld bc,00008h		;03ef
	ldir			;03f2
	ld hl,(l0253h)		;03f4
	ld a,(l0255h)		;03f7
	or a			;03fa
	jr nz,l0401h		;03fb
	ld de,l0400h		;03fd
l0400h:
	add hl,de		;0400
l0401h:
	ld (l15feh),hl		;0401
	ld l,006h		;0404
	ld (00006h),hl		;0406
	ld hl,l1100h		;0409
	ld de,(l0253h)		;040c
	ld bc,(l1001h)		;0410
	ldir			;0414
	ld de,00080h		;0416
	ld hl,l03e8h		;0419
	ld c,001h		;041c
	call sub_06b7h		;041e
	ld hl,00080h		;0421
	ld a,(hl)		;0424
	cpl			;0425
	ld (hl),a		;0426
l0427h:
	push af			;0427
	ld de,00080h		;0428
	ld hl,l03e8h		;042b
	ld c,001h		;042e
	call sub_06bfh		;0430
	ld de,00080h		;0433
	ld hl,l03e8h		;0436
	ld c,001h		;0439
	call sub_06b7h		;043b
	pop af			;043e
	ld hl,00080h		;043f
	cp (hl)			;0442
	cpl			;0443
	ld (hl),a		;0444
	jr z,l045bh		;0445
	ld hl,(l0253h)		;0447
	ld de,00431h		;044a
	add hl,de		;044d
	ld (hl),003h		;044e
	inc hl			;0450
	ld (hl),007h		;0451
	inc hl			;0453
	ld (hl),000h		;0454
	inc hl			;0456
	inc hl			;0457
	inc hl			;0458
	ld (hl),03fh		;0459
l045bh:
	ld de,00080h		;045b
	ld hl,l03e8h		;045e
	ld c,001h		;0461
	call sub_06bfh		;0463
	ld de,00080h		;0466
	ld hl,00000h		;0469
	ld c,001h		;046c
	call sub_06b7h		;046e
l0471h:
	ld hl,l0180h		;0471
	ld de,00081h		;0474
	ld b,01fh		;0477
l0479h:
	ld a,(de)		;0479
	cp (hl)			;047a
	jr nz,l0484h		;047b
	inc hl			;047d
	inc de			;047e
	djnz l0479h		;047f
	jp l04b0h		;0481
l0484h:
	ld hl,00080h		;0484
	ld de,00081h		;0487
	ld bc,0007fh		;048a
	ld (hl),0e5h		;048d
	ldir			;048f
	ld c,001h		;0491
	call sub_06ebh		;0493
	ld c,002h		;0496
	call sub_06ebh		;0498
	ld hl,l017fh		;049b
	ld bc,00020h		;049e
	ld de,00080h		;04a1
	push de			;04a4
	ldir			;04a5
	pop de			;04a7
	ld hl,00000h		;04a8
	ld c,001h		;04ab
	call sub_06bfh		;04ad
l04b0h:
	ld c,00dh		;04b0
	call 00005h		;04b2
	ld a,(l1516h)		;04b5
	inc a			;04b8
	ld (l01c3h),a		;04b9
	ld (l020bh),a		;04bc
	ld (l022fh),a		;04bf
	ld a,(l153eh)		;04c2
	cp 0ffh			;04c5
	jr z,l04d0h		;04c7
	inc a			;04c9
	ld (l019fh),a		;04ca
	ld (l01e7h),a		;04cd
l04d0h:
	ld c,020h		;04d0
	ld e,00fh		;04d2
	call 00005h		;04d4
	ld c,011h		;04d7
	ld de,l01c3h		;04d9
	call 00005h		;04dc
	sub 0ffh		;04df
	jp nz,l0554h		;04e1
	ld c,020h		;04e4
	ld e,000h		;04e6
	call 00005h		;04e8
	ld c,00fh		;04eb
	ld de,l019fh		;04ed
	call 00005h		;04f0
	cp 0ffh			;04f3
	jr z,l052eh		;04f5
	ld c,020h		;04f7
	ld e,00fh		;04f9
	call 00005h		;04fb
	ld c,016h		;04fe
l0500h:
	ld de,l01c3h		;0500
	call 00005h		;0503
sub_0506h:
	cp 0ffh			;0506
	jr z,l052eh		;0508
l050ah:
	ld c,020h		;050a
	ld e,000h		;050c
	call 00005h		;050e
	ld c,014h		;0511
	ld de,l019fh		;0513
l0516h:
	call 00005h		;0516
l0519h:
	or a			;0519
l051ah:
	jr nz,l0538h		;051a
l051ch:
	ld c,020h		;051c
l051eh:
	ld e,00fh		;051e
	call 00005h		;0520
	ld c,015h		;0523
	ld de,l01c3h		;0525
	call 00005h		;0528
l052bh:
	or a			;052b
	jr z,l050ah		;052c
l052eh:
	ld de,l014dh		;052e
l0531h:
	ld c,009h		;0531
	call 00005h		;0533
l0536h:
	jr l0536h		;0536
l0538h:
	ld c,020h		;0538
	ld e,00fh		;053a
	call 00005h		;053c
	ld c,010h		;053f
	ld de,l01c3h		;0541
	call 00005h		;0544
	ld a,0d3h		;0547
	ld (001cch),a		;0549
	ld c,01eh		;054c
	ld de,l01c3h		;054e
	call 00005h		;0551
l0554h:
	ld c,020h		;0554
	ld e,000h		;0556
	call 00005h		;0558
	ld a,(l0255h)		;055b
	or a			;055e
	jr z,l05afh		;055f
	ld c,011h		;0561
	ld de,l020bh		;0563
	call 00005h		;0566
	cp 0ffh			;0569
	jr nz,l05afh		;056b
	ld c,00fh		;056d
	ld de,l01e7h		;056f
	call 00005h		;0572
	cp 0ffh			;0575
	jr nz,l0583h		;0577
l0579h:
	ld c,009h		;0579
	ld de,l067dh		;057b
	call 00005h		;057e
	jr l05afh		;0581
l0583h:
	ld c,016h		;0583
	ld de,l020bh		;0585
	call 00005h		;0588
	cp 0ffh			;058b
	jr z,l0579h		;058d
l058fh:
	ld c,014h		;058f
	ld de,l01e7h		;0591
	call 00005h		;0594
	or a			;0597
	jr nz,l05a7h		;0598
	ld c,015h		;059a
	ld de,l020bh		;059c
	call 00005h		;059f
	or a			;05a2
	jr nz,l0579h		;05a3
	jr l058fh		;05a5
l05a7h:
	ld c,010h		;05a7
	ld de,l020bh		;05a9
	call 00005h		;05ac
l05afh:
	ld c,011h		;05af
	ld de,l022fh		;05b1
	call 00005h		;05b4
	cp 0ffh			;05b7
	jr nz,l05f5h		;05b9
	ld c,016h		;05bb
	ld de,l022fh		;05bd
	call 00005h		;05c0
	cp 0ffh			;05c3
	jr z,l05f5h		;05c5
	ld c,01ah		;05c7
	ld de,00900h		;05c9
	call 00005h		;05cc
	ld c,015h		;05cf
	ld de,l022fh		;05d1
	call 00005h		;05d4
	or a			;05d7
l05d8h:
	jr nz,l05f5h		;05d8
l05dah:
	ld c,01ah		;05da
	ld de,00980h		;05dc
	call 00005h		;05df
	ld c,015h		;05e2
	ld de,l022fh		;05e4
	call 00005h		;05e7
	or a			;05ea
	jr nz,l05f5h		;05eb
	ld c,010h		;05ed
	ld de,l022fh		;05ef
	call 00005h		;05f2
l05f5h:
	ld a,(l0255h)		;05f5
	or a			;05f8
	jr z,l0643h		;05f9
l05fbh:
	ld a,(l0255h+1)		;05fb
l05feh:
	or a			;05fe
	jr z,l0643h		;05ff
	ld de,(l0253h)		;0601
	ld hl,00431h		;0605
	add hl,de		;0608
	ld a,(hl)		;0609
	cp 003h			;060a
	ld a,(l0255h+1)		;060c
	jr z,l0613h		;060f
	srl a			;0611
l0613h:
	ld hl,00012h		;0613
	add hl,de		;0616
	ld (hl),a		;0617
	push de			;0618
	call sub_06b2h		;0619
	or a			;061c
	ld b,000h		;061d
	jr nz,l062fh		;061f
	xor a			;0621
	ld (l0255h+1),a		;0622
	ld c,009h		;0625
	ld de,l0655h		;0627
	call 00005h		;062a
	ld b,001h		;062d
l062fh:
	pop de			;062f
l0630h:
	ld hl,00012h		;0630
	add hl,de		;0633
	ld (hl),b		;0634
	ld hl,00011h		;0635
sub_0638h:
	add hl,de		;0638
	ld (hl),000h		;0639
l063bh:
	ld hl,l0118h		;063b
	add hl,de		;063e
	ld a,(l0255h+1)		;063f
	ld (hl),a		;0642
l0643h:
	ld a,(l1516h)		;0643
	ld e,a			;0646
	ld a,(l0255h+2)		;0647
	cp e			;064a
	jr nz,l064fh		;064b
	ld a,002h		;064d
l064fh:
	ld (00004h),a		;064f
	jp 00000h		;0652
l0655h:
	ld c,(hl)		;0655
l0656h:
	ld l,a			;0656
	ld (hl),h		;0657
	jr nz,sub_06bfh		;0658
	ld l,(hl)		;065a
	ld l,a			;065b
l065ch:
	ld (hl),l		;065c
	ld h,a			;065d
	ld l,b			;065e
	jr nz,$+117		;065f
	ld (hl),b		;0661
l0662h:
	ld h,c			;0662
	ld h,e			;0663
	ld h,l			;0664
	jr nz,$+104		;0665
	ld l,a			;0667
	ld (hl),d		;0668
	jr nz,$+104		;0669
l066bh:
	ld l,c			;066b
	ld a,b			;066c
	ld h,l			;066d
	ld h,h			;066e
	jr nz,$+114		;066f
	ld (hl),d		;0671
	ld l,c			;0672
	ld l,(hl)		;0673
	ld (hl),h		;0674
	jr nz,$+100		;0675
	ld (hl),l		;0677
	ld h,(hl)		;0678
	ld h,(hl)		;0679
	ld h,l			;067a
	ld (hl),d		;067b
	inc h			;067c
l067dh:
	ld c,(hl)		;067d
	ld l,a			;067e
	ld (hl),h		;067f
	ld h,l			;0680
	ld a,(07020h)		;0681
	ld (hl),d		;0684
	ld l,c			;0685
l0686h:
	ld l,(hl)		;0686
	ld (hl),h		;0687
	jr nz,$+100		;0688
	ld (hl),l		;068a
	ld h,(hl)		;068b
	ld h,(hl)		;068c
l068dh:
	ld h,l			;068d
	ld (hl),d		;068e
	jr nz,$+119		;068f
	ld (hl),h		;0691
sub_0692h:
	ld l,c			;0692
	ld l,h			;0693
l0694h:
	ld l,c			;0694
	ld (hl),h		;0695
	ld a,c			;0696
	jr nz,$+42		;0697
	ld b,h			;0699
	ld b,e			;069a
l069bh:
	ld d,l			;069b
	ld l,043h		;069c
	ld c,a			;069e
	ld c,l			;069f
	add hl,hl		;06a0
	jr nz,l0711h		;06a1
	ld l,a			;06a3
l06a4h:
	ld (hl),h		;06a4
	jr nz,l0708h		;06a5
	halt			;06a7
l06a8h:
	ld h,c			;06a8
	ld l,c			;06a9
	ld l,h			;06aa
	ld h,c			;06ab
	ld h,d			;06ac
	ld l,h			;06ad
	ld h,l			;06ae
	dec c			;06af
	ld a,(bc)		;06b0
	inc h			;06b1
sub_06b2h:
	ld hl,0005eh		;06b2
	add hl,de		;06b5
	jp (hl)			;06b6
sub_06b7h:
	call sub_06c9h		;06b7
	ld l,027h		;06ba
	jp l06e6h		;06bc
sub_06bfh:
	call sub_06c9h		;06bf
	ld l,02ah		;06c2
	ld c,000h		;06c4
	jp l06e6h		;06c6
sub_06c9h:
	push hl			;06c9
	push bc			;06ca
	push de			;06cb
	ld a,(l1516h)		;06cc
	ld c,a			;06cf
	ld l,01bh		;06d0
	call l06e6h		;06d2
sub_06d5h:
	pop bc			;06d5
	ld l,024h		;06d6
	call l06e6h		;06d8
	pop bc			;06db
	ld b,000h		;06dc
	ld l,021h		;06de
	call l06e6h		;06e0
	pop bc			;06e3
	ld l,01eh		;06e4
l06e6h:
	ld a,(00002h)		;06e6
	ld h,a			;06e9
	jp (hl)			;06ea
sub_06ebh:
	ld b,010h		;06eb
	ld hl,00000h		;06ed
l06f0h:
	push bc			;06f0
	push hl			;06f1
	ld de,00080h		;06f2
	call sub_06bfh		;06f5
	pop hl			;06f8
	pop bc			;06f9
	inc hl			;06fa
	dec b			;06fb
	jr nz,l06f0h		;06fc
l06feh:
	ret			;06fe
	ld (hl),h		;06ff
	ld c,a			;0700
	ld hl,00562h		;0701
	add hl,bc		;0704
	call sub_02f3h		;0705
l0708h:
	jp 00371h		;0708
	ld hl,00676h		;070b
	call sub_02f3h		;070e
l0711h:
	ld a,d			;0711
	call sub_0692h		;0712
	jp 00371h		;0715
	call 0002eh		;0718
	ld c,03fh		;071b
	call 00015h		;071d
	ld hl,(00013h)		;0720
	ld sp,hl		;0723
	ld hl,00000h		;0724
	add hl,sp		;0727
	ld (00013h),hl		;0728
	call 00338h		;072b
	ld (00011h),hl		;072e
	call 00689h		;0731
	call sub_015ah		;0734
	ld hl,(00011h)		;0737
	ld (0000ch),hl		;073a
	jp l052bh		;073d
	ld hl,(00013h)		;0740
	ld sp,hl		;0743
	ret			;0744
	nop			;0745
	rlca			;0746
	rrca			;0747
	rla			;0748
	rra			;0749
	daa			;074a
	cpl			;074b
	scf			;074c
	ccf			;074d
	halt			;074e
	ret			;074f
	ex (sp),hl		;0750
	jp (hl)			;0751
	ex de,hl		;0752
	di			;0753
	ld sp,hl		;0754
	ei			;0755
	add a,0ceh		;0756
	out (0d6h),a		;0758
	in a,(0deh)		;075a
	and 0eeh		;075c
	or 0feh			;075e
	ld (0322ah),hl		;0760
l0763h:
	ld a,(0cdc3h)		;0763
	ld b,l			;0766
	ld c,c			;0767
	jr nz,$+34		;0768
	ld d,e			;076a
sub_076bh:
	ld d,b			;076b
	ld c,b			;076c
	ld c,h			;076d
	ld b,h			;076e
	ld c,c			;076f
	jr nz,$+34		;0770
	ld e,b			;0772
	ld b,e			;0773
	ld c,b			;0774
	ld b,a			;0775
	ld d,b			;0776
	ld b,e			;0777
	ld c,b			;0778
	ld c,h			;0779
	ld e,b			;077a
	ld d,h			;077b
	ld c,b			;077c
	ld c,h			;077d
	ld d,d			;077e
	ld b,l			;077f
	ld d,h			;0780
	jr nz,l07cbh		;0781
	ld c,h			;0783
	ld d,h			;0784
	jr nz,$+69		;0785
	ld c,l			;0787
	ld b,e			;0788
	jr nz,$+85		;0789
	ld d,h			;078b
	ld b,e			;078c
	jr nz,$+69		;078d
	ld c,l			;078f
	ld b,c			;0790
	jr nz,l07d7h		;0791
	ld b,c			;0793
	ld b,c			;0794
	jr nz,l07e9h		;0795
	ld b,c			;0797
	ld d,d			;0798
	jr nz,l07edh		;0799
	ld b,c			;079b
	ld c,h			;079c
	jr nz,l07f1h		;079d
	ld d,d			;079f
	ld b,e			;07a0
	jr nz,l07f5h		;07a1
	ld c,h			;07a3
	ld b,e			;07a4
	jr nz,l07f5h		;07a5
	ld c,a			;07a7
	ld d,b			;07a8
	jr nz,$+69		;07a9
	ld d,b			;07ab
	ld c,c			;07ac
	jr nz,$+81		;07ad
	ld d,d			;07af
	ld c,c			;07b0
	jr nz,l080bh		;07b1
	ld d,d			;07b3
	ld c,c			;07b4
sub_07b5h:
	jr nz,l07f8h		;07b5
	ld c,(hl)		;07b7
	ld c,c			;07b8
	jr nz,$+85		;07b9
	ld b,d			;07bb
	ld c,c			;07bc
	jr nz,l0808h		;07bd
l07bfh:
	ld c,(hl)		;07bf
	jr nz,$+34		;07c0
	ld d,e			;07c2
	ld d,l			;07c3
	ld c,c			;07c4
	jr nz,$+81		;07c5
	ld d,l			;07c7
	ld d,h			;07c8
	jr nz,l080ch		;07c9
l07cbh:
	ld b,e			;07cb
	ld c,c			;07cc
	jr nz,l0810h		;07cd
	ld b,h			;07cf
	ld c,c			;07d0
	jr nz,$+69		;07d1
	ld b,c			;07d3
	ld c,h			;07d4
	ld c,h			;07d5
	ld c,d			;07d6
l07d7h:
	ld c,l			;07d7
	ld d,b			;07d8
	jr nz,l0827h		;07d9
	ld b,h			;07db
	ld b,c			;07dc
	jr nz,$+85		;07dd
	ld d,h			;07df
	ld b,c			;07e0
	jr nz,l082fh		;07e1
	ld c,b			;07e3
	ld c,h			;07e4
	ld b,h			;07e5
	ld d,e			;07e6
	ld c,b			;07e7
	ld c,h			;07e8
l07e9h:
	ld b,h			;07e9
	ld c,l			;07ea
	ld c,a			;07eb
	ld d,(hl)		;07ec
l07edh:
	jr nz,l0830h		;07ed
	ld b,h			;07ef
	ld b,h			;07f0
l07f1h:
	jr nz,l0834h		;07f1
	ld b,h			;07f3
	ld b,e			;07f4
l07f5h:
	jr nz,$+85		;07f5
	ld d,l			;07f7
l07f8h:
	ld b,d			;07f8
	jr nz,l084eh		;07f9
	ld b,d			;07fb
	ld b,d			;07fc
	jr nz,l0840h		;07fd
	ld c,(hl)		;07ff
	ld b,c			;0800
l0801h:
	jr nz,l085bh		;0801
	ld d,d			;0803
	ld b,c			;0804
	jr nz,$+81		;0805
l0807h:
	ld d,d			;0807
l0808h:
	ld b,c			;0808
	jr nz,l084eh		;0809
l080bh:
	ld c,l			;080b
l080ch:
	ld d,b			;080c
	jr nz,$+75		;080d
	ld c,(hl)		;080f
l0810h:
	ld d,d			;0810
	jr nz,l0857h		;0811
	ld b,e			;0813
	ld d,d			;0814
	jr nz,$+79		;0815
	ld d,(hl)		;0817
	ld c,c			;0818
	jr nz,l0867h		;0819
	ld e,b			;081b
	ld c,c			;081c
	jr nz,l0872h		;081d
	ld d,h			;081f
	ld b,c			;0820
	ld e,b			;0821
	ld c,c			;0822
	ld c,(hl)		;0823
	ld e,b			;0824
	jr nz,l086bh		;0825
l0827h:
	ld b,c			;0827
	ld b,h			;0828
	jr nz,l0877h		;0829
	ld b,h			;082b
	ld b,c			;082c
	ld e,b			;082d
	ld b,h			;082e
l082fh:
	ld b,e			;082f
l0830h:
	ld e,b			;0830
	jr nz,l0885h		;0831
	ld d,e			;0833
l0834h:
	ld d,h			;0834
	jr nz,l0887h		;0835
	ld d,e			;0837
	ld d,a			;0838
	jr nz,$+82		;0839
	ld c,a			;083b
	ld d,b			;083c
	jr nz,l088fh		;083d
	ld d,l			;083f
l0840h:
	ld d,e			;0840
sub_0841h:
	ld c,b			;0841
	ld c,(hl)		;0842
	ld e,d			;0843
	ld e,d			;0844
	jr nz,l0895h		;0845
	ld b,e			;0847
	ld b,e			;0848
	jr nz,l089bh		;0849
	ld c,a			;084b
	ld d,b			;084c
	ld b,l			;084d
l084eh:
	ld d,b			;084e
	jr nz,l089eh		;084f
	jr nz,l0895h		;0851
	jr nz,l0898h		;0853
	jr nz,l089bh		;0855
l0857h:
	jr nz,l089eh		;0857
	jr nz,l08a3h		;0859
l085bh:
	jr nz,$+78		;085b
	jr nz,$+79		;085d
	jr nz,l08a2h		;085f
	jr nz,$+68		;0861
	jr nz,l0885h		;0863
	jr nz,$+70		;0865
l0867h:
	jr nz,l0889h		;0867
	jr nz,l08b3h		;0869
l086bh:
	jr nz,$+34		;086b
	jr nz,$+85		;086d
	ld d,b			;086f
	jr nz,l0892h		;0870
l0872h:
	ld d,b			;0872
	ld d,e			;0873
	ld d,a			;0874
	jr nz,l08b6h		;0875
l0877h:
	ccf			;0877
	dec a			;0878
	jr nz,$+32		;0879
	ld c,l			;087b
	ld b,000h		;087c
	ld hl,0c345h		;087e
	and d			;0881
	ld b,0c3h		;0882
	xor d			;0884
l0885h:
	ld b,0c3h		;0885
l0887h:
	rst 8			;0887
	dec c			;0888
l0889h:
	jp 00bb6h		;0889
	jp 00bddh		;088c
l088fh:
	jp 00bc7h		;088f
l0892h:
	jp l0c05h		;0892
l0895h:
	jp 00c2dh		;0895
l0898h:
	jp l0c90h		;0898
l089bh:
	jp l0c66h		;089b
l089eh:
	jp l0c1fh		;089e
l08a1h:
	ret			;08a1
l08a2h:
	ex (sp),hl		;08a2
l08a3h:
	ld (00f4ah),hl		;08a3
	ex (sp),hl		;08a6
sub_08a7h:
	jp 00000h		;08a7
	ld hl,(00006h)		;08aa
	ld (l06a8h),hl		;08ad
	ld hl,006a2h		;08b0
l08b3h:
	ld (00001h),hl		;08b3
l08b6h:
	ld hl,00000h		;08b6
	ld (00006h),hl		;08b9
	xor a			;08bc
	ld (00f4fh),a		;08bd
	ld hl,l0100h		;08c0
	ld (0000ch),hl		;08c3
	ld (l0f5dh),hl		;08c6
	ld (l0f87h),hl		;08c9
	ld (l0fb9h),hl		;08cc
	ld hl,l0100h		;08cf
	ld sp,l0fb7h		;08d2
	push hl			;08d5
	ld hl,00002h		;08d6
	push hl			;08d9
	dec hl			;08da
	dec hl			;08db
	ld (l0fb7h),hl		;08dc
l08dfh:
	push hl			;08df
	push hl			;08e0
	ld (l0f4dh),hl		;08e1
	ld a,0c3h		;08e4
	ld (00038h),a		;08e6
	ld hl,l0686h		;08e9
	ld (00039h),hl		;08ec
	ld a,(0005dh)		;08ef
	cp 020h			;08f2
l08f4h:
	jp z,l06feh		;08f4
l08f7h:
	ld hl,00000h		;08f7
l08fah:
	push hl			;08fa
	jp l09ach+1		;08fb
	ld sp,0c3afh		;08fe
	ld c,e			;0901
	ld bc,l0d00h		;0902
	ld b,h			;0905
l0906h:
	ld b,e			;0906
	ld c,(hl)		;0907
	jr nz,$+120		;0908
	ld h,l			;090a
	ld (hl),d		;090b
l090ch:
	ld (hl),e		;090c
	ld l,c			;090d
	ld l,a			;090e
l090fh:
	ld l,(hl)		;090f
	jr nz,l0944h		;0910
l0912h:
	ld l,030h		;0912
	scf			;0914
l0915h:
	ld a,(bc)		;0915
	dec c			;0916
	ld b,e			;0917
sub_0918h:
	ld l,a			;0918
	ld (hl),b		;0919
	ld a,c			;091a
l091bh:
	ld (hl),d		;091b
	ld l,c			;091c
	ld h,a			;091d
	ld l,b			;091e
	ld (hl),h		;091f
	jr nz,l094ah		;0920
	ld h,e			;0922
	add hl,hl		;0923
	jr nz,$+51		;0924
l0926h:
	add hl,sp		;0926
	jr c,$+54		;0927
	jr nz,l096fh		;0929
	ld (hl),d		;092b
	ld l,c			;092c
	halt			;092d
	ld h,l			;092e
	jr nz,$+69		;092f
	ld a,(l0a2ch)		;0931
	dec c			;0934
	ld b,c			;0935
	ld l,h			;0936
	ld l,h			;0937
	jr nz,l09ach		;0938
l093ah:
	ld l,c			;093a
	ld h,a			;093b
	ld l,b			;093c
	ld (hl),h		;093d
	ld (hl),e		;093e
	jr nz,l09b3h		;093f
	ld h,l			;0941
	ld (hl),e		;0942
	ld h,l			;0943
l0944h:
	ld (hl),d		;0944
	halt			;0945
	ld h,l			;0946
	ld h,h			;0947
	dec c			;0948
	ld a,(bc)		;0949
l094ah:
	ld a,(de)		;094a
l094bh:
	ld h,0e0h		;094b
l094dh:
	ld l,011h		;094d
	ld a,(hl)		;094f
	cp 054h			;0950
	jr nz,l0960h		;0952
	inc hl			;0954
l0955h:
	ld a,(hl)		;0955
	cp 04ah			;0956
	jr nz,l0960h		;0958
	inc hl			;095a
	ld a,(hl)		;095b
	cp 048h			;095c
	jr z,l0970h		;095e
l0960h:
	ld a,(00007h)		;0960
	cp h			;0963
	dec h			;0964
	jr c,l094dh		;0965
	ld de,l01fbh		;0967
l096ah:
	ld c,009h		;096a
	call 00005h		;096c
l096fh:
	ret			;096f
l0970h:
	push hl			;0970
	ld c,019h		;0971
	call 00005h		;0973
	ld c,a			;0976
	pop hl			;0977
	ld l,000h		;0978
	ld de,00016h		;097a
	add hl,de		;097d
	ld a,(hl)		;097e
	call l01c3h		;097f
	ld (l0103h),a		;0982
	ld a,(0005ch)		;0985
	or a			;0988
	jr nz,l099bh		;0989
sub_098bh:
	ld a,(0005dh)		;098b
	cp 020h			;098e
	jr z,l09c0h		;0990
	sub 041h		;0992
	jr nc,l099ch		;0994
l0996h:
	ld de,l01dfh		;0996
l0999h:
	jr l096ah		;0999
l099bh:
	dec a			;099b
l099ch:
	cp 003h			;099c
	jr nc,l0996h		;099e
	ld b,a			;09a0
	ld de,00016h		;09a1
	ld l,000h		;09a4
	add hl,de		;09a6
	ld (hl),a		;09a7
	cp 002h			;09a8
	jr nc,l09b5h		;09aa
l09ach:
	ld a,002h		;09ac
	ld l,000h		;09ae
	ld de,0003eh		;09b0
l09b3h:
	add hl,de		;09b3
	ld (hl),a		;09b4
l09b5h:
	ld a,(l0103h)		;09b5
	ld c,a			;09b8
	ld a,b			;09b9
	call l01c3h		;09ba
	ld (00004h),a		;09bd
l09c0h:
	jp 00000h		;09c0
	push hl			;09c3
	sla a			;09c4
	sla a			;09c6
	add a,c			;09c8
	ld hl,l01d3h		;09c9
	ld e,a			;09cc
	ld d,000h		;09cd
	add hl,de		;09cf
	ld a,(hl)		;09d0
	pop hl			;09d1
	ret			;09d2
l09d3h:
	ld (bc),a		;09d3
	ld bc,00000h		;09d4
	nop			;09d7
	ld (bc),a		;09d8
	ld bc,00000h		;09d9
	ld bc,00002h		;09dc
	ld c,c			;09df
	ld l,(hl)		;09e0
l09e1h:
	halt			;09e1
	ld h,c			;09e2
	ld l,h			;09e3
	ld l,c			;09e4
	ld h,h			;09e5
	jr nz,l0a2ch		;09e6
	ld (hl),d		;09e8
	ld l,c			;09e9
l09eah:
	halt			;09ea
	ld h,l			;09eb
	jr nz,$+85		;09ec
	ld (hl),b		;09ee
	ld h,l			;09ef
	ld h,e			;09f0
	ld l,c			;09f1
	ld h,(hl)		;09f2
	ld l,c			;09f3
	ld h,e			;09f4
	ld h,c			;09f5
	ld (hl),h		;09f6
	ld l,c			;09f7
	ld l,a			;09f8
	ld l,(hl)		;09f9
	inc h			;09fa
	ld b,h			;09fb
	ld (hl),d		;09fc
	ld l,c			;09fd
	halt			;09fe
	ld h,l			;09ff
	jr nz,$+69		;0a00
	ld a,(04e20h)		;0a02
	ld c,a			;0a05
l0a06h:
	ld d,h			;0a06
	jr nz,l0a52h		;0a07
	ld c,(hl)		;0a09
	ld d,e			;0a0a
	ld d,h			;0a0b
l0a0ch:
	ld b,c			;0a0c
	ld c,h			;0a0d
	ld c,h			;0a0e
l0a0fh:
	ld b,l			;0a0f
	ld b,h			;0a10
	jr nz,l0a6ch		;0a11
	ld b,l			;0a13
	ld d,h			;0a14
	inc h			;0a15
l0a16h:
	ld de,l01dfh		;0a16
	jr l09eah		;0a19
	dec a			;0a1b
	cp 003h			;0a1c
	jr nc,l0a16h		;0a1e
	ld b,a			;0a20
	ld de,00016h		;0a21
	ld l,000h		;0a24
sub_0a26h:
	add hl,de		;0a26
	ld (hl),a		;0a27
	cp 002h			;0a28
	jr nc,l0a35h		;0a2a
l0a2ch:
	ld a,002h		;0a2c
	ld l,000h		;0a2e
	ld de,0003eh		;0a30
	add hl,de		;0a33
	ld (hl),a		;0a34
l0a35h:
	ld a,(l0103h)		;0a35
	ld c,a			;0a38
	ld a,b			;0a39
	call l01c3h		;0a3a
	ld (00004h),a		;0a3d
	jp 00000h		;0a40
	push hl			;0a43
	sla a			;0a44
l0a46h:
	sla a			;0a46
	add a,c			;0a48
	ld hl,l01d3h		;0a49
	ld e,a			;0a4c
	ld d,000h		;0a4d
	add hl,de		;0a4f
	ld a,(hl)		;0a50
	pop hl			;0a51
l0a52h:
	ret			;0a52
	ld (bc),a		;0a53
	ld bc,00000h		;0a54
	nop			;0a57
	ld (bc),a		;0a58
	ld bc,00000h		;0a59
	ld bc,00002h		;0a5c
	ld c,c			;0a5f
	ld l,(hl)		;0a60
	halt			;0a61
	ld h,c			;0a62
	ld l,h			;0a63
	ld l,c			;0a64
	ld h,h			;0a65
	jr nz,l0aach		;0a66
	ld (hl),d		;0a68
	ld l,c			;0a69
	halt			;0a6a
	ld h,l			;0a6b
l0a6ch:
	jr nz,l0ac1h		;0a6c
	ld (hl),b		;0a6e
l0a6fh:
	ld h,l			;0a6f
	ld h,e			;0a70
	ld l,c			;0a71
	ld h,(hl)		;0a72
	ld l,c			;0a73
	ld h,e			;0a74
	ld h,c			;0a75
	ld (hl),h		;0a76
	ld l,c			;0a77
	ld l,a			;0a78
	ld l,(hl)		;0a79
	inc h			;0a7a
	ld b,h			;0a7b
	ld (hl),d		;0a7c
	ld l,c			;0a7d
	halt			;0a7e
	ld h,l			;0a7f
	inc c			;0a80
	ld b,h			;0a81
	ld c,l			;0a82
	pop de			;0a83
l0a84h:
	pop hl			;0a84
	di			;0a85
	jp z,l08a1h		;0a86
	jp c,l088fh		;0a89
	ld (l0fb9h),hl		;0a8c
	and 07fh		;0a8f
	dec a			;0a91
	jp z,l08a1h		;0a92
	call 008b2h		;0a95
	dec a			;0a98
	jp z,l08a1h		;0a99
	ld e,c			;0a9c
	ld d,b			;0a9d
	call 008b2h		;0a9e
	ld sp,l0fafh		;0aa1
	pop de			;0aa4
	pop bc			;0aa5
	pop af			;0aa6
	pop hl			;0aa7
	ld sp,hl		;0aa8
	ld hl,(l0fb9h)		;0aa9
l0aach:
	push hl			;0aac
	ld hl,(l0fb7h)		;0aad
	ei			;0ab0
	ret			;0ab1
	push af			;0ab2
	push bc			;0ab3
	ld hl,00f4fh		;0ab4
	ld a,(hl)		;0ab7
	inc (hl)		;0ab8
	or a			;0ab9
	jp z,008cdh		;0aba
	inc hl			;0abd
	ld a,(hl)		;0abe
	inc hl			;0abf
	ld b,(hl)		;0ac0
l0ac1h:
	inc hl			;0ac1
	cp e			;0ac2
	jp nz,008cdh		;0ac3
	ld a,b			;0ac6
	cp d			;0ac7
	jp nz,008cdh		;0ac8
	ld a,(hl)		;0acb
	ld (de),a		;0acc
	inc hl			;0acd
	ld (hl),e		;0ace
	inc hl			;0acf
	ld (hl),d		;0ad0
	inc hl			;0ad1
	ld a,(de)		;0ad2
	ld (hl),a		;0ad3
	ld a,0ffh		;0ad4
	ld (de),a		;0ad6
	pop bc			;0ad7
	pop af			;0ad8
	ret			;0ad9
	call l0c90h		;0ada
	cp 002h			;0add
	jp nz,00babh		;0adf
	call l0c66h		;0ae2
	push hl			;0ae5
	call l0c66h		;0ae6
	pop de			;0ae9
	push hl			;0aea
	call sub_0c15h		;0aeb
	add hl,de		;0aee
	call 00c2eh		;0aef
	call 00bc5h		;0af2
l0af5h:
	pop hl			;0af5
	xor a			;0af6
	sub l			;0af7
	ld l,a			;0af8
	ld a,000h		;0af9
l0afbh:
	sbc a,h			;0afb
	ld h,a			;0afc
	add hl,de		;0afd
	call 00c2eh		;0afe
	jp l06feh		;0b01
	xor a			;0b04
	ld (0007ch),a		;0b05
l0b08h:
	ld (0005ch),a		;0b08
	call 00bddh		;0b0b
	ld c,009h		;0b0e
	ld hl,0005dh		;0b10
	ld (hl),a		;0b13
	inc hl			;0b14
	dec c			;0b15
	jp z,00babh		;0b16
	call 00bddh		;0b19
	cp 02eh			;0b1c
	jp z,l0926h		;0b1e
	cp 00dh			;0b21
	jp nz,l0912h+1		;0b23
	dec c			;0b26
	jp z,00930h		;0b27
	ld (hl),020h		;0b2a
	inc hl			;0b2c
	jp l0926h		;0b2d
	ld c,004h		;0b30
	cp 02eh			;0b32
	jp nz,l094bh		;0b34
	ld hl,00065h		;0b37
	call 00bddh		;0b3a
	cp 00dh			;0b3d
	jp z,l094bh		;0b3f
	ld (hl),a		;0b42
	inc hl			;0b43
	dec c			;0b44
	jp z,00babh		;0b45
	jp l093ah		;0b48
	dec c			;0b4b
	jp z,l0955h		;0b4c
	ld (hl),020h		;0b4f
	inc hl			;0b51
	jp l094bh		;0b52
	ld (hl),000h		;0b55
	jp l06feh		;0b57
	call sub_0841h		;0b5a
	call l0857h		;0b5d
	jp c,l06feh		;0b60
	ld a,(bc)		;0b63
	inc bc			;0b64
	ld (hl),a		;0b65
	inc hl			;0b66
	jp 0095dh		;0b67
	ld hl,00065h		;0b6a
	ld a,(hl)		;0b6d
	and 07fh		;0b6e
	cp 048h			;0b70
	ret nz			;0b72
	inc hl			;0b73
sub_0b74h:
	ld a,(hl)		;0b74
	and 07fh		;0b75
	cp 045h			;0b77
	ret nz			;0b79
	inc hl			;0b7a
	ld a,(hl)		;0b7b
	and 07fh		;0b7c
	cp 058h			;0b7e
	ret			;0b80
	ex de,hl		;0b81
	ld hl,(l0f87h)		;0b82
	ld a,l			;0b85
	sub e			;0b86
	ld a,h			;0b87
	sbc a,d			;0b88
	ex de,hl		;0b89
	ret			;0b8a
	call 00981h		;0b8b
	ret nc			;0b8e
	ld (l0f87h),hl		;0b8f
	ret			;0b92
	push hl			;0b93
l0b94h:
	ld hl,00000h		;0b94
	call 00981h		;0b97
	pop hl			;0b9a
	ret			;0b9b
	call l0c90h		;0b9c
	ld hl,00000h		;0b9f
	jp z,l09ach		;0ba2
	dec a			;0ba5
l0ba6h:
	jp nz,00babh		;0ba6
	call l0c66h		;0ba9
	push hl			;0bac
	call sub_076bh		;0bad
	cp 0ffh			;0bb0
	jp z,00babh		;0bb2
	call l096ah		;0bb5
	jp z,l09e1h		;0bb8
	pop hl			;0bbb
	ld de,l0100h		;0bbc
	add hl,de		;0bbf
	push hl			;0bc0
	ld de,0005ch		;0bc1
	ld c,014h		;0bc4
	call 006a2h		;0bc6
	pop hl			;0bc9
	or a			;0bca
	jp nz,l0a46h		;0bcb
	ld de,00080h		;0bce
	ld c,080h		;0bd1
	ld a,(de)		;0bd3
sub_0bd4h:
	inc de			;0bd4
	ld (hl),a		;0bd5
	inc hl			;0bd6
	dec c			;0bd7
	jp nz,l09d3h		;0bd8
	call sub_098bh		;0bdb
	jp l09c0h		;0bde
	call sub_0b74h		;0be1
	cp 01ah			;0be4
	jp z,00babh		;0be6
	sbc a,03ah		;0be9
	jp nz,l09e1h		;0beb
	ld d,a			;0bee
	pop hl			;0bef
	push hl			;0bf0
	call sub_0a26h		;0bf1
l0bf4h:
	ld e,a			;0bf4
	call sub_0a26h		;0bf5
	push af			;0bf8
	call sub_0a26h		;0bf9
	pop bc			;0bfc
	ld c,a			;0bfd
	add hl,bc		;0bfe
	ld a,e			;0bff
l0c00h:
	or a			;0c00
	jp nz,l0a0ch		;0c01
	ld h,b			;0c04
l0c05h:
	ld l,c			;0c05
	ld (l0fb9h),hl		;0c06
	jp l0a46h		;0c09
	call sub_0a26h		;0c0c
	call sub_0a26h		;0c0f
	ld (hl),a		;0c12
	inc hl			;0c13
	dec e			;0c14
sub_0c15h:
	jp nz,l0a0fh		;0c15
	call sub_0a26h		;0c18
	push af			;0c1b
	call sub_098bh		;0c1c
l0c1fh:
	pop af			;0c1f
	jp nz,00babh		;0c20
	jp l09e1h		;0c23
	push bc			;0c26
	push hl			;0c27
	push de			;0c28
	call sub_0b74h		;0c29
	call 00c59h		;0c2c
	rlca			;0c2f
	rlca			;0c30
	rlca			;0c31
	rlca			;0c32
	and 0f0h		;0c33
	push af			;0c35
	call sub_0b74h		;0c36
	call 00c59h		;0c39
	pop bc			;0c3c
	or b			;0c3d
	ld b,a			;0c3e
	pop de			;0c3f
l0c40h:
	add a,d			;0c40
	ld d,a			;0c41
	ld a,b			;0c42
	pop hl			;0c43
	pop bc			;0c44
sub_0c45h:
	ret			;0c45
	ld c,00ch		;0c46
	call 006a2h		;0c48
	ld hl,l0a6fh		;0c4b
	ld a,(hl)		;0c4e
	or a			;0c4f
sub_0c50h:
	jp z,00a5ah		;0c50
	call 00bc7h		;0c53
	inc hl			;0c56
	jp 00a4eh		;0c57
	call sub_0c15h		;0c5a
	ld hl,(l0f87h)		;0c5d
	call 00c2eh		;0c60
	call 00bc5h		;0c63
l0c66h:
	ld hl,(l0fb9h)		;0c66
	call 00c2eh		;0c69
	jp l06feh		;0c6c
	dec c			;0c6f
	ld a,(bc)		;0c70
l0c71h:
	ld c,(hl)		;0c71
	ld b,l			;0c72
	ld e,b			;0c73
	ld d,h			;0c74
	jr nz,l0c97h		;0c75
	ld d,b			;0c77
	ld b,e			;0c78
	nop			;0c79
	call l0c90h		;0c7a
	dec a			;0c7d
	jp nz,00babh		;0c7e
	call l0c66h		;0c81
	call sub_0c15h		;0c84
	push hl			;0c87
	call 00c2eh		;0c88
	call 00bc5h		;0c8b
	pop hl			;0c8e
	ld a,(hl)		;0c8f
l0c90h:
	push hl			;0c90
	call l0c05h		;0c91
	call 00bc5h		;0c94
l0c97h:
	call 00bb6h		;0c97
	call 00bddh		;0c9a
	pop hl			;0c9d
	cp 00dh			;0c9e
	jp z,00abbh		;0ca0
	cp 02eh			;0ca3
	jp z,l06feh		;0ca5
	push hl			;0ca8
	call 00c93h		;0ca9
	dec a			;0cac
	jp nz,00babh		;0cad
	call l0c66h		;0cb0
	ld a,h			;0cb3
	or a			;0cb4
	jp nz,00babh		;0cb5
	ld a,l			;0cb8
	pop hl			;0cb9
	ld (hl),a		;0cba
	inc hl			;0cbb
	jp l0a84h		;0cbc
	xor a			;0cbf
	jp 00ac5h		;0cc0
	ld a,0ffh		;0cc3
	ld (l0f4ch),a		;0cc5
	call l0c90h		;0cc8
	ld hl,00000h		;0ccb
	jp z,00adeh		;0cce
	dec a			;0cd1
	jp nz,00babh		;0cd2
l0cd5h:
	call l0c66h		;0cd5
	ld a,l			;0cd8
	or h			;0cd9
	jp z,00babh		;0cda
	dec hl			;0cdd
	ld (l0f4dh),hl		;0cde
	call sub_0d44h		;0ce1
	jp l0885h		;0ce4
	call 00bddh		;0ce7
	cp 00dh			;0cea
	jp nz,l0af5h		;0cec
	call sub_0d44h		;0cef
	jp l06feh		;0cf2
	ld bc,0000bh		;0cf5
	ld hl,l0db3h		;0cf8
	cp (hl)			;0cfb
	jp z,l0b08h		;0cfc
	inc hl			;0cff
l0d00h:
	inc b			;0d00
sub_0d01h:
	dec c			;0d01
	jp nz,l0afbh		;0d02
	jp 00babh		;0d05
	call 00bddh		;0d08
	cp 00dh			;0d0b
	jp nz,00babh		;0d0d
	push bc			;0d10
	call sub_0c15h		;0d11
	call sub_0d1ah		;0d14
	call 00bc5h		;0d17
sub_0d1ah:
	call 00bb6h		;0d1a
	call l0c90h		;0d1d
	or a			;0d20
	jp z,l06feh		;0d21
	dec a			;0d24
	jp nz,00babh		;0d25
	call l0c66h		;0d28
l0d2bh:
	pop bc			;0d2b
	ld a,b			;0d2c
	cp 005h			;0d2d
	jp nc,00b59h		;0d2f
	ld a,h			;0d32
	or a			;0d33
	jp nz,00babh		;0d34
	ld a,l			;0d37
	cp 002h			;0d38
	jp nc,00babh		;0d3a
l0d3dh:
	call 00ce3h		;0d3d
	ld h,a			;0d40
	ld b,c			;0d41
	ld a,0feh		;0d42
sub_0d44h:
	call 00b53h		;0d44
	and h			;0d47
	ld b,c			;0d48
	ld h,a			;0d49
	ld a,l			;0d4a
	call 00b53h		;0d4b
	or h			;0d4e
	ld (de),a		;0d4f
	jp l06feh		;0d50
	dec b			;0d53
	ret z			;0d54
	rlca			;0d55
	jp 00b53h		;0d56
	jp nz,00b69h		;0d59
	ld a,h			;0d5c
	or a			;0d5d
	jp nz,00babh		;0d5e
	ld a,l			;0d61
	ld hl,l0fb4h		;0d62
	ld (hl),a		;0d65
l0d66h:
	jp l06feh		;0d66
	push hl			;0d69
	call sub_0d01h		;0d6a
	pop de			;0d6d
	ld (hl),e		;0d6e
	inc hl			;0d6f
	ld (hl),d		;0d70
	jp l06feh		;0d71
	push hl			;0d74
	push de			;0d75
	push bc			;0d76
	ld a,(0005bh)		;0d77
	and 07fh		;0d7a
	jp z,l0b94h		;0d7c
	ld d,000h		;0d7f
	ld e,a			;0d81
	ld hl,00080h		;0d82
	add hl,de		;0d85
l0d86h:
	ld a,(hl)		;0d86
	cp 01ah			;0d87
	jp z,l0ba6h		;0d89
	ld hl,0005bh		;0d8c
	inc (hl)		;0d8f
	or a			;0d90
	jp l0ba6h+1		;0d91
	ld c,014h		;0d94
	ld de,0005ch		;0d96
	call 006a2h		;0d99
	or a			;0d9c
	jp nz,l0ba6h		;0d9d
	ld (0005bh),a		;0da0
	jp 00b7fh		;0da3
	scf			;0da6
	pop bc			;0da7
	pop de			;0da8
	pop hl			;0da9
	ret			;0daa
l0dabh:
	call sub_0c15h		;0dab
	ld a,03fh		;0dae
	call 00bc7h		;0db0
l0db3h:
	jp l06feh		;0db3
	ld c,00ah		;0db6
	ld de,l0f63h+2		;0db8
	call 006a2h		;0dbb
l0dbeh:
	ld hl,l0f66h+1		;0dbe
	ld (l0f63h),hl		;0dc1
	ret			;0dc4
	ld a,020h		;0dc5
	push hl			;0dc7
	push de			;0dc8
	push bc			;0dc9
	ld e,a			;0dca
	ld c,002h		;0dcb
	call 006a2h		;0dcd
	pop bc			;0dd0
	pop de			;0dd1
	pop hl			;0dd2
	ret			;0dd3
	cp 07fh			;0dd4
	ret z			;0dd6
	cp 061h			;0dd7
	ret c			;0dd9
	and 05fh		;0dda
	ret			;0ddc
	push hl			;0ddd
	ld hl,l0f66h		;0dde
	ld a,(hl)		;0de1
	or a			;0de2
	ld a,00dh		;0de3
	jp z,l0bf4h		;0de5
	dec (hl)		;0de8
	ld hl,(l0f63h)		;0de9
	ld a,(hl)		;0dec
	inc hl			;0ded
	ld (l0f63h),hl		;0dee
	call sub_0bd4h		;0df1
	pop hl			;0df4
	ret			;0df5
	cp 00ah			;0df6
	jp nc,l0c00h		;0df8
	add a,030h		;0dfb
	jp 00bc7h		;0dfd
	add a,037h		;0e00
	jp 00bc7h		;0e02
	push af			;0e05
	rra			;0e06
	rra			;0e07
	rra			;0e08
	rra			;0e09
	and 00fh		;0e0a
	call 00bf6h		;0e0c
	pop af			;0e0f
	and 00fh		;0e10
	jp 00bf6h		;0e12
	ld a,00dh		;0e15
	call 00bc7h		;0e17
	ld a,00ah		;0e1a
	jp 00bc7h		;0e1c
	push bc			;0e1f
	push de			;0e20
	push hl			;0e21
	ld c,00bh		;0e22
	call 006a2h		;0e24
	and 001h		;0e27
	pop hl			;0e29
	pop de			;0e2a
	pop bc			;0e2b
	ret			;0e2c
	ex de,hl		;0e2d
	ld a,h			;0e2e
	call l0c05h		;0e2f
	ld a,l			;0e32
	jp l0c05h		;0e33
	cp 07fh			;0e36
	jp nc,l0c40h		;0e38
	cp 020h			;0e3b
	jp nc,00bc7h		;0e3d
	ld a,02eh		;0e40
	jp 00bc7h		;0e42
	ex de,hl		;0e45
	ld hl,(l0f5dh+2)	;0e46
	ld a,l			;0e49
	sub e			;0e4a
	ld l,a			;0e4b
	ld a,h			;0e4c
	sbc a,d			;0e4d
	ex de,hl		;0e4e
	ret			;0e4f
	cp 00dh			;0e50
	ret z			;0e52
	cp 02ch			;0e53
	ret z			;0e55
	cp 020h			;0e56
	ret			;0e58
	sub 030h		;0e59
	cp 00ah			;0e5b
	ret c			;0e5d
	add a,0f9h		;0e5e
	cp 010h			;0e60
	ret c			;0e62
	jp 00babh		;0e63
	ex de,hl		;0e66
	ld e,(hl)		;0e67
	inc hl			;0e68
	ld d,(hl)		;0e69
	inc hl			;0e6a
	ex de,hl		;0e6b
	ret			;0e6c
	ex de,hl		;0e6d
	ld hl,00000h		;0e6e
	call 00c59h		;0e71
	add hl,hl		;0e74
	add hl,hl		;0e75
	add hl,hl		;0e76
	add hl,hl		;0e77
	or l			;0e78
	ld l,a			;0e79
	call 00bddh		;0e7a
	call sub_0c50h		;0e7d
	jp nz,l0c71h		;0e80
	ex de,hl		;0e83
	ret			;0e84
sub_0e85h:
	ld (hl),e		;0e85
	inc hl			;0e86
	ld (hl),d		;0e87
	inc hl			;0e88
	push hl			;0e89
	ld hl,l0f56h		;0e8a
	inc (hl)		;0e8d
	pop hl			;0e8e
	ret			;0e8f
	call 00bddh		;0e90
	ld hl,l0f56h		;0e93
	ld (hl),000h		;0e96
	inc hl			;0e98
	cp 00dh			;0e99
	jp z,l0cd5h		;0e9b
	cp 02ch			;0e9e
	jp nz,00caeh		;0ea0
	ld a,080h		;0ea3
	ld (l0f56h),a		;0ea5
	ld de,00000h		;0ea8
	jp 00cb1h		;0eab
	call 00c6dh		;0eae
	call 00c85h		;0eb1
	cp 00dh			;0eb4
	jp z,l0cd5h		;0eb6
	call 00bddh		;0eb9
	call 00c6dh		;0ebc
	call 00c85h		;0ebf
	cp 00dh			;0ec2
	jp z,l0cd5h		;0ec4
	call 00bddh		;0ec7
	call 00c6dh		;0eca
	call 00c85h		;0ecd
	cp 00dh			;0ed0
	jp nz,00babh		;0ed2
	ld de,l0f56h		;0ed5
	ld a,(de)		;0ed8
	cp 081h			;0ed9
	jp z,00babh		;0edb
	inc de			;0ede
	or a			;0edf
	rlca			;0ee0
	rrca			;0ee1
	ret			;0ee2
	push hl			;0ee3
	ld hl,00dc3h		;0ee4
	ld e,b			;0ee7
	ld d,000h		;0ee8
	add hl,de		;0eea
	ld c,(hl)		;0eeb
	ld hl,l0fb3h		;0eec
	ld a,(hl)		;0eef
	ex de,hl		;0ef0
	pop hl			;0ef1
	ret			;0ef2
	call 00ce3h		;0ef3
	dec c			;0ef6
	jp z,00cfeh		;0ef7
	rra			;0efa
	jp 00cf6h		;0efb
	and 001h		;0efe
	ret			;0f00
	sub 006h		;0f01
	ld hl,l0dbeh		;0f03
	ld e,a			;0f06
	ld d,000h		;0f07
	add hl,de		;0f09
	ld e,(hl)		;0f0a
	ld d,0ffh		;0f0b
	ld hl,l0fbbh		;0f0d
	add hl,de		;0f10
	ret			;0f11
	call sub_0d01h		;0f12
	ld e,(hl)		;0f15
	inc hl			;0f16
	ld d,(hl)		;0f17
	ex de,hl		;0f18
	ret			;0f19
	ld a,(hl)		;0f1a
	call 00bc7h		;0f1b
	ld a,b			;0f1e
	cp 005h			;0f1f
	jp nc,l0d2bh		;0f21
	call 00cf3h		;0f24
	call 00bf6h		;0f27
	ret			;0f2a
	push af			;0f2b
	ld a,03dh		;0f2c
	call 00bc7h		;0f2e
	pop af			;0f31
	jp nz,l0d3dh		;0f32
	ld hl,l0fb4h		;0f35
	ld a,(hl)		;0f38
	call l0c05h		;0f39
	ret			;0f3c
	call 00d12h		;0f3d
	call 00c2eh		;0f40
	ret			;0f43
	ld hl,l0db3h		;0f44
	ld b,000h		;0f47
	call sub_0c15h		;0f49
l0f4ch:
	push bc			;0f4c
l0f4dh:
	push hl			;0f4d
	call sub_0d1ah		;0f4e
	pop hl			;0f51
	pop bc			;0f52
	inc b			;0f53
	inc hl			;0f54
	ld a,b			;0f55
l0f56h:
	cp 00bh			;0f56
	jp nc,l0d66h		;0f58
	cp 005h			;0f5b
l0f5dh:
	jp c,00d4ch		;0f5d
	call 00bc5h		;0f60
l0f63h:
	jp 00d4ch		;0f63
l0f66h:
	call 00bc5h		;0f66
	call sub_0e85h		;0f69
	push af			;0f6c
	push de			;0f6d
	push bc			;0f6e
	call 00993h		;0f6f
	jp nc,l0d86h		;0f72
	ld hl,(l0fb9h)		;0f75
	ld (0000ch),hl		;0f78
	ld hl,00010h		;0f7b
	ld (hl),0ffh		;0f7e
	call 00006h		;0f80
	jp 00dafh		;0f83
	dec hl			;0f86
l0f87h:
	ld (l0f5dh+2),hl	;0f87
	ld hl,(l0fb9h)		;0f8a
	ld a,(hl)		;0f8d
	call l0c05h		;0f8e
	inc hl			;0f91
	call sub_0c45h		;0f92
	jp c,00dafh		;0f95
	push af			;0f98
	call 00bc5h		;0f99
	pop af			;0f9c
	or e			;0f9d
	jp z,l0dabh		;0f9e
	ld e,(hl)		;0fa1
	inc hl			;0fa2
	ld d,(hl)		;0fa3
	ex de,hl		;0fa4
	call 00c2eh		;0fa5
	jp 00dafh		;0fa8
	ld a,(hl)		;0fab
	call l0c05h		;0fac
l0fafh:
	pop bc			;0faf
	pop de			;0fb0
	pop af			;0fb1
	ret			;0fb2
l0fb3h:
	ld b,e			;0fb3
l0fb4h:
	ld e,d			;0fb4
	ld c,l			;0fb5
	ld b,l			;0fb6
l0fb7h:
	ld c,c			;0fb7
	ld b,c			;0fb8
l0fb9h:
	ld b,d			;0fb9
	ld b,h			;0fba
l0fbbh:
	ld c,b			;0fbb
	ld d,e			;0fbc
	ld d,b			;0fbd
	or 0f4h			;0fbe
	call m,0fefah		;0fc0
	ld bc,l0807h		;0fc3
	inc bc			;0fc6
	dec b			;0fc7
	ld hl,00000h		;0fc8
	ld (l0f4dh),hl		;0fcb
	ret			;0fce
	di			;0fcf
	ld (l0fb7h),hl		;0fd0
	pop hl			;0fd3
	dec hl			;0fd4
	ld (l0fb9h),hl		;0fd5
	push af			;0fd8
	ld hl,00002h		;0fd9
	add hl,sp		;0fdc
	pop af			;0fdd
	ld sp,l0fb7h		;0fde
	push hl			;0fe1
	push af			;0fe2
	push bc			;0fe3
	push de			;0fe4
	ld hl,(l0fb9h)		;0fe5
	ld a,(hl)		;0fe8
	cp 0ffh			;0fe9
	push af			;0feb
	push hl			;0fec
	ld hl,00f4fh		;0fed
	ld a,(hl)		;0ff0
	ld (hl),000h		;0ff1
	or a			;0ff3
	jp z,00e04h		;0ff4
	dec a			;0ff7
	ld b,a			;0ff8
	inc hl			;0ff9
	ld e,(hl)		;0ffa
	inc hl			;0ffb
	ld d,(hl)		;0ffc
	inc hl			;0ffd
	ld a,(hl)		;0ffe
	ld (de),a		;0fff
	nop			;1000
l1001h:
	sbc a,e			;1001
	ex af,af'		;1002
	nop			;1003
	nop			;1004
	nop			;1005
	nop			;1006
	nop			;1007
	nop			;1008
	nop			;1009
	nop			;100a
	nop			;100b
	nop			;100c
	nop			;100d
	nop			;100e
	nop			;100f
	nop			;1010
	nop			;1011
	nop			;1012
	nop			;1013
	nop			;1014
	nop			;1015
	nop			;1016
	nop			;1017
	nop			;1018
	nop			;1019
	nop			;101a
	nop			;101b
	nop			;101c
	nop			;101d
	nop			;101e
	nop			;101f
	nop			;1020
	nop			;1021
	nop			;1022
	nop			;1023
	nop			;1024
	nop			;1025
	nop			;1026
	nop			;1027
	nop			;1028
	nop			;1029
	nop			;102a
	nop			;102b
	nop			;102c
	nop			;102d
	nop			;102e
	nop			;102f
	nop			;1030
	nop			;1031
	nop			;1032
	nop			;1033
	nop			;1034
	nop			;1035
	nop			;1036
	nop			;1037
	nop			;1038
	nop			;1039
	nop			;103a
	nop			;103b
	nop			;103c
	nop			;103d
	nop			;103e
	nop			;103f
	nop			;1040
	nop			;1041
	nop			;1042
	nop			;1043
	nop			;1044
	nop			;1045
	nop			;1046
	nop			;1047
	nop			;1048
	nop			;1049
	nop			;104a
	nop			;104b
	nop			;104c
	nop			;104d
	nop			;104e
	nop			;104f
	nop			;1050
	nop			;1051
	nop			;1052
	nop			;1053
	nop			;1054
	nop			;1055
	nop			;1056
	nop			;1057
	nop			;1058
	nop			;1059
	nop			;105a
	nop			;105b
	nop			;105c
	nop			;105d
	nop			;105e
	nop			;105f
	nop			;1060
	nop			;1061
	nop			;1062
	nop			;1063
	nop			;1064
	nop			;1065
	nop			;1066
	nop			;1067
	nop			;1068
	nop			;1069
	nop			;106a
	nop			;106b
	nop			;106c
	nop			;106d
	nop			;106e
	nop			;106f
	nop			;1070
	nop			;1071
	nop			;1072
	nop			;1073
	nop			;1074
	nop			;1075
	nop			;1076
	nop			;1077
	nop			;1078
	nop			;1079
	nop			;107a
	nop			;107b
	nop			;107c
	nop			;107d
	nop			;107e
	nop			;107f
	nop			;1080
	nop			;1081
	nop			;1082
	nop			;1083
	nop			;1084
	nop			;1085
	nop			;1086
	nop			;1087
	nop			;1088
	nop			;1089
	nop			;108a
	nop			;108b
	nop			;108c
	nop			;108d
	nop			;108e
	nop			;108f
	nop			;1090
	nop			;1091
	nop			;1092
	nop			;1093
	nop			;1094
	nop			;1095
	nop			;1096
	nop			;1097
	nop			;1098
	nop			;1099
	nop			;109a
	nop			;109b
	nop			;109c
	nop			;109d
	nop			;109e
	nop			;109f
	nop			;10a0
	nop			;10a1
	nop			;10a2
	nop			;10a3
	nop			;10a4
	nop			;10a5
	nop			;10a6
	nop			;10a7
	nop			;10a8
	nop			;10a9
	nop			;10aa
	nop			;10ab
	nop			;10ac
	nop			;10ad
	nop			;10ae
	nop			;10af
	nop			;10b0
	nop			;10b1
	nop			;10b2
	nop			;10b3
	nop			;10b4
	nop			;10b5
	nop			;10b6
	nop			;10b7
	nop			;10b8
	nop			;10b9
	nop			;10ba
	nop			;10bb
	nop			;10bc
	nop			;10bd
	nop			;10be
	nop			;10bf
	nop			;10c0
	nop			;10c1
	nop			;10c2
	nop			;10c3
	nop			;10c4
	nop			;10c5
	nop			;10c6
	nop			;10c7
	nop			;10c8
	nop			;10c9
	nop			;10ca
	nop			;10cb
	nop			;10cc
	nop			;10cd
	nop			;10ce
	nop			;10cf
	nop			;10d0
	nop			;10d1
	nop			;10d2
	nop			;10d3
	nop			;10d4
	nop			;10d5
	nop			;10d6
	nop			;10d7
	nop			;10d8
	nop			;10d9
	nop			;10da
	nop			;10db
	nop			;10dc
	nop			;10dd
	nop			;10de
	nop			;10df
	nop			;10e0
	nop			;10e1
	nop			;10e2
	nop			;10e3
	nop			;10e4
	nop			;10e5
	nop			;10e6
	nop			;10e7
	nop			;10e8
	nop			;10e9
	nop			;10ea
	nop			;10eb
	nop			;10ec
	nop			;10ed
	nop			;10ee
	nop			;10ef
	nop			;10f0
	nop			;10f1
	nop			;10f2
	nop			;10f3
	nop			;10f4
	nop			;10f5
	nop			;10f6
	nop			;10f7
	nop			;10f8
	nop			;10f9
	nop			;10fa
	nop			;10fb
	nop			;10fc
	nop			;10fd
	nop			;10fe
	nop			;10ff
l1100h:
	nop			;1100
	nop			;1101
	nop			;1102
	nop			;1103
	nop			;1104
	nop			;1105
	jp l0a06h		;1106
l1109h:
	nop			;1109
	nop			;110a
	nop			;110b
	nop			;110c
	nop			;110d
	nop			;110e
	nop			;110f
	nop			;1110
	nop			;1111
	ld bc,00000h		;1112
	nop			;1115
	nop			;1116
	nop			;1117
	nop			;1118
	nop			;1119
	nop			;111a
	nop			;111b
	nop			;111c
	nop			;111d
	nop			;111e
	nop			;111f
	nop			;1120
	nop			;1121
	ld a,0ffh		;1122
	jr l1128h		;1124
	ld a,000h		;1126
l1128h:
	ld bc,(l051ch)		;1128
	push bc			;112c
	ld (l051ch),hl		;112d
	ld hl,(l0516h+2)	;1130
	push hl			;1133
	ld hl,(l051ah)		;1134
	push hl			;1137
	ld c,a			;1138
	ld h,d			;1139
	ld l,e			;113a
	srl h			;113b
	rr l			;113d
	ld (l0516h+2),hl	;113f
	ld a,e			;1142
	and 001h		;1143
	inc a			;1145
	ld (l051ah),a		;1146
	ld a,0ffh		;1149
	ld (l051eh),a		;114b
	call sub_06d5h		;114e
	pop hl			;1151
	ld (l051ah),hl		;1152
	pop hl			;1155
	ld (l0516h+2),hl	;1156
	pop hl			;1159
	ld (l051ch),hl		;115a
	ret			;115d
	ld a,(l0112h)		;115e
	or a			;1161
	ret z			;1162
	ld a,000h		;1163
	ld (l0114h),a		;1165
	ld a,(l0536h)		;1168
	srl a			;116b
	srl a			;116d
	ld b,a			;116f
	inc b			;1170
l1171h:
	push bc			;1171
	ld e,b			;1172
	dec e			;1173
	ld d,000h		;1174
	ld hl,0055ah		;1176
	call l0122h		;1179
	ld b,004h		;117c
	ld hl,0055ah		;117e
l1181h:
	ld a,(hl)		;1181
	cp 0e5h			;1182
	jr z,l119eh		;1184
	push bc			;1186
	ld b,010h		;1187
	push hl			;1189
	ld de,00010h		;118a
	add hl,de		;118d
	ld a,(l0114h)		;118e
l1191h:
	ld c,(hl)		;1191
	cp c			;1192
	jr nc,l1196h		;1193
	ld a,c			;1195
l1196h:
	inc hl			;1196
	djnz l1191h		;1197
	ld (l0114h),a		;1199
	pop hl			;119c
	pop bc			;119d
l119eh:
	ld de,00020h		;119e
	add hl,de		;11a1
	djnz l1181h		;11a2
	pop bc			;11a4
	djnz l1171h		;11a5
	ld a,(l0114h)		;11a7
	ld b,a			;11aa
	ld a,(l0112h)		;11ab
	ld e,a			;11ae
	ld a,(00534h)		;11af
	sub e			;11b2
	cp b			;11b3
	ld a,000h		;11b4
	ret c			;11b6
	ld a,(l0111h)		;11b7
	add a,e			;11ba
	ld (l0111h),a		;11bb
	ld a,(00534h)		;11be
	sub e			;11c1
	ld (00534h),a		;11c2
	ld e,a			;11c5
	inc e			;11c6
	ld a,(l0531h)		;11c7
	ld b,a			;11ca
	ld d,000h		;11cb
l11cdh:
	sla e			;11cd
	rl d			;11cf
	djnz l11cdh		;11d1
	ld (l0119h),de		;11d3
	ld a,(l0112h)		;11d7
	ld b,a			;11da
l11dbh:
	push bc			;11db
	ld a,(l0531h+1)		;11dc
	inc a			;11df
	ld b,a			;11e0
l11e1h:
	push bc			;11e1
	push de			;11e2
	ld hl,0055ah		;11e3
	call l0122h		;11e6
	pop de			;11e9
	pop bc			;11ea
	ld a,b			;11eb
	pop hl			;11ec
	push hl			;11ed
	cp h			;11ee
	jr nz,l11f8h		;11ef
	cp 001h			;11f1
	ld hl,00000h		;11f3
	jr z,l11fbh		;11f6
l11f8h:
	ld h,d			;11f8
	ld l,e			;11f9
	inc hl			;11fa
l11fbh:
	ld (l05d8h),hl		;11fb
	push bc			;11fe
	push de			;11ff
	ld hl,0055ah		;1200
	call sub_0126h		;1203
	pop de			;1206
	inc de			;1207
	pop bc			;1208
	djnz l11e1h		;1209
	pop bc			;120b
	djnz l11dbh		;120c
	ld a,001h		;120e
	ret			;1210
	ld d,h			;1211
	ld c,d			;1212
	ld c,b			;1213
	ld d,e			;1214
	ld d,b			;1215
	nop			;1216
	nop			;1217
	nop			;1218
	nop			;1219
	nop			;121a
	nop			;121b
	nop			;121c
	nop			;121d
	nop			;121e
	nop			;121f
	nop			;1220
	nop			;1221
	nop			;1222
	nop			;1223
	nop			;1224
	nop			;1225
	nop			;1226
	nop			;1227
	nop			;1228
	nop			;1229
	nop			;122a
	nop			;122b
	nop			;122c
	nop			;122d
	nop			;122e
	nop			;122f
	nop			;1230
	nop			;1231
	nop			;1232
	nop			;1233
	nop			;1234
	nop			;1235
	nop			;1236
	nop			;1237
	nop			;1238
	nop			;1239
	nop			;123a
	nop			;123b
	nop			;123c
	nop			;123d
	nop			;123e
	nop			;123f
	nop			;1240
	nop			;1241
	nop			;1242
	nop			;1243
	nop			;1244
	nop			;1245
	nop			;1246
	nop			;1247
	nop			;1248
	nop			;1249
	nop			;124a
	nop			;124b
	nop			;124c
	nop			;124d
	nop			;124e
	nop			;124f
	nop			;1250
	nop			;1251
	nop			;1252
	nop			;1253
	nop			;1254
	nop			;1255
	nop			;1256
	nop			;1257
	nop			;1258
	nop			;1259
	nop			;125a
	nop			;125b
	nop			;125c
	nop			;125d
	nop			;125e
	nop			;125f
	nop			;1260
	nop			;1261
	nop			;1262
	nop			;1263
	nop			;1264
	nop			;1265
	nop			;1266
	nop			;1267
	nop			;1268
	nop			;1269
	nop			;126a
	nop			;126b
	nop			;126c
	nop			;126d
	nop			;126e
	nop			;126f
	nop			;1270
	nop			;1271
	nop			;1272
	nop			;1273
	nop			;1274
	nop			;1275
	nop			;1276
	nop			;1277
	nop			;1278
	nop			;1279
	nop			;127a
	nop			;127b
	nop			;127c
	nop			;127d
	nop			;127e
	nop			;127f
	nop			;1280
	nop			;1281
	nop			;1282
	nop			;1283
	nop			;1284
	nop			;1285
	nop			;1286
	nop			;1287
	nop			;1288
	nop			;1289
	nop			;128a
	nop			;128b
	nop			;128c
	nop			;128d
	nop			;128e
	nop			;128f
	nop			;1290
	nop			;1291
	nop			;1292
	nop			;1293
	nop			;1294
	nop			;1295
	nop			;1296
	nop			;1297
	nop			;1298
	ld (l0120h),sp		;1299
	ld sp,l08dfh		;129d
	push bc			;12a0
	call sub_02aah		;12a1
	pop bc			;12a4
	ld sp,(l0120h)		;12a5
	ret			;12a9
	ld a,(l0116h)		;12aa
	or a			;12ad
	jr nz,l12cbh		;12ae
	ld a,(l0111h)		;12b0
	or a			;12b3
	jr z,l12fah		;12b4
	ld b,a			;12b6
	ld a,(00534h)		;12b7
	add a,b			;12ba
	ld (00534h),a		;12bb
	ld a,000h		;12be
	ld (l0111h),a		;12c0
	ld hl,00000h		;12c3
	ld (l0119h),hl		;12c6
	jr l12fah		;12c9
l12cbh:
	ld a,(l0217h)		;12cb
	or a			;12ce
	ret nz			;12cf
	ld a,(l0216h)		;12d0
	or a			;12d3
	jr nz,l12fah		;12d4
	call sub_0918h		;12d6
	or a			;12d9
	ret z			;12da
	ld a,(l0118h)		;12db
	or a			;12de
	jr nz,l1308h		;12df
	ld a,(l0116h)		;12e1
	ld e,a			;12e4
	ld a,(l0116h+1)		;12e5
	cp e			;12e8
	jr nc,l12fah		;12e9
	ld e,a			;12eb
	inc a			;12ec
	ld (l0116h+1),a		;12ed
	ld d,000h		;12f0
	ld hl,l0219h		;12f2
	add hl,de		;12f5
	ld c,(hl)		;12f6
	jp l08fah		;12f7
l12fah:
	xor a			;12fa
	ld (l0216h),a		;12fb
	ld (l0118h),a		;12fe
	ld (l0116h),a		;1301
	ld (l0116h+1),a		;1304
	ret			;1307
l1308h:
	ld a,(l0116h+1)		;1308
	ld e,a			;130b
	inc a			;130c
	ld (l0116h+1),a		;130d
	ld d,000h		;1310
	ld hl,l091bh		;1312
	add hl,de		;1315
	ld c,(hl)		;1316
	call l08fah		;1317
	ld a,(l0116h+1)		;131a
	cp 07eh			;131d
	ret nz			;131f
	ld de,(l0999h)		;1320
	ld hl,(l011dh)		;1324
	xor a			;1327
	ld (l0116h+1),a		;1328
	sbc hl,de		;132b
	ld (l0118h),a		;132d
	ret z			;1330
	ld a,d			;1331
	or e			;1332
	ret z			;1333
	ld (l0118h),a		;1334
	ld hl,(l011bh)		;1337
	sbc hl,de		;133a
	jr nz,l1344h		;133c
	ld hl,0ffffh		;133e
	ld (l011bh),hl		;1341
l1344h:
	push de			;1344
	ld hl,l091bh		;1345
	call l0122h		;1348
	ld hl,(l0119h)		;134b
	pop de			;134e
	ld (l0119h),de		;134f
	ld bc,(l0999h)		;1353
	push bc			;1357
	ld (l0999h),hl		;1358
	ld hl,l091bh		;135b
	call sub_0126h		;135e
	pop hl			;1361
	ld (l0999h),hl		;1362
	ret			;1365
	ld (l0120h),sp		;1366
	ld sp,l08dfh		;136a
	call l0375h		;136d
	ld sp,(l0120h)		;1370
	ret			;1374
	ld a,c			;1375
	ld (l011fh),a		;1376
	ld a,(l0217h)		;1379
	ld (l0112h+1),a		;137c
	or a			;137f
	jr nz,l1399h		;1380
	ld a,(l0216h)		;1382
	or a			;1385
	jr nz,l1399h		;1386
	ld a,(l0116h)		;1388
	or a			;138b
	jr nz,l1399h		;138c
	call sub_0918h		;138e
	or a			;1391
	ld a,(l011fh)		;1392
	ld c,a			;1395
	jp nz,l08fah		;1396
l1399h:
	ld a,(l0116h)		;1399
	cp 07eh			;139c
	jp nz,00455h		;139e
	call sub_02cbh		;13a1
	ld a,000h		;13a4
	ld (l0116h),a		;13a6
	ld (l0217h),a		;13a9
	ld a,(l0118h)		;13ac
	or a			;13af
	jr nz,l13d3h		;13b0
l13b2h:
	ld hl,0ffffh		;13b2
	ld (l011bh),hl		;13b5
	ld a,h			;13b8
	ld (l0118h),a		;13b9
	ld hl,(l0119h)		;13bc
	ld (l0297h),hl		;13bf
	ld (l011dh),hl		;13c2
	ld hl,l0219h		;13c5
	ld de,l091bh		;13c8
	ld bc,00080h		;13cb
	ldir			;13ce
	jp 00455h		;13d0
l13d3h:
	ld de,(l0119h)		;13d3
	ld a,d			;13d7
	or e			;13d8
	jr z,l13feh		;13d9
	push de			;13db
	ld hl,0055ah		;13dc
	call l0122h		;13df
	pop de			;13e2
	ld hl,(l05d8h)		;13e3
	jr l140bh		;13e6
l13e8h:
	call sub_02cbh		;13e8
	ld a,(l0118h)		;13eb
	or a			;13ee
	jr z,l13b2h		;13ef
	ld de,(l0119h)		;13f1
	ld a,d			;13f5
	or e			;13f6
	jr z,l13e8h		;13f7
	ld hl,00000h		;13f9
	jr l140bh		;13fc
l13feh:
	call l015eh		;13fe
	or a			;1401
	jr z,l13e8h		;1402
	ld de,(l0119h)		;1404
	ld h,d			;1408
	ld l,e			;1409
	inc hl			;140a
l140bh:
	push de			;140b
	ld (l0119h),hl		;140c
	ld (l0297h),hl		;140f
	ld hl,l0219h		;1412
	call sub_0126h		;1415
	pop de			;1418
	ld hl,(l011bh)		;1419
	ld a,h			;141c
	or a			;141d
	jp p,l0427h		;141e
	ld (l0999h),de		;1421
	jr l144bh		;1425
	or l			;1427
	jr z,l144bh		;1428
	ld hl,(l011dh)		;142a
	or a			;142d
	sbc hl,de		;142e
	jr z,l144bh		;1430
	push de			;1432
	ld de,(l011bh)		;1433
	push de			;1437
	ld hl,0055ah		;1438
	call l0122h		;143b
	pop de			;143e
	pop hl			;143f
	push hl			;1440
	ld (l05d8h),hl		;1441
	ld hl,0055ah		;1444
	call sub_0126h		;1447
	pop de			;144a
l144bh:
	ld (l011bh),de		;144b
	ld hl,(l0297h)		;144f
	ld (l011dh),hl		;1452
	ld a,(l0112h+1)		;1455
	ld (l0217h),a		;1458
	call sub_02cbh		;145b
	ld a,(l0116h)		;145e
	ld e,a			;1461
	inc a			;1462
	ld (l0116h),a		;1463
	ld d,000h		;1466
	ld hl,l0219h		;1468
	add hl,de		;146b
	ld a,(l011fh)		;146c
	ld (hl),a		;146f
	ret			;1470
	ld a,(l0116h)		;1471
	cp 07eh			;1474
	jr c,l1495h		;1476
	ld a,(l0118h)		;1478
	or a			;147b
	jr z,l1495h		;147c
	ld hl,(l0119h)		;147e
	ld a,h			;1481
	or l			;1482
	jr nz,l1495h		;1483
	ld (l0120h),sp		;1485
	ld sp,l08dfh		;1489
	call l015eh		;148c
	ld sp,(l0120h)		;148f
	or a			;1493
	ret z			;1494
l1495h:
	ld a,0ffh		;1495
	ret			;1497
	nop			;1498
	nop			;1499
	nop			;149a
	nop			;149b
	nop			;149c
	nop			;149d
	nop			;149e
	nop			;149f
	nop			;14a0
	nop			;14a1
	nop			;14a2
	nop			;14a3
	nop			;14a4
	nop			;14a5
	nop			;14a6
	nop			;14a7
	nop			;14a8
	nop			;14a9
	nop			;14aa
	nop			;14ab
	nop			;14ac
	nop			;14ad
	nop			;14ae
	nop			;14af
	nop			;14b0
	nop			;14b1
	nop			;14b2
	nop			;14b3
	nop			;14b4
	nop			;14b5
	nop			;14b6
	nop			;14b7
	nop			;14b8
	nop			;14b9
	nop			;14ba
	nop			;14bb
	nop			;14bc
	nop			;14bd
	nop			;14be
	nop			;14bf
	nop			;14c0
	nop			;14c1
	nop			;14c2
	nop			;14c3
	nop			;14c4
	nop			;14c5
	nop			;14c6
	nop			;14c7
	nop			;14c8
	nop			;14c9
	nop			;14ca
	nop			;14cb
	nop			;14cc
	nop			;14cd
	nop			;14ce
	nop			;14cf
	nop			;14d0
	nop			;14d1
	nop			;14d2
	nop			;14d3
	nop			;14d4
	nop			;14d5
	nop			;14d6
	nop			;14d7
	nop			;14d8
	nop			;14d9
	nop			;14da
	nop			;14db
	nop			;14dc
	nop			;14dd
	nop			;14de
	nop			;14df
	nop			;14e0
	nop			;14e1
	nop			;14e2
	nop			;14e3
	nop			;14e4
	nop			;14e5
	nop			;14e6
	nop			;14e7
	nop			;14e8
	nop			;14e9
	nop			;14ea
	nop			;14eb
	nop			;14ec
	nop			;14ed
	nop			;14ee
	nop			;14ef
	nop			;14f0
	nop			;14f1
	nop			;14f2
	nop			;14f3
	nop			;14f4
	nop			;14f5
	nop			;14f6
	nop			;14f7
	nop			;14f8
	nop			;14f9
	nop			;14fa
	nop			;14fb
	nop			;14fc
	nop			;14fd
	nop			;14fe
	nop			;14ff
	nop			;1500
	nop			;1501
	nop			;1502
	nop			;1503
	nop			;1504
	nop			;1505
	jp l0a06h		;1506
	nop			;1509
	nop			;150a
	nop			;150b
	nop			;150c
	nop			;150d
	nop			;150e
	nop			;150f
	nop			;1510
	ld d,h			;1511
	ld c,d			;1512
	ld c,b			;1513
l1514h:
	ex de,hl		;1514
	rlca			;1515
l1516h:
	ld (bc),a		;1516
	nop			;1517
	nop			;1518
	nop			;1519
	nop			;151a
	nop			;151b
	nop			;151c
	nop			;151d
	nop			;151e
	ld e,b			;151f
	dec b			;1520
	nop			;1521
	nop			;1522
	nop			;1523
	nop			;1524
	nop			;1525
	nop			;1526
	ld e,d			;1527
	dec b			;1528
	cpl			;1529
	dec b			;152a
	nop			;152b
	nop			;152c
	ccf			;152d
	dec b			;152e
	ld (bc),a		;152f
	nop			;1530
	inc b			;1531
	rrca			;1532
	ld bc,000bfh		;1533
	ld a,a			;1536
	nop			;1537
	ret nz			;1538
	nop			;1539
	nop			;153a
	nop			;153b
	nop			;153c
	nop			;153d
l153eh:
	rst 38h			;153e
	nop			;153f
	nop			;1540
	nop			;1541
	nop			;1542
	nop			;1543
	nop			;1544
	nop			;1545
	nop			;1546
	nop			;1547
	nop			;1548
	nop			;1549
	nop			;154a
	nop			;154b
	nop			;154c
	nop			;154d
	nop			;154e
	nop			;154f
	nop			;1550
	nop			;1551
	nop			;1552
	nop			;1553
	nop			;1554
	nop			;1555
	nop			;1556
	nop			;1557
	ld bc,00002h		;1558
	nop			;155b
	nop			;155c
	nop			;155d
	nop			;155e
	nop			;155f
	nop			;1560
	nop			;1561
	nop			;1562
	nop			;1563
	nop			;1564
	nop			;1565
	nop			;1566
	nop			;1567
	nop			;1568
	nop			;1569
	nop			;156a
	nop			;156b
	nop			;156c
	nop			;156d
	nop			;156e
	nop			;156f
	nop			;1570
	nop			;1571
	nop			;1572
	nop			;1573
	nop			;1574
	nop			;1575
	nop			;1576
	nop			;1577
	nop			;1578
	nop			;1579
	nop			;157a
	nop			;157b
	nop			;157c
	nop			;157d
	nop			;157e
	nop			;157f
	nop			;1580
	nop			;1581
	nop			;1582
	nop			;1583
	nop			;1584
	nop			;1585
	nop			;1586
	nop			;1587
	nop			;1588
	nop			;1589
	nop			;158a
	nop			;158b
	nop			;158c
	nop			;158d
	nop			;158e
	nop			;158f
	nop			;1590
	nop			;1591
	nop			;1592
	nop			;1593
	nop			;1594
	nop			;1595
	nop			;1596
	nop			;1597
	nop			;1598
	nop			;1599
	nop			;159a
	nop			;159b
	nop			;159c
	nop			;159d
	nop			;159e
	nop			;159f
	nop			;15a0
	nop			;15a1
	nop			;15a2
	nop			;15a3
	nop			;15a4
	nop			;15a5
	nop			;15a6
	nop			;15a7
	nop			;15a8
	nop			;15a9
	nop			;15aa
	nop			;15ab
	nop			;15ac
	nop			;15ad
	nop			;15ae
	nop			;15af
	nop			;15b0
	nop			;15b1
	nop			;15b2
	nop			;15b3
	nop			;15b4
	nop			;15b5
	nop			;15b6
l15b7h:
	nop			;15b7
	nop			;15b8
	nop			;15b9
	nop			;15ba
	nop			;15bb
	nop			;15bc
	nop			;15bd
	nop			;15be
	nop			;15bf
	nop			;15c0
	nop			;15c1
	nop			;15c2
	nop			;15c3
	nop			;15c4
	nop			;15c5
	nop			;15c6
	nop			;15c7
	nop			;15c8
	nop			;15c9
	nop			;15ca
	nop			;15cb
	nop			;15cc
	nop			;15cd
	nop			;15ce
	nop			;15cf
	nop			;15d0
	nop			;15d1
	nop			;15d2
	nop			;15d3
	nop			;15d4
	nop			;15d5
	nop			;15d6
	nop			;15d7
	nop			;15d8
	nop			;15d9
	ld bc,04644h		;15da
	ld b,h			;15dd
	jr nz,l1600h		;15de
	jr nz,$+34		;15e0
	jr nz,l15b7h		;15e2
	ret nc			;15e4
	ld d,d			;15e5
	nop			;15e6
	nop			;15e7
	nop			;15e8
	nop			;15e9
	nop			;15ea
	nop			;15eb
	nop			;15ec
	nop			;15ed
	nop			;15ee
	nop			;15ef
	nop			;15f0
	nop			;15f1
	nop			;15f2
	nop			;15f3
	nop			;15f4
	nop			;15f5
	nop			;15f6
	nop			;15f7
	nop			;15f8
	nop			;15f9
	nop			;15fa
	nop			;15fb
	nop			;15fc
	nop			;15fd
l15feh:
	nop			;15fe
	nop			;15ff
l1600h:
	jp l07bfh		;1600
	jp l07bfh		;1603
	jp l063bh		;1606
	jp 00641h		;1609
	jp l064fh+1		;160c
	jp l0366h		;160f
	jp l0656h		;1612
	jp l065ch		;1615
	jp l0662h		;1618
	jp l066bh		;161b
	jp l068dh		;161e
	jp l0694h		;1621
	jp l069bh		;1624
	jp 006a2h		;1627
	jp l06a4h		;162a
	jp l0471h		;162d
l1630h:
	nop			;1630
	nop			;1631
	nop			;1632
	nop			;1633
	nop			;1634
	nop			;1635
	nop			;1636
	nop			;1637
l1638h:
	jp l0299h		;1638
	call sub_0638h		;163b
	jp 008f1h		;163e
	call sub_0638h		;1641
l1644h:
	call 008f1h		;1644
	or a			;1647
	jp nz,l08f4h		;1648
	call sub_0638h		;164b
	jr l1644h		;164e
	call sub_0638h		;1650
	jp l08f7h		;1653
	call sub_0638h		;1656
	jp 008fdh		;1659
	call sub_0638h		;165c
	jp 00900h		;165f
	ld hl,00000h		;1662
	ld (l0516h+2),hl	;1665
	jp 00903h		;1668
	ld a,000h		;166b
	ld (l0516h+1),a		;166d
	ld a,(l0516h)		;1670
	cp c			;1673
	jr nz,l167fh		;1674
	ld a,0ffh		;1676
	ld (l0516h+1),a		;1678
	ld hl,l051eh+1		;167b
	ret			;167e
l167fh:
	ld a,(0053eh)		;167f
	cp c			;1682
	jp nz,l0906h		;1683
	ld a,(l0516h)		;1686
	ld c,a			;1689
	jp l0906h		;168a
	ld (l0516h+2),bc	;168d
	jp 00909h		;1691
	ld (l051ah),bc		;1694
	jp l090ch		;1698
	ld (l051ch),bc		;169b
	jp l090fh		;169f
	ld c,0ffh		;16a2
	call sub_0638h		;16a4
	ld a,(l0516h+1)		;16a7
	or a			;16aa
	jr nz,l16b6h		;16ab
	ld a,c			;16ad
	cp 0ffh			;16ae
	jp z,l0912h		;16b0
	jp l0915h		;16b3
l16b6h:
	ld (l051eh),a		;16b6
	ld a,(l051ch+1)		;16b9
	cp 040h			;16bc
	jr nc,l16d5h		;16be
	xor a			;16c0
	ld (l051eh),a		;16c1
	ld a,c			;16c4
	inc a			;16c5
	jr z,l16d5h		;16c6
	push bc			;16c8
	ld bc,00080h		;16c9
	ld de,0055ah		;16cc
	ld hl,(l051ch)		;16cf
	ldir			;16d2
	pop bc			;16d4
l16d5h:
	di			;16d5
	xor a			;16d6
	out (000h),a		;16d7
	ld hl,02901h		;16d9
	ld (hl),032h		;16dc
	ld hl,02900h		;16de
	ld (hl),0ffh		;16e1
	ld hl,02901h		;16e3
	ld (hl),036h		;16e6
	ld hl,02903h		;16e8
	ld (hl),032h		;16eb
	ld hl,02902h		;16ed
	ld (hl),0ffh		;16f0
	ld hl,02903h		;16f2
	ld (hl),036h		;16f5
	ld hl,02902h		;16f7
	ld (hl),008h		;16fa
	ld a,(l0516h+2)		;16fc
	call sub_07b5h		;16ff
	ld a,(l051ah)		;1702
	rrca			;1705
	and 080h		;1706
	ld b,a			;1708
	ld a,(l0519h)		;1709
	cp 003h			;170c
	jr c,l1718h		;170e
	sub 003h		;1710
	rlca			;1712
	rlca			;1713
	or 003h			;1714
	jr l171ah		;1716
l1718h:
	or 00ch			;1718
l171ah:
	or b			;171a
	ld hl,02902h		;171b
	ld (hl),000h		;171e
	call sub_07b5h		;1720
	ld a,c			;1723
	inc a			;1724
	ld a,088h		;1725
	jr nz,l173ah		;1727
	ld hl,02901h		;1729
	ld (hl),032h		;172c
	ld hl,02900h		;172e
	ld (hl),000h		;1731
	ld hl,02901h		;1733
	ld (hl),036h		;1736
	ld a,081h		;1738
l173ah:
	ld hl,02902h		;173a
	ld (hl),a		;173d
	ld hl,02900h		;173e
	ld de,0055ah		;1741
	ld a,(l051eh)		;1744
	or a			;1747
	jr z,l174eh		;1748
	ld de,(l051ch)		;174a
l174eh:
	ld a,c			;174e
	push bc			;174f
	ld bc,00080h		;1750
	inc a			;1753
	jr nz,l1763h		;1754
	inc hl			;1756
	ld (hl),03eh		;1757
	ld (hl),036h		;1759
	dec hl			;175b
	ldi			;175c
	jp pe,00757h		;175e
	jr l176fh		;1761
l1763h:
	ex de,hl		;1763
	ldi			;1764
	ex de,hl		;1766
	ld (hl),03eh		;1767
	ld (hl),036h		;1769
	dec hl			;176b
	jp pe,l0763h		;176c
l176fh:
	ld hl,02902h		;176f
	ld (hl),009h		;1772
	ld a,032h		;1774
	ld (02901h),a		;1776
	ld a,0ffh		;1779
	ld (02900h),a		;177b
	ld a,036h		;177e
	ld (02901h),a		;1780
	ld a,000h		;1783
	ld (02903h),a		;1785
	ld a,0bfh		;1788
	ld (02902h),a		;178a
	ld a,004h		;178d
	ld (02903h),a		;178f
	ld a,002h		;1792
	ld (02902h),a		;1794
	ld a,001h		;1797
	out (001h),a		;1799
	ei			;179b
	pop bc			;179c
	ld a,(l051eh)		;179d
	cpl			;17a0
	or a			;17a1
	ret z			;17a2
	ld a,c			;17a3
	inc a			;17a4
	ld a,000h		;17a5
	ret nz			;17a7
	ld bc,00080h		;17a8
	ld hl,0055ah		;17ab
	ld de,(l051ch)		;17ae
	ldir			;17b2
	ret			;17b4
	ld hl,02900h		;17b5
	ld (hl),a		;17b8
	inc hl			;17b9
	ld (hl),03eh		;17ba
	ld (hl),036h		;17bc
	ret			;17be
	ld sp,008ebh		;17bf
	ld hl,(l0630h)		;17c2
	ld (0ef0fh),hl		;17c5
	ld de,00080h		;17c8
	ld c,01ah		;17cb
	call sub_0506h		;17cd
	ld e,00fh		;17d0
	ld c,020h		;17d2
	call sub_0506h		;17d4
	ld a,(l0516h)		;17d7
	call sub_08a7h		;17da
	jr nz,l1804h		;17dd
	ld e,000h		;17df
	ld c,020h		;17e1
	call sub_0506h		;17e3
	ld a,(l0516h)		;17e6
	call sub_08a7h		;17e9
	jr nz,l1804h		;17ec
	ld a,(l0516h)		;17ee
	or a			;17f1
	ld a,000h		;17f2
	jr nz,l17ffh		;17f4
	ld a,(0053eh)		;17f6
	cp 0ffh			;17f9
	jr nz,l17ffh		;17fb
	ld a,001h		;17fd
l17ffh:
	call sub_08a7h		;17ff
l1802h:
	jr z,l1802h		;1802
l1804h:
	xor a			;1804
	ld (005fah),a		;1805
	ld (l05fbh),a		;1808
	ld de,l05dah		;180b
	ld c,014h		;180e
	call sub_0506h		;1810
	ld bc,(00081h)		;1813
	push bc			;1817
	ld a,c			;1818
	or a			;1819
	jr z,l181dh		;181a
	inc b			;181c
l181dh:
	xor a			;181d
	ld c,a			;181e
	ld hl,(l05feh)		;181f
	sbc hl,bc		;1822
	ld (l05fbh+1),hl	;1824
	push hl			;1827
	ld de,l05dah		;1828
	ld c,014h		;182b
	call sub_0506h		;182d
	pop hl			;1830
	pop bc			;1831
	push bc			;1832
l1833h:
	push bc			;1833
	push hl			;1834
	call l0889h		;1835
	pop hl			;1838
	pop bc			;1839
	ld (hl),a		;183a
	inc hl			;183b
	dec bc			;183c
	ld a,b			;183d
	or c			;183e
	jr nz,l1833h		;183f
	ld d,001h		;1841
	ld hl,(l05fbh+1)	;1843
	pop bc			;1846
l1847h:
	rrc d			;1847
	jr nc,l1855h		;1849
	push de			;184b
	push hl			;184c
	push bc			;184d
	call l0889h		;184e
	pop bc			;1851
	pop hl			;1852
	pop de			;1853
	ld e,a			;1854
l1855h:
	ld a,d			;1855
	and e			;1856
	jr z,l185eh		;1857
	ld a,(l05fbh+2)		;1859
	add a,(hl)		;185c
	ld (hl),a		;185d
l185eh:
	inc hl			;185e
	dec bc			;185f
	ld a,b			;1860
	or c			;1861
	jr nz,l1847h		;1862
	ld c,020h		;1864
	ld e,000h		;1866
	call sub_0506h		;1868
	ld hl,l1802h+1		;186b
	ld (00001h),hl		;186e
	ld hl,(l05feh)		;1871
	ld l,006h		;1874
	ld (00006h),hl		;1876
	ld a,0c3h		;1879
	ld (00000h),a		;187b
	ld (00005h),a		;187e
	ld a,(00004h)		;1881
	ld c,a			;1884
	ld hl,(l05fbh+1)	;1885
	jp (hl)			;1888
	ld a,(l05fbh)		;1889
	or a			;188c
	jr nz,l1898h		;188d
	ld de,l05dah		;188f
	ld c,014h		;1892
	call sub_0506h		;1894
	xor a			;1897
l1898h:
	ld c,a			;1898
	ld b,000h		;1899
	ld hl,00080h		;189b
	add hl,bc		;189e
	inc a			;189f
	and 07fh		;18a0
	ld (l05fbh),a		;18a2
	ld a,(hl)		;18a5
	ret			;18a6
	inc a			;18a7
	ld (l05dah),a		;18a8
	ld de,l05dah		;18ab
	ld c,00fh		;18ae
	call sub_0506h		;18b0
	inc a			;18b3
	ret			;18b4
	call z,0cccch		;18b5
	call z,0cccch		;18b8
	call z,0cccch		;18bb
	call z,0cccch		;18be
	call z,0cccch		;18c1
	call z,0cccch		;18c4
	call z,0cccch		;18c7
	call z,0cccch		;18ca
	call z,0cccch		;18cd
	call z,0cccch		;18d0
	call z,0cccch		;18d3
	call z,0cccch		;18d6
	call z,0cccch		;18d9
	call z,0cccch		;18dc
	call z,0cccch		;18df
	call z,0cccch		;18e2
	call z,0cccch		;18e5
	call z,0cccch		;18e8
	jp 00000h		;18eb
	jp 00000h		;18ee
	jp 00000h		;18f1
	jp 00000h		;18f4
	jp 00000h		;18f7
	jp 00000h		;18fa
	jp 00000h		;18fd
	jp 00000h		;1900
	jp 00000h		;1903
	jp 00000h		;1906
	jp 00000h		;1909
	jp 00000h		;190c
	jp 00000h		;190f
	jp 00000h		;1912
	jp 00000h		;1915
	jp 00000h		;1918
	nop			;191b
	nop			;191c
	nop			;191d
	nop			;191e
	nop			;191f
	nop			;1920
	nop			;1921
	nop			;1922
	nop			;1923
	nop			;1924
	nop			;1925
	nop			;1926
	nop			;1927
	nop			;1928
	nop			;1929
	nop			;192a
	nop			;192b
	nop			;192c
	nop			;192d
	nop			;192e
	nop			;192f
	nop			;1930
	nop			;1931
	nop			;1932
	nop			;1933
	nop			;1934
	nop			;1935
	nop			;1936
	nop			;1937
	nop			;1938
	nop			;1939
	nop			;193a
	nop			;193b
	nop			;193c
	nop			;193d
	nop			;193e
	nop			;193f
	nop			;1940
	nop			;1941
	nop			;1942
	nop			;1943
	nop			;1944
	nop			;1945
	nop			;1946
	nop			;1947
	nop			;1948
	nop			;1949
	nop			;194a
	nop			;194b
	nop			;194c
	nop			;194d
	nop			;194e
	nop			;194f
	nop			;1950
	nop			;1951
	nop			;1952
	nop			;1953
	nop			;1954
	nop			;1955
	nop			;1956
	nop			;1957
	nop			;1958
l1959h:
	nop			;1959
	nop			;195a
l195bh:
	nop			;195b
	nop			;195c
	nop			;195d
	nop			;195e
	nop			;195f
	nop			;1960
	nop			;1961
	nop			;1962
	nop			;1963
	nop			;1964
	nop			;1965
	nop			;1966
	nop			;1967
	nop			;1968
	nop			;1969
	nop			;196a
	nop			;196b
	nop			;196c
	nop			;196d
	nop			;196e
	nop			;196f
	nop			;1970
	nop			;1971
	nop			;1972
	nop			;1973
	nop			;1974
	nop			;1975
l1976h:
	nop			;1976
	nop			;1977
	nop			;1978
	nop			;1979
	nop			;197a
	nop			;197b
	nop			;197c
l197dh:
	nop			;197d
	nop			;197e
	nop			;197f
	nop			;1980
	nop			;1981
	nop			;1982
	nop			;1983
	nop			;1984
	nop			;1985
	nop			;1986
	nop			;1987
l1988h:
	nop			;1988
	nop			;1989
	nop			;198a
	nop			;198b
	nop			;198c
	nop			;198d
	nop			;198e
	nop			;198f
	nop			;1990
	nop			;1991
	nop			;1992
	nop			;1993
	nop			;1994
	nop			;1995
	nop			;1996
	nop			;1997
	nop			;1998
	nop			;1999
	nop			;199a
	nop			;199b
	add a,b			;199c
	nop			;199d
	nop			;199e
	nop			;199f
	ld de,00022h		;19a0
	ld b,b			;19a3
	add a,h			;19a4
	adc a,b			;19a5
	adc a,b			;19a6
	add a,c			;19a7
	jr nz,l19aah		;19a8
l19aah:
	sub b			;19aa
	add a,b			;19ab
	nop			;19ac
	add a,b			;19ad
	djnz l19b0h		;19ae
l19b0h:
	ld b,h			;19b0
	ld b,b			;19b1
	ld b,h			;19b2
	adc a,b			;19b3
	ld b,b			;19b4
	ld (bc),a		;19b5
	ld b,d			;19b6
	inc b			;19b7
	add a,b			;19b8
	nop			;19b9
	inc b			;19ba
	inc h			;19bb
	nop			;19bc
	nop			;19bd
	nop			;19be
	nop			;19bf
	nop			;19c0
	nop			;19c1
	nop			;19c2
	nop			;19c3
	nop			;19c4
	nop			;19c5
	nop			;19c6
	nop			;19c7
	nop			;19c8
	nop			;19c9
	nop			;19ca
	nop			;19cb
	nop			;19cc
	nop			;19cd
	add hl,bc		;19ce
	djnz l1959h		;19cf
	jr nz,l1a17h		;19d1
	jr nz,l1959h		;19d3
	jr nz,l195bh		;19d5
	ld de,l0801h		;19d7
	ld b,h			;19da
	sub d			;19db
	ld hl,04808h		;19dc
	ld (de),a		;19df
	ld hl,04002h		;19e0
	ld de,02224h		;19e3
	inc h			;19e6
	adc a,b			;19e7
	ld c,c			;19e8
	djnz l197dh		;19e9
	ex af,af'		;19eb
	jr nz,l1976h		;19ec
	sub b			;19ee
	sub b			;19ef
	sub d			;19f0
	ld bc,04912h		;19f1
	jr nz,l1a18h		;19f4
	ld (bc),a		;19f6
	ld b,h			;19f7
	inc h			;19f8
	ex af,af'		;19f9
	nop			;19fa
	add a,c			;19fb
	ld (bc),a		;19fc
	ld c,c			;19fd
	djnz l1988h		;19fe
	ex af,af'		;1a00
	ld (bc),a		;1a01
	inc h			;1a02
	ld (de),a		;1a03
	ld b,d			;1a04
	ld c,c			;1a05
	inc h			;1a06
	add a,h			;1a07
	ld (02010h),hl		;1a08
	add a,b			;1a0b
	sub d			;1a0c
	jr nz,l1a0fh		;1a0d
l1a0fh:
	nop			;1a0f
	nop			;1a10
	nop			;1a11
	nop			;1a12
	nop			;1a13
	nop			;1a14
	nop			;1a15
	nop			;1a16
l1a17h:
	nop			;1a17
l1a18h:
	nop			;1a18
	nop			;1a19
	nop			;1a1a
	nop			;1a1b
	add a,b			;1a1c
	nop			;1a1d
	nop			;1a1e
	add a,b			;1a1f
	and d			;1a20
	nop			;1a21
	nop			;1a22
	nop			;1a23
	nop			;1a24
	nop			;1a25
	nop			;1a26
	nop			;1a27
	nop			;1a28
	nop			;1a29
	nop			;1a2a
	nop			;1a2b
	nop			;1a2c
	nop			;1a2d
	nop			;1a2e
	nop			;1a2f
	nop			;1a30
	nop			;1a31
	nop			;1a32
	nop			;1a33
	nop			;1a34
	nop			;1a35
	nop			;1a36
	nop			;1a37
	nop			;1a38
	nop			;1a39
	nop			;1a3a
	inc h			;1a3b
	sub d			;1a3c
	ld c,c			;1a3d
	inc h			;1a3e
	sub d			;1a3f
	ld c,c			;1a40
	nop			;1a41
	inc h			;1a42
	sub d			;1a43
	inc h			;1a44
	inc h			;1a45
	sub d			;1a46
	ld b,c			;1a47
	ld hl,02420h		;1a48
	ld b,h			;1a4b
	adc a,b			;1a4c
	sub c			;1a4d
	ld (04042h),hl		;1a4e
	inc h			;1a51
	sub b			;1a52
	djnz l1a57h		;1a53
	ld b,b			;1a55
	nop			;1a56
l1a57h:
	nop			;1a57
	nop			;1a58
	nop			;1a59
	ld (bc),a		;1a5a
	ld c,b			;1a5b
	djnz l1a5eh		;1a5c
l1a5eh:
	nop			;1a5e
	jr nz,l1a61h		;1a5f
l1a61h:
	nop			;1a61
	nop			;1a62
	ld (de),a		;1a63
	inc b			;1a64
	nop			;1a65
	nop			;1a66
	add a,b			;1a67
	ld (bc),a		;1a68
	nop			;1a69
	nop			;1a6a
	nop			;1a6b
	nop			;1a6c
	nop			;1a6d
	ld bc,l0400h		;1a6e
	ld b,b			;1a71
	nop			;1a72
	ld c,b			;1a73
	ld bc,04802h		;1a74
	inc b			;1a77
	sub b			;1a78
	add a,b			;1a79
	add a,b			;1a7a
	ld b,c			;1a7b
	inc h			;1a7c
	jr nz,l1a7fh		;1a7d
l1a7fh:
	ld b,d			;1a7f
	ld hl,00001h		;1a80
	inc b			;1a83
	nop			;1a84
	add a,b			;1a85
	djnz l1a88h		;1a86
l1a88h:
	inc h			;1a88
	djnz l1a8bh		;1a89
l1a8bh:
	ld bc,04210h		;1a8b
	nop			;1a8e
	ex af,af'		;1a8f
	inc h			;1a90
	jr nz,l1a93h		;1a91
l1a93h:
	nop			;1a93
	nop			;1a94
	nop			;1a95
	nop			;1a96
	nop			;1a97
	nop			;1a98
	nop			;1a99
	nop			;1a9a
	nop			;1a9b
	nop			;1a9c
	nop			;1a9d
	nop			;1a9e
	nop			;1a9f
	nop			;1aa0
	nop			;1aa1
	nop			;1aa2
	nop			;1aa3
	nop			;1aa4
	nop			;1aa5
	nop			;1aa6
	nop			;1aa7
	nop			;1aa8
	nop			;1aa9
	nop			;1aaa
	nop			;1aab
	nop			;1aac
	nop			;1aad
	nop			;1aae
	ld a,(de)		;1aaf
	ld a,(de)		;1ab0
	ld a,(de)		;1ab1
	ld a,(de)		;1ab2
	ld a,(de)		;1ab3
	ld a,(de)		;1ab4
	ld a,(de)		;1ab5
	ld a,(de)		;1ab6
	ld a,(de)		;1ab7
	ld a,(de)		;1ab8
	ld a,(de)		;1ab9
	ld a,(de)		;1aba
	ld a,(de)		;1abb
	ld a,(de)		;1abc
	ld a,(de)		;1abd
	ld a,(de)		;1abe
	ld a,(de)		;1abf
	ld a,(de)		;1ac0
	ld a,(de)		;1ac1
	ld a,(de)		;1ac2
	ld a,(de)		;1ac3
	ld a,(de)		;1ac4
	ld a,(de)		;1ac5
	ld a,(de)		;1ac6
	ld a,(de)		;1ac7
	ld a,(de)		;1ac8
	ld a,(de)		;1ac9
	ld a,(de)		;1aca
	ld a,(de)		;1acb
	ld a,(de)		;1acc
	ld a,(de)		;1acd
	ld a,(de)		;1ace
	ld a,(de)		;1acf
	ld a,(de)		;1ad0
	ld a,(de)		;1ad1
	ld a,(de)		;1ad2
	ld a,(de)		;1ad3
	ld a,(de)		;1ad4
	ld a,(de)		;1ad5
	ld a,(de)		;1ad6
	ld a,(de)		;1ad7
	ld a,(de)		;1ad8
	ld a,(de)		;1ad9
	ld a,(de)		;1ada
	ld a,(de)		;1adb
	ld a,(de)		;1adc
	ld a,(de)		;1add
	ld a,(de)		;1ade
	ld a,(de)		;1adf
	ld a,(de)		;1ae0
	ld a,(de)		;1ae1
	ld a,(de)		;1ae2
	ld a,(de)		;1ae3
	ld a,(de)		;1ae4
	ld a,(de)		;1ae5
	ld a,(de)		;1ae6
	ld a,(de)		;1ae7
	ld a,(de)		;1ae8
	ld a,(de)		;1ae9
	ld a,(de)		;1aea
	ld a,(de)		;1aeb
	ld a,(de)		;1aec
	ld a,(de)		;1aed
	ld a,(de)		;1aee
	ld a,(de)		;1aef
	ld a,(de)		;1af0
	ld a,(de)		;1af1
	ld a,(de)		;1af2
	ld a,(de)		;1af3
	ld a,(de)		;1af4
	ld a,(de)		;1af5
	ld a,(de)		;1af6
	ld a,(de)		;1af7
	ld a,(de)		;1af8
	ld a,(de)		;1af9
	ld a,(de)		;1afa
	ld a,(de)		;1afb
	ld a,(de)		;1afc
	ld a,(de)		;1afd
	ld a,(de)		;1afe
	ld a,(de)		;1aff
