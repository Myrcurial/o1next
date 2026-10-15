-- rom2drives.lua -- A0> .. N0>, a file on each, and each drive's own ALV (#247).
--
-- WHY THIS EXISTS
--   rom2boot.lua proves the *chain* -- the ROM's HCBOOT, the CBIOS, the MD-10
--   BIOS, the hand-over -- and, with a drive, that the machine reaches `A0>`.
--   That is one drive.  #247 step 6 grows the driver from three hard-disk
--   drives to N, and its acceptance is not "it boots": it is that **every**
--   drive exists, **each takes a write and reads it back**, and **each has its
--   own directory** -- which is the whole point of a per-drive allocation
--   vector.
--
--   So this presses `X:` for each drive, `SAVE`s a distinct file on it, `DIR`s
--   it back, and then reads the *machine's own ALVs* out of RAM through the
--   driver's per-drive table.  The ALV is the check that matters and it is the
--   one a screen cannot make: if two drives shared an ALV, both would boot, both
--   would list, and the second one's directory would silently be the first
--   one's.
--
--   And it reads the *card's* side too: the machine's own CDB at D9FA, whose
--   LBA is compared **byte by byte** against what the driver's own drive and
--   sector cells say it should be.  That is the check neither the screen nor a
--   RAM dump can make.  On 2026-10-15 the grown driver stored the CDB's LBA
--   bytes the wrong way round, so drive A:'s first sector was read as LBA
--   0x1400 instead of 0x0014: the machine booted, `A0>` appeared, every cell in
--   RAM matched the vendor's driver byte for byte, and `DIR A:` answered
--   `No file` because the card had been asked for the wrong sector.  Drive B:
--   *appeared* to work, because its swapped LBA landed in A:'s `E5h` tail --
--   self-consistent and wrong.  See `tools/research/md10dpb.py`'s `lba_routine`.
--
--   N is not an argument -- it is read from the driver's own type table at
--   DD5E, so the harness checks the driver that is actually in the machine.
--
-- Run it as a *standalone* -autoboot_script, with the image and a drive:
--
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -harddisk /tmp/md10/hd.chd -autoboot_script rom2drives.lua \
--     -seconds_to_run 120
--
--   O1_DRIVES_EXPECT  the drive count the driver is *supposed* to present; if
--                     set, a mismatch is a failure rather than a report.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local kb = M.natkeyboard
local VRAM, STRIDE = 0xF000, 128

local TYPE_BASE = 0xDD5E         -- the per-drive type byte table
local TABLE = 0xDD6E             -- the grown driver's per-drive table
local ENTRY = 5                  -- start(3) + ALV(2)
local DPH_CELL = 0xDD55
local ALV_DIR_BITS = 0xF0        -- AL0 = F0: four 8 KiB directory blocks

io.stdout:setvbuf("no")
local fail = 0
local function logf(s) print(s); io.stdout:flush() end
local function verdict(name, ok)
  logf(string.format("  %s  %s", ok and "PASS" or "FAIL", name))
  if not ok then fail = fail + 1 end
