-- o1next-bootscreen.lua -- ROM 2.0's boot screen, read back off the machine
-- (#247 step 8; rewritten for #278).
--
-- WHY THIS EXISTS
--   ROM 2.0's monitor calls its screen code at the sign-on prompt -- `rom2.diff`
--   replaces the stock `LDK DE,IMSG` + `CALL OSTR` with `CALL SCRN` -- and that
--   code fills the attribute array bright, prints the fallback and returns.  The
--   *result* is what this reads: the two video planes, back off the machine.
--
--   And the fallback is not decoration.  Since #278 the ROM serves no frame and
--   draws none: the RP2354B is the display, it plays the animation out of its own
--   flash, and it stops on the Z80's first video-RAM write.  The Z80's whole role
--   is the *trigger*, and the trigger is this text -- so the two lines, their
--   columns and their three dim runs are checked here by value, and they are the
--   one thing the frame path's retirement must not disturb
--   (docs/rom-pico-protocol.md 5.1, docs/o1-rom-2.0.md 4.9).
--
-- THE TWO PLANES ARE ONE ADDRESS
--   The ninth video bit is a separate 4Kx1 array paged over the video RAM by
--   `OUT (02h)`, and `OUT (03h)` puts the character RAM back -- the stock
--   monitor's own macros `ENADIM` and `DISDIM` (rom144.asm), and
--   `bankswitch_w`'s offsets 2 and 3.  So both planes are read at F000h-FFFFh,
--   one at a time, with the same two writes the guest itself makes.
--
-- AND THE FILL IS PART OF THE TRIGGER
--   24 of the array's 4096 cells read 7Fh (dim) at the sign-on, so the code fills
--   every cell bright before it prints.  The dim cells this run finds must
--   therefore be *exactly* the fallback's own runs -- and their total is checked,
--   which is how the fill's own 15-cell shortfall was found on 2026-10-17.
--
-- Run it as a *standalone* -autoboot_script, with the ROM 2.0 image mounted:
--
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -autoboot_script o1next-bootscreen.lua -seconds_to_run 30
--
-- **No flash assets are mounted, and there are none left to mount (#278).**  The
-- `-frame` and `-bootsplash` slots went with the ROM-side frame path: the monitor
-- runs its own 26 bytes of screen code, out of the tail where the stub used to be,
-- and the only thing that draws a picture on the real machine is the RP2354B.
--
-- It prints SCREEN: PASS or SCREEN: FAIL, and exits 0 or 1.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local I = M.devices[":maincpu"].spaces["io"]

local VRAM, PLANE, STRIDE = 0xf000, 0x1000, 128
local OUT_ATTRS, OUT_CHARS = 0x02, 0x03    -- ENADIM / DISDIM (rom144.asm)

io.stdout:setvbuf("no")
local fails = 0
local function logf(s) print(s) ; io.stdout:flush() end

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

local function row_text(plane, r)
  local t = {}
  for c = 0, STRIDE - 1 do
    local b = plane[r * STRIDE + c] % 128
    t[#t + 1] = (b >= 32 and b < 127) and string.char(b) or " "
  end
  return (table.concat(t):gsub("%s+$", ""))
end

local function run()
  logf("the boot screen, read off the machine")
  logf("  monitor: ROM 2.0's, in the softROM window -- its sign-on hook is the caller")
  logf("  assets:  none mounted, and none to mount: the monitor's own code draws this")
  logf("")

  -- The screen code runs at the sign-on, before the machine waits for a key, and
  -- then nothing writes the planes: the machine sits at the prompt for ever,
  -- because no key is posted.
  emu.wait(6)

  local ch = chars()
  local at = attrs()

  logf("the character plane (OUT 03h, then F000h-FFFFh), the first 8 of 32 rows:")
  for r = 0, 7 do logf("  |" .. row_text(ch, r) .. "|") end
  logf("... and the two rows the fallback writes:")
  for r = 20, 22 do logf("  |" .. row_text(ch, r) .. "|") end
  logf("")

  -- #247's W3, and the trigger: the screen code's own fallback, at the animation's
  -- own rows and columns and with the animation's own bright/dim runs.
  local L1, L1C = "osborne 1 next rom 2.0 2026", 24
  local L2, L2C = "press return to begin", 30
  for _, spec in ipairs({ { 20, L1, L1C }, { 22, L2, L2C } }) do
    local r, want, col = spec[1], spec[2], spec[3]
    local got = {}
    for c = col, col + #want - 1 do
      got[#got + 1] = string.char(ch[r * STRIDE + c] % 128)
    end
    got = table.concat(got)
    check(got == want,
          string.format("row %d carries the screen's own line |%s|", r, want),
          got ~= want and ("got |" .. got .. "|") or nil)
  end
  local stray = 0
  for r = 0, 31 do
    for c = 0, STRIDE - 1 do
      local b = ch[r * STRIDE + c] % 128
      if b ~= 32 and b ~= 0 then
        local mine = (r == 20 and c >= L1C and c < L1C + #L1)
                  or (r == 22 and c >= L2C and c < L2C + #L2)
        if not mine then stray = stray + 1 end
      end
    end
  end
  check(stray == 0, "the two lines are the whole screen -- no other ink",
        stray .. " stray cell(s)")

  -- the dim runs, and only them.  The bright fill covers all 4096 cells, so a dim
  -- cell anywhere else is a defect -- which is how the fill's own 15-cell
  -- shortfall was found (2026-10-17).
  local DIM = { { 20, 39, 50 }, { 22, 30, 34 }, { 22, 43, 50 } }
  local want, dimtotal = 0, 0
  for _, d in ipairs(DIM) do want = want + (d[3] - d[2] + 1) end
  for a = 0, PLANE - 1 do if (at[a] & 0x80) == 0 then dimtotal = dimtotal + 1 end end
  check(dimtotal == want,
        string.format("exactly the fallback's %d dim cells and no others -- the "
                      .. "bright fill is all 4096", want), dimtotal .. " dim cell(s)")
  for _, d in ipairs(DIM) do
    local bad = 0
    for c = d[2], d[3] do if (at[d[1] * STRIDE + c] & 0x80) ~= 0 then bad = bad + 1 end end
    check(bad == 0, string.format("row %d cols %d-%d is dim", d[1], d[2], d[3]),
          bad .. " bright")
  end
  check((at[20 * STRIDE + 38] & 0x80) ~= 0,
        "row 20 col 38 is bright, so the dim run really starts at 39")

  logf("")
  if fails == 0 then
    logf("SCREEN: PASS -- the fallback is on the machine, read off the two planes")
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
