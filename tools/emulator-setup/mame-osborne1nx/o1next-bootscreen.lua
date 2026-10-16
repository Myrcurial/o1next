-- o1next-bootscreen.lua -- the boot screen, read back off the machine (#247 step 8,
-- turn 4).
--
-- WHY THIS EXISTS
--   Every other harness here checks a *door*: what the ROM service serves, what the
--   window holds, what the chain copies.  This one checks the *result*.  ROM 2.0's
--   monitor calls its ~30-byte stub at the sign-on prompt -- `rom2.diff` replaces
--   the stock `LDK DE,IMSG` + `CALL OSTR` with `CALL SCRN` -- the stub asks the
--   interposer for the screen's code with `PRESENT(3)`, copies window page 1 to RAM
--   at 4000h and jumps into it, and the code fills the attribute array bright,
--   prints its fallback text, blits the frame's character half into the video RAM
--   and its attribute half into the ninth bit, puts the payload back and RETs to
--   the sign-on prompt (docs/o1-rom-2.0.md 4.7; the code is
--   research/source-code/BIOS-200-source/rom2-screen.asm).
--
--   So the two planes are the evidence, and the whole chain -- monitor -> stub ->
--   PRESENT(3) -> the code running -> the screen drawn -- is measured end to end by
--   reading them: after it runs, F000h-FFFFh holds the frame's characters, and the
--   same 4096 bytes with the ninth bit paged in hold the frame's attributes.
--
-- THE TWO PLANES ARE ONE ADDRESS
--   The ninth video bit is a separate 4Kx1 array paged over the video RAM by
--   `OUT (02h)` and `OUT (03h)` puts the character RAM back -- the stock monitor's
--   own macros `ENADIM` and `DISDIM` (rom144.asm), and `bankswitch_w`'s offsets 2
--   and 3.  So both planes are read at F000h-FFFFh, one at a time, with the same
--   two writes the guest itself makes.
--
-- AND THE ATTRIBUTE COMPARISON IS ONE BIT, BUT IT STILL BITES
--   `attrram_w` discards the low seven bits of what is written -- "attribute RAM is
--   only one bit wide - low seven bits are discarded and read back high" -- so that
--   comparison is bit 7 only.  It is not therefore vacuous: the frame's attribute
--   half is all-bright `0xFF` *except* its own trailer at 0FF8h, whose six magic
--   bytes are `4F 31 4E 45 58 54`, every one of them with bit 7 **clear**.  Those
--   six cells read dim after the blit and bright after the bright fill alone, so
--   this is a measurement of the blit rather than of the fill.
--
-- Run it as a *standalone* -autoboot_script, with all three assets mounted:
--
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -frame firmware/rom-service/frame.bin \
--     -bootsplash firmware/rom-service/screen.bin \
--     -autoboot_script o1next-bootscreen.lua -seconds_to_run 30
--
-- Environment:
--   O1_FRAME       the image mounted with -frame (required; it is the expectation)
--   O1_BOOTSPLASH  the image mounted with -bootsplash, if any
--   O1_EXPECT      `splash` (the default) -- the splash is mounted, so the frame
--                  has to be on the screen.  `stock` -- no splash is mounted, so
--                  the stub prints the stock sign-on and the frame has to *not*
--                  be, which is what says the frame came from the screen code.
--
-- It prints SCREEN: PASS or SCREEN: FAIL, and exits 0 or 1.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local I = M.devices[":maincpu"].spaces["io"]

local VRAM, PLANE, STRIDE = 0xf000, 0x1000, 128
local OUT_ATTRS, OUT_CHARS = 0x02, 0x03    -- ENADIM / DISDIM (rom144.asm)
local FRAME  = os.getenv("O1_FRAME")
local SPLASH = os.getenv("O1_BOOTSPLASH")
local EXPECT = os.getenv("O1_EXPECT") or "splash"
-- an empty environment variable is an unset one: Lua would call "" a mounted file
if FRAME == "" then FRAME = nil end
if SPLASH == "" then SPLASH = nil end

io.stdout:setvbuf("no")
local fails = 0
local function logf(s) print(s) ; io.stdout:flush() end

local function slurp(path)
  local f = assert(io.open(path, "rb"), "no such file: " .. path)
  local d = f:read("a")
  f:close()
  return d
end

local function check(ok, what, detail)
  if ok then
    logf("  PASS  " .. what)
  else
    fails = fails + 1
    logf("  FAIL  " .. what .. (detail and ("  --  " .. detail) or ""))
  end
end