end
local function rows()
  local out = {}
  for r = 0, 31 do
    local s = {}
    for c = 0, STRIDE - 1 do
      local b = P:read_u8(VRAM + r * STRIDE + c) % 128
      s[#s + 1] = (b >= 32 and b < 127) and string.char(b) or " "
    end
    out[r] = (table.concat(s):gsub("%s+$", ""))
  end
  return out
end
local function find(pat)
  for _, line in pairs(rows()) do if line:find(pat, 1, true) then return true end end
  return false
end
local function wait_for(pat, t)
  local e = 0
  while e < t do if find(pat) then return true end; emu.wait(0.5); e = e + 0.5 end
  return false
end
-- The rows the machine printed *after* a command echo, and nothing else.
--
-- Two things this has to get right, and an earlier revision got both wrong.
-- A CP/M `DIR` row is `A: AA       DAT` -- the name and the extension are
-- separated by spaces and there is **no dot** -- so a listing can never be
-- matched on `AA.DAT`; it is matched on the doubled letter, which is why the
-- file name is the drive letter twice.  And the rows *above* the echo are the
-- previous drives' listings, so scoping the search to the rows below the echo
-- is what stops drive C:'s listing from passing for drive B:'s, and what stops
-- the isolation check from reading an old listing as a fresh leak.
local function rows_after(pat)
  local r, from = rows(), nil
  for i = 0, 31 do if r[i]:find(pat, 1, true) then from = i + 1 end end
  local out = {}
  if from then for i = from, 31 do out[#out + 1] = r[i] end end
  return out
end
local function listing_has(drive, what)
  for _, line in ipairs(rows_after(drive .. "0>DIR " .. drive .. ":")) do
    if line:find(what, 1, true) then return line end
  end
  return nil
end
local function letter(i) return string.char(65 + i) end
local function w(a) return P:read_u8(a) + P:read_u8(a + 1) * 256 end
local function alv_of(i) return w(TABLE + i * ENTRY + 3) end
-- A drive's partition start, from the driver's own table at DD6E: three bytes,
-- 24-bit, because eleven 7.5 MiB partitions end past a 16-bit LBA.
local function start_of(i)
  local o = TABLE + i * ENTRY
  return P:read_u8(o) + P:read_u8(o + 1) * 256 + P:read_u8(o + 2) * 65536
end
-- The LBA the machine last asked the card for, read back out of the machine's
-- own CDB at D9FA.  The card is a SCSI target, so the LBA is **big-endian** in
-- the READ(6)'s bytes 2 and 3: byte 2 at D9FC is LBA[15:8] and byte 3 at D9FD
-- is LBA[7:0].  A driver that stores them the other way round still boots and
-- still keeps every cell in RAM byte-identical to the vendor's -- it just asks
-- the card for a different sector, which is the defect this check exists to
-- catch: on 2026-10-15 the grown driver read drive A: as LBA 0x1400 instead of
-- 0x0014, so `DIR A:` answered `No file` (#247).
local function cdb_lba()
  return P:read_u8(0xD9FB) * 65536 + P:read_u8(0xD9FC) * 256
         + P:read_u8(0xD9FD)
end

logf("ROM 2.0's HCBOOT, N hard-disk drives (#247 step 6)")
logf("  sign-on: " .. tostring(wait_for("Insert disk", 25)))
emu.wait(1)
kb:post("\r")
local booted = wait_for("A0>", 60)
verdict("the machine booted the hard disk with no floppy (A0>)", booted)
if not booted then
  logf("  no A0>: the chain, not the drive count, is what failed -- run rom2boot.lua")
  logf("ROM2DRIVES: BOOT FAILED")
  os.exit(1)
end

-- N, read from the driver that is in the machine: the type table is
-- `00 01 .. 0(N-1)` and then the floppy types.
local n = 0
while n < 16 and P:read_u8(TYPE_BASE + n) == n do n = n + 1 end
local dph = w(DPH_CELL)
logf(string.format("  the driver: %d hard-disk drives, shared DPH at %04X",
                   n, dph))
if os.getenv("O1_DRIVES_EXPECT") then
  local want = tonumber(os.getenv("O1_DRIVES_EXPECT"))
  verdict(string.format("the driver presents %d drives, as the drive's label says",
                        want), n == want)
end
verdict("the floppies moved up behind the disk (drive " .. n .. " is type 80h)",
        P:read_u8(TYPE_BASE + n) == 0x80)

-- Every drive: select it, write a file, and read it back.  The name is the
-- drive letter *doubled* (`AA.DAT`), so a listing row can be matched on a
-- string the extension does not contain -- `DA` matched `DAT`, which is how an
-- earlier revision passed a drive nothing had been written to.
--
-- The last check is the one neither the screen nor a RAM dump can make: what
-- the *card* was asked for.  A byte-swapped LBA still boots and still leaves
-- every cell in RAM matching the vendor's driver's, so only the card's side can
-- see it.
logf("")
logf("a file on each drive, its own ALV, and the LBA the card was asked for:")
local alvs = {}
for i = 0, n - 1 do
  local L = letter(i)
  local name = L .. L
  kb:post(L .. ":\r")
  local at = wait_for(L .. "0>", 15)
  kb:post("SAVE 1 " .. L .. ":" .. name .. ".DAT\r")
  emu.wait(4)
  kb:post("DIR " .. L .. ":\r")
  emu.wait(4)
  local row = listing_has(L, name)
  local alv = alv_of(i)
  local first = P:read_u8(alv)
  alvs[i] = first
  verdict(string.format("%s0> exists, SAVE 1 %s:%s.DAT, DIR %s: lists it  "
                        .. "(ALV %04X = %02X)", L, L, name, L, alv, first),
          at and (row ~= nil) and (first & ALV_DIR_BITS) == ALV_DIR_BITS)
  -- And the card's side.  The driver keeps the drive and the sector it last
  -- worked with, so the LBA the card *should* have been asked for is
  -- start + sector, and the two bytes are checked **separately** -- byte 2 at
  -- D9FC is LBA[15:8] and byte 3 at D9FD is LBA[7:0].  That separation is the
  -- whole point: on 2026-10-15 the grown driver stored them the other way
  -- round, and on two of the three drives the resulting LBA happened to have
  -- equal bytes (0x3C3C, 0x7878), so the *value* looked right while the bytes
  -- were reversed.  Drive A:'s read did not, and this is what named the defect.
  local drv, sec = P:read_u8(0xD96F), w(0xD970)
  local want = start_of(drv) + sec
  local hi, lo = P:read_u8(0xD9FC), P:read_u8(0xD9FD)
  verdict(string.format("%s:'s read went to LBA %d, as the driver's cells say "
                        .. "(%d + %d; bytes %02X %02X)", L, cdb_lba(), start_of(drv),
                        sec, hi, lo),
          (hi == math.floor(want / 256) % 256) and (lo == want % 256))
end

-- The ALVs are the check a screen cannot make: N drives sharing one would all
-- list, and only the last one's directory would be real.
local distinct = {}
for i = 0, n - 1 do distinct[alv_of(i)] = true end
local count = 0
for _ in pairs(distinct) do count = count + 1 end
verdict(string.format("the %d drives have %d distinct ALVs", n, count), count == n)

-- And the *directory* of each is its own: a file written on drive i must not be
-- visible on drive i+1, which is the failure a shared ALV produces.
logf("")
local isolated = true
for i = 0, n - 2 do
  kb:post(letter(i + 1) .. ":\r")
  wait_for(letter(i + 1) .. "0>", 15)
  kb:post("DIR " .. letter(i + 1) .. ":\r")
  emu.wait(4)
  local row = listing_has(letter(i + 1), letter(i) .. letter(i))
  if row then
    isolated = false
    logf(string.format("  drive %s lists drive %s's file: %s",
                       letter(i + 1), letter(i), row))
  end
end
verdict("no drive lists another's file", isolated)

logf("")
logf("  ALVs, read through the driver's table at DD6E:")
for i = 0, n - 1 do
  logf(string.format("    %s0>  ALV %04X  %s", letter(i), alv_of(i),
                     string.format("%02X %02X", P:read_u8(alv_of(i)),
                                   P:read_u8(alv_of(i) + 1))))
end
logf(string.format("ROM2DRIVES: %s", (fail == 0) and "all drives hold"
                   or "DRIVE COUNT INCOMPLETE"))
os.exit(fail == 0 and 0 or 1)
