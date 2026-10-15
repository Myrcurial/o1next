-- o1next-softrom.lua -- headless check of the softROM window (#247).
--
-- The window is 8 KB -- 0000-1FFF -- because the mainboard never decoded A12:
-- the stock machine reads its 4 KB monitor twice across it (docs/o1-rom-2.0.md
-- section 4.1b).  The interposer decodes A12, so page 0 is the monitor and page
-- 1 is the payload, and this is the check that the machine really is reading
-- the softROM rather than the ROM region behind it -- which a boot comparison
-- alone cannot tell you, because the stock monitor never reads page 1.
--
-- Run it as a *standalone* -autoboot_script:
--
--   SDL_VIDEODRIVER=dummy O1_SOFTROM_MONITOR=research/roms/os1-144.rom \
--     mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -autoboot_script o1next-softrom.lua \
--     -seconds_to_run 2
--
-- Environment:
--   O1_SOFTROM_MONITOR  the stock monitor image, 4 KB (required)
--   O1_SOFTROM_IMAGE    the image mounted with -softrom; absent means none is
--   O1_SOFTROM_DUMP     write the 8 KB window here, for the record
--
-- It reads the window back and compares it, byte for byte, against what the
-- device says it should be:
--
--   no image         the monitor, mirrored across the window (A12 ignored)
--   4 KB or less     the image, mirrored -- the image *is* the stock part
--   larger           both pages: 0000-0fff from the image, 1000-1fff from it
--                    too, and past the image's end the erased flash, 0xff
--
-- and prints SOFTROM: PASS or SOFTROM: FAIL.  It is the pass/fail half of
-- softrom-check.sh's two-way acceptance; the boot comparison is the other half.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local I = M.devices[":maincpu"].spaces["io"]

local WINDOW, STOCK = 0x2000, 0x1000
local MONITOR = os.getenv("O1_SOFTROM_MONITOR")
local IMAGE = os.getenv("O1_SOFTROM_IMAGE")
local DUMP = os.getenv("O1_SOFTROM_DUMP")

io.stdout:setvbuf("no")
local function logf(s)
  print(s)
  io.stdout:flush()
end

local function slurp(path)
  local f = assert(io.open(path, "rb"), "no such file: " .. path)
  local d = f:read("a")
  f:close()
  return d
end

local function hex(s, n)
  local t = {}
  for i = 1, n do t[#t + 1] = string.format("%02X", string.byte(s, i)) end
  return table.concat(t, " ")
end

local done = false
local function check()
  if done then return end
  done = true

  assert(MONITOR, "o1next-softrom.lua: set O1_SOFTROM_MONITOR to the 4 KB monitor")
  local monitor = slurp(MONITOR)
  assert(#monitor == STOCK, "o1next-softrom.lua: the monitor must be 4096 bytes")

  -- the window lives in bank 2, and the machine boots there
  I:write_u8(0x00, 0)

  local win = {}
  for a = 0, WINDOW - 1 do win[a] = P:read_u8(a) end

  if DUMP then
    local f = assert(io.open(DUMP, "wb"))
    for a = 0, WINDOW - 1 do f:write(string.char(win[a])) end
    f:close()
    logf(string.format("WINDOW-DUMP: %s (%d bytes)", DUMP, WINDOW))
  end

  -- what the window should be, per softrom.h
  local image = IMAGE and slurp(IMAGE) or nil
  local expected, what
  if not image then
    what = "no image: the monitor, mirrored (A12 ignored)"
    expected = function(a) return string.byte(monitor, (a % STOCK) + 1) end
  elseif #image <= STOCK then
    what = string.format("a %d-byte image: the stock part, mirrored", #image)
    expected = function(a) return string.byte(image, (a % STOCK) + 1) end
  else
    what = string.format("a %d-byte image: two pages, 0xff past its end", #image)
    expected = function(a)
      return (a < #image) and string.byte(image, a + 1) or 0xff
    end
  end

  logf(string.format("window: %s", what))
  logf(string.format("  page 0 (0000): %s", hex(string.char(win[0], win[1], win[2], win[3],
    win[4], win[5], win[6], win[7]), 8)))
  logf(string.format("  page 1 (1000): %s", hex(string.char(win[0x1000], win[0x1001], win[0x1002],
    win[0x1003], win[0x1004], win[0x1005], win[0x1006], win[0x1007]), 8)))
  logf(string.format("  page 1 top (1ff8): %s   %s", hex(string.char(win[0x1ff8], win[0x1ff9],
    win[0x1ffa], win[0x1ffb], win[0x1ffc], win[0x1ffd], win[0x1ffe], win[0x1fff]), 8),
    (win[0x1000] == win[0]) and "page 1 mirrors page 0" or "page 1 is its own page"))

  local bad, first = 0, nil
  for a = 0, WINDOW - 1 do
    if win[a] ~= expected(a) then
      bad = bad + 1
      if not first then
        first = a
        logf(string.format("  first mismatch at %04X: window %02X, expected %02X",
          a, win[a], expected(a)))
      end
    end
  end

  if bad == 0 then
    logf(string.format("SOFTROM: PASS -- all %d bytes of the window are what the device says", WINDOW))
  else
    logf(string.format("SOFTROM: FAIL -- %d of %d bytes differ, first at %04X",
      bad, WINDOW, first))
  end
  os.exit(bad == 0 and 0 or 1)
end

emu.register_frame_done(function() check() end)
