-- o1ng-dataphase.lua -- headless check of the osborne1ng card's *data* phase.
-- Written for #191; see docs/osborne1ng-machine.md.
--
-- Run it as a *standalone* -autoboot_script with a drive image mounted.  The
-- card is an ACB-4000 host adapter; the SCSI target behind it is MAME's
-- SCSIHD, so the geometry this reports is the CHD's:
--
--   chdman createhd -o /tmp/md10/hd.chd -c none -chs 321,4,18 -ss 512
--   O1NG_LOG=/tmp/o1ng-dataphase.log mame osborne1ng \
--     -rompath tools/emulator-setup/roms -hard /tmp/md10/hd.chd \
--     -video none -sound none -window -nothrottle -seconds_to_run 6 \
--     -autoboot_script tools/emulator-setup/mame-osborne1ng/o1ng-dataphase.lua
--
-- `-window` matters on the mac OSD: `-video none` picks the renderer, not the
-- window, and MAME's default is full screen (docs/mame-emulation.md section 6).
--
--   O1NG_CHS=<c>,<h>,<s>   the geometry the mounted CHD carries (321,4,18)
--
-- WHY IT EXISTS
--   o1ng-probe.lua answers "is the decode right and does the card answer?".
--   This one answers the next question: "does a *transfer* work?" -- and it
--   answers it at the register level, so a failure is the card's and not the
--   driver's.  The MD-10 driver's own transaction routine is the model: it
--   selects, asserts CTRL_SELECT (10h), releases it, sends the CDB one byte per
--   REQ while PHASE is set, moves the data, and then reads the status byte,
--   waits for END, and reads the register again to acknowledge (overlay
--   0x8030-0x80d1; the same routine is in HARDBIOS.SPR at 0xE285).
--
--   It drives all six commands the MD-10 actually issues: TEST UNIT READY,
--   INQUIRY, MODE SENSE page 4 (geometry) and page 3 (format parameters),
--   READ CAPACITY and READ.  The first four are byte-at-a-time transfers and
--   READ is a 512-byte block, which is exactly the split the driver makes
--   (`opcode & 1fh`), so both paths through the card are exercised.
--
--   Do not fold this into o1keys.lua or another harness: Lua runs between CPU
--   timeslices, so a probe has to keep its own reads and writes adjacent.

local M = manager.machine
local cpu = M.devices[":maincpu"]
local I = cpu.spaces["io"]