-- --- the two planes ---------------------------------------------------------
-- `OUT (03h)` (DISDIM) puts the character RAM back at F000h-FFFFh, and `OUT (02h)`
-- (ENADIM) pages the attribute array in over it.  Both planes are 4096 bytes: 32
-- rows of 128 columns, of which 24 x 52 are the visible window (the slice is the
-- scroll register's, so array row is not screen row when it is not zero).
local function chars()
  I:write_u8(OUT_CHARS, 0)
  local p = {}
  for a = 0, PLANE - 1 do p[a] = P:read_u8(VRAM + a) end
  return p
end

local function attrs()
  I:write_u8(OUT_ATTRS, 0)
  local p = {}
  for a = 0, PLANE - 1 do p[a] = P:read_u8(VRAM + a) end
  I:write_u8(OUT_CHARS, 0)      -- leave the machine as the guest expects to find it
  return p
end

-- how many bytes of a plane differ from `want` (a half of the frame file), and the
-- first one that does.  `only_bit7` is the attribute plane's own comparison, which
-- is the only one the hardware permits.
local function compare(plane, want, base, only_bit7)
  local n, first, got, exp = 0, nil, nil, nil
  for a = 0, PLANE - 1 do
    local g = plane[a]
    local w = string.byte(want, base + a + 1)
    if only_bit7 then g, w = g & 0x80, w & 0x80 end
    if g ~= w then
      n = n + 1
      if not first then first, got, exp = a, g, w end
    end
  end
  return n, first, got, exp
end

local function first_mismatch(plane, want, base)
  for a = 0, PLANE - 1 do
    if plane[a] ~= string.byte(want, base + a + 1) then return a end
  end
  return nil
end

local function row_text(plane, r)
  local t = {}
  for c = 0, STRIDE - 1 do
    local b = plane[r * STRIDE + c] % 128
    t[#t + 1] = (b >= 32 and b < 127) and string.char(b) or " "
  end
  return (table.concat(t):gsub("%s+$", ""))
end

local function run()
  assert(FRAME, "o1next-bootscreen.lua: set O1_FRAME to the boot frame")
  local frame = slurp(FRAME)
  local splash = SPLASH and slurp(SPLASH) or nil

  logf("the boot screen, read off the machine")
  logf("  monitor: ROM 2.0's, in the softROM window -- its sign-on stub is the caller")
  logf(string.format("  frame:   %s (%d bytes)", FRAME, #frame))
  logf("  splash:  " .. (splash and string.format("%s (%d bytes)", SPLASH, #splash)
                        or "<none -- the stub prints the stock sign-on instead>"))
  logf("  expect:  " .. EXPECT)
  logf("")

  -- The splash is drawn at the sign-on, before the machine waits for a key, and
  -- then nothing writes the planes: it sits at the prompt for ever, because no key
  -- is posted.  Poll for the frame rather than sleeping, so the report can say when
  -- it landed -- and so a machine that never draws it fails on the planes rather
  -- than on a stopwatch.
  if EXPECT == "splash" then
    local landed, waited = false, 0
    while waited < 15 do
      if not first_mismatch(chars(), frame, 0) then
        landed = true
        break
      end
      emu.wait(0.25)
      waited = waited + 0.25
    end
    logf(string.format("the frame's characters are on the character plane after %s " ..
                       "emulated seconds", landed and string.format("%.2f", waited)
                       or "15.00 (they never were)"))
  else
    emu.wait(3)   -- no splash: the fallback text, and then the prompt
    logf("no splash is mounted, so the stub takes its fallback: the stock sign-on is " ..
         "what this run expects to find")
  end
  logf("")

  local ch = chars()
  local at = attrs()

  logf("the character plane (OUT 03h, then F000h-FFFFh), the first 8 of 32 rows:")
  for r = 0, 7 do logf("  |" .. row_text(ch, r) .. "|") end
  logf("")

  if EXPECT == "splash" then
    local n, first, got, want = compare(ch, frame, 0, false)
    check(n == 0, "the character plane holds the frame's character half (4096 bytes)",
          first and string.format("+%04X is %02X, expected %02X; %d byte(s) differ",
                                  first, got, want, n))
    local an, afirst, agot, awant = compare(at, frame, PLANE, true)
    check(an == 0, "the attribute plane holds the frame's attribute half, bit 7 (the ninth bit)",
          afirst and string.format("+%04X is %02X, expected %02X (bit 7); %d byte(s) differ",
                                   afirst, agot, awant, an))
    -- and the six cells that make that comparison a measurement rather than a
    -- tautology: the frame's own attribute trailer at 0FF8h is dim, and the bright
    -- fill on its own leaves those same cells lit.
    local dim = 0
    for a = 0xff8, 0xffd do if (at[a] & 0x80) == 0 then dim = dim + 1 end end
    check(dim == 6, string.format("the frame's attribute trailer at 0FF8h is on the plane, " ..
                                  "dim (%d of 6)", dim))
  else
    local n = compare(ch, frame, 0, false)
    check(n > 0, "the frame is not on the screen -- the stub printed the stock sign-on instead")
    local ink = 0
    for a = 0, PLANE - 1 do if ch[a] ~= 0x20 then ink = ink + 1 end end
    check(ink >= 16, string.format("and the screen is not blank: %d cells are not spaces", ink))
  end

  logf("")
  if fails == 0 then
    logf("SCREEN: PASS -- the boot screen is on the machine, read off the two planes")
  else
    logf("SCREEN: FAIL -- " .. fails .. " check(s) failed")
  end
  os.exit(fails == 0 and 0 or 1)
end

local done = false
emu.register_frame_done(function()
  if done then return end
  done = true
  run()
end)
