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
-- The last screen row holding `pat` -- a DIR listing is the newest thing on
-- screen, and the listings above it are older drives'.  A *command echo* also
-- holds the name (`A0>SAVE 1 A:AA.DAT`), so the echo is skipped: that is what
-- made an earlier revision of this harness pass a drive nothing was written to.
local function last_row_with(pat)
  local r, best = rows(), nil
  for i = 0, 31 do
    local line = r[i]
    if line:find(pat, 1, true) and not line:find("SAVE", 1, true)
       and not line:find("DIR ", 1, true) then best = line end
  end
  return best
end
local function letter(i) return string.char(65 + i) end
local function w(a) return P:read_u8(a) + P:read_u8(a + 1) * 256 end
local function alv_of(i) return w(TABLE + i * ENTRY + 3) end

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
logf("")
logf("a file on each drive, and the drive's own ALV:")
local alvs = {}
for i = 0, n - 1 do
  local L = letter(i)
  local name = L .. L .. ".DAT"
  kb:post(L .. ":\r")
  local at = wait_for(L .. "0>", 15)
  kb:post("SAVE 1 " .. L .. ":" .. name .. "\r")
  emu.wait(4)
  kb:post("DIR " .. L .. ":\r")
  emu.wait(4)
  local row = last_row_with(name)
  local alv = alv_of(i)
  local first = P:read_u8(alv)
  alvs[i] = first
  verdict(string.format("%s0> exists, SAVE 1 %s:%s, DIR %s: lists it  "
                        .. "(ALV %04X = %02X)", L, L, name, L, alv, first),
          at and (row ~= nil) and (first % 16) == (ALV_DIR_BITS % 16))
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
  local row = last_row_with(letter(i) .. letter(i) .. ".DAT")
  if row and row:find(letter(i) .. letter(i), 1, true) then
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