io.stdout:setvbuf("no")
local LOG = io.open(os.getenv("O1NG_LOG") or "/tmp/o1ng-dataphase.log", "w")
local function logf(s) print(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end

-- the card's four registers, relative to the base port the MD-10 uses (30h)
local BASE = 0x30
local function status_r() return I:read_u8(BASE + 2) end
local function data_r()   return I:read_u8(BASE + 0) end
local function data_w(v)  I:write_u8(BASE + 0, v) end
local function ctrl_w(v)  I:write_u8(BASE + 2, v) end

local STATUS_SELECT, STATUS_REQ, STATUS_PHASE, STATUS_END = 0x01, 0x02, 0x20, 0x40
local CTRL_SELECT = 0x10

local checks, failures = 0, 0
local function check(what, ok, detail)
  checks = checks + 1
  if not ok then failures = failures + 1 end
  logf(string.format("  %-4s %s%s", ok and "ok" or "FAIL", what, detail and (" -- " .. detail) or ""))
end

-- One transaction, following the driver's routine step for step.
--   cdb  the command descriptor block
--   cap  a ceiling on bytes read in the data phase, so a card that never ends
--        the phase shows up as "CAP HIT" rather than as a hung probe
-- Returns the data bytes, the status byte, and whether the phase ended.
local function transaction(cdb, cap)
  local out, guard = {}, 0

  -- 1. select: wait for the handshake to clear, write the select byte, assert
  --    CTRL_SELECT, wait for the card to answer, then release it
  while (status_r() & STATUS_SELECT) ~= 0 and guard < 100000 do guard = guard + 1 end
  data_w(0x01)                        -- one-of-eight ID mask: controller 01 = SCSI ID 0
  ctrl_w(CTRL_SELECT)
  guard = 0
  while (status_r() & STATUS_SELECT) == 0 and guard < 100000 do guard = guard + 1 end
  ctrl_w(0x00)                        -- the command phase starts

  -- 2. command phase: one CDB byte per REQ while PHASE is set
  local i, sent, g = 1, 0, 0
  while g < 100000 do
    g = g + 1
    local s = status_r()
    if (s & STATUS_END) ~= 0 then break end
    if (s & STATUS_REQ) ~= 0 and (s & STATUS_PHASE) ~= 0 then
      data_w(cdb[i]); i = i + 1; sent = sent + 1
    end
  end

  -- 3. data phase: read while REQ is set, until PHASE says we are in status
  local n, g2 = 0, 0
  while n < cap and g2 < 1000000 do
    g2 = g2 + 1
    local s = status_r()
    if (s & STATUS_PHASE) ~= 0 and (s & STATUS_END) ~= 0 then break end
    if (s & STATUS_REQ) ~= 0 then out[#out + 1] = data_r(); n = n + 1 end
  end

  -- 4. status phase: the status byte, wait for END, then acknowledge
  local status = data_r()
  g = 0
  while (status_r() & STATUS_END) == 0 and g < 100000 do g = g + 1 end
  data_r()

  return out, status, sent, (n < cap)
end

local function u32be(t, i)
  return t[i + 1] * 0x1000000 + t[i + 2] * 0x10000 + t[i + 3] * 0x100 + t[i + 4]
end
local function hex(t, n)
  local s = {}
  for k = 1, math.min(#t, n or 16) do s[#s + 1] = string.format("%02X", t[k]) end
  return table.concat(s, " ")
end

local done = false
emu.register_frame_done(function()
  if done then return end
  done = true

  local chs = os.getenv("O1NG_CHS") or "321,4,18"
  local cyl, hd, sec = chs:match("^(%d+),(%d+),(%d+)$")
  cyl, hd, sec = tonumber(cyl), tonumber(hd), tonumber(sec)
  logf(string.format("mounted geometry (O1NG_CHS): %d/%d/%d, 512-byte sectors", cyl, hd, sec))

  -- TEST UNIT READY: no data phase at all -- the shortest path through the card
  logf("TEST UNIT READY (00)")
  local d, st, sent, ended = transaction({0x00, 0, 0, 0, 0, 0}, 8)
  check("6 CDB bytes sent", sent == 6, "sent " .. sent)
  check("no data phase", #d == 0, #d .. " bytes")
  check("status GOOD", st == 0x00, string.format("%02X", st))

  -- INQUIRY: 36 bytes, byte-at-a-time
  logf("INQUIRY (12)")
  d, st, sent = transaction({0x12, 0, 0, 0, 36, 0}, 600)
  check("36 bytes, phase ended", #d == 36 and ended, string.format("%d bytes", #d))
  check("status GOOD", st == 0x00, string.format("%02X", st))
  check("direct-access device", d[1] == 0x00 and d[2] == 0x00, hex(d, 8))
  local vendor = {}
  for k = 9, 36 do vendor[#vendor + 1] = string.char(d[k] % 128) end
  logf("    vendor/product: " .. (string.gsub(table.concat(vendor), "%s+$", "")))

  -- MODE SENSE page 4: the rigid-disk geometry the DPB is built from
  logf("MODE SENSE (1A), page 4 -- geometry")
  d, st = transaction({0x1a, 0, 0x04, 0, 64, 0}, 600)
  check("page 4 returned, phase ended", d[13] == 0x04 and ended, hex(d, 20))
  check("status GOOD", st == 0x00, string.format("%02X", st))
  local rcyl = d[15] * 0x10000 + d[16] * 0x100 + d[17]
  local rhd = d[18]
  check("cylinders match the CHD", rcyl == cyl, rcyl .. " vs " .. cyl)
  check("heads match the CHD", rhd == hd, rhd .. " vs " .. hd)
  check("rotation rate 3600", d[33] * 0x100 + d[34] == 3600, (d[33] * 0x100 + d[34]) .. " rpm")

  -- MODE SENSE page 3: format parameters (sectors/track, bytes/sector)
  logf("MODE SENSE (1A), page 3 -- format parameters")
  d, st = transaction({0x1a, 0, 0x03, 0, 64, 0}, 600)
  check("page 3 returned, phase ended", d[13] == 0x03 and ended, hex(d, 20))
  check("status GOOD", st == 0x00, string.format("%02X", st))
  local rsec = d[23] * 0x100 + d[24]
  local rbps = d[25] * 0x100 + d[26]
  check("sectors/track match the CHD", rsec == sec, rsec .. " vs " .. sec)
  check("512 bytes/sector", rbps == 512, rbps .. " bytes")
  check("soft-sectored", (d[33] & 0x80) ~= 0, string.format("format %02X", d[33]))

  -- READ CAPACITY: 8 bytes, byte-at-a-time
  logf("READ CAPACITY (25)")
  d, st = transaction({0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 600)
  check("8 bytes, phase ended", #d == 8 and ended, #d .. " bytes")
  check("status GOOD", st == 0x00, string.format("%02X", st))
  local last, bsize = u32be(d, 0), u32be(d, 4)
  check("last LBA = c*h*s - 1", last + 1 == cyl * hd * sec, last + 1 .. " vs " .. (cyl * hd * sec))
  check("block size 512", bsize == 512, bsize .. " bytes")

  -- READ: the one command the driver moves in 512-byte blocks
  logf("READ (08), LBA 0, 1 block")
  d, st = transaction({0x08, 0, 0, 0, 1, 0}, 600)
  check("512 bytes, phase ended", #d == 512 and ended, #d .. " bytes")
  check("status GOOD", st == 0x00, string.format("%02X", st))

  logf(string.format("%d checks, %d failed -- %s",
    checks, failures, (failures == 0) and "DATA PHASE OK" or "DATA PHASE FAILED"))
end)
