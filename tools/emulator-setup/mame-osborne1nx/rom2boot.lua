-- rom2boot.lua -- what ROM 2.0's HCBOOT does, measured in the machine (#247).
--
-- WHY THIS EXISTS
--   ROM 2.0's monitor fills in HCBOOT -- the entry the monitor takes when ESC is
--   pressed at the sign-on prompt -- with the ACB-4000 cold boot: the CBIOS and
--   the MD-10 BIOS come out of the softROM's window into RAM, the MD-10 BIOS is
--   patched with the CBIOS's vectors, and the machine hands over to it
--   (docs/o1-rom-2.0.md 4.6).  That is a *chain*, and a boot comparison cannot
--   see it: this reads each stage back.
--
--   It also records the chain's current limit honestly.  What the ROM does is
--   complete; what happens after it is not, and the harness says where the
--   machine ends up rather than pretending the boot finished.
--
-- Run it as a *standalone* -autoboot_script, with the image mounted:
--
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -harddisk /tmp/md10/hd.chd -autoboot_script rom2boot.lua -seconds_to_run 40
--
-- Environment:
--   O1_ROM2_DRIVE  set when a hard disk is mounted, to also check that the system
--                  is read off it into 0xC200
--
-- ESC is not ASCII 27 on this machine.  The Osborne's ESC key is declared
-- `PORT_CHAR(UCHAR_MAMEKEY(ESC))`, so `natkeyboard:post("\27")` matches no port
-- and presses nothing -- see o1keys.lua's `key esc`, which had the same bug.  The
-- code that does press it is read out of the natkeyboard's own table here, rather
-- than hard-coded, so it survives a MAME that numbers its key codes differently.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local kb = M.natkeyboard
local VRAM, STRIDE = 0xF000, 128

local WINDOW = 0x1000          -- the softROM's window, bank 2 only
local CBIOS, CBIOS_LEN = 0xE100, 2048
local MD10, MD10_LEN = 0xD800, 1477
local CCP = 0xC200
local PATCHES = { {0xE106, 0xD806, 0x12}, {0xE118, 0xD86A, 0x15},
                  {0xE12D, 0xD82D, 0x03}, {0xE130, 0xD87F, 0x03},
                  {0xE133, 0xD833, 0x2D} }

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
local function peek(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", P:read_u8(a + i)) end
  return table.concat(t, " ")
end
-- Write 5A to 1000h and read it back: RAM mode keeps it, ROM mode does not, and
-- 1000h is the one address that tells them apart without touching the guest.
local function bank()
  local before = P:read_u8(WINDOW)
  P:write_u8(WINDOW, 0x5A)
  local after = P:read_u8(WINDOW)
  P:write_u8(WINDOW, before)
  return (after == 0x5A) and "RAM" or "ROM"
end
local function esc_code()
  for line in kb:dump():gmatch("[^\n]+") do
    local code, name = line:match("^([0-9A-F]+) %((.-)%)")
    if name == "Escape" then return tonumber(code, 16) end
  end
end
local function same(a, b, n)
  for i = 0, n - 1 do
    if P:read_u8(a + i) ~= P:read_u8(b + i) then return false, i end
  end
  return true
end
-- The MD-10 BIOS is copied *and then patched*, so it is only equal to its source
-- outside the slots the patch writes.
local function patched_range(off)
  for _, p in ipairs(PATCHES) do
    if off >= (p[2] - MD10) and off < (p[2] - MD10) + p[3] then return true end
  end
  return false
end
local function same_unpatched(a, b, n)
  for i = 0, n - 1 do
    if not patched_range(i) and P:read_u8(a + i) ~= P:read_u8(b + i) then return false, i end
  end
  return true
end

logf("ROM 2.0's HCBOOT, measured in the machine")
logf("  sign-on: " .. tostring(wait_for("Insert disk", 25)))

local esc = esc_code()
logf(string.format("  ESC is natkeyboard code %s", esc and string.format("%06X", esc) or "NOT FOUND"))
if not esc then os.exit(1) end

local ram_seen = false
kb:post(utf8.char(esc))
for i = 1, 40 do
  emu.wait(0.05)
  if bank() == "RAM" then ram_seen = true end
end
emu.wait(4)

logf("")
logf("the chain the ROM runs:")
-- The window is visible here (bank 2), and so is the RAM above 3FFFh, so the
-- copies are checked against their *source* rather than against bytes typed in.
verdict("the CBIOS is at 0E100h, and it is the window's 1000h",
        (same(CBIOS, WINDOW, CBIOS_LEN)))
-- The MD-10 BIOS *runs* after it lands and uses its own RAM cells (its parameter
-- block, its CDB), so comparing all 1477 bytes against the window's copy after
-- the fact is not meaningful.  What is checked is that it is there -- its own two
-- vectors, which the patch does not touch -- and that the patch landed.
verdict("the MD-10 BIOS's own jump table is at 0D800h",
        (same(MD10, WINDOW + 0x800, 6)))
local patched = true
for _, p in ipairs(PATCHES) do
  local ok = same(p[2], p[1], p[3])
  patched = patched and ok
end
verdict("it is patched from the CBIOS's vectors (5 LDIRs, 90 bytes)", patched)
verdict("the bank switched to RAM at some point after ESC (observed: " ..
        tostring(ram_seen) .. ")", ram_seen)
if os.getenv("O1_ROM2_DRIVE") then
  verdict("the system was read off the drive into 0C200h",
          (P:read_u8(CCP) == 0xC3))
end

logf("")
logf("  page zero   " .. peek(0, 8) .. "   (in bank 2 this is the ROM, not RAM)")
logf("  0E100       " .. peek(CBIOS, 8))
logf("  0D800       " .. peek(MD10, 8))
logf("  0C200       " .. peek(CCP, 8))
logf("  bank now    " .. bank())
logf(string.format("  CCPADR      %04X   (must be CB00h -- see docs/o1-rom-2.0.md 8.10)",
                   P:read_u8(0xEFD2) + P:read_u8(0xEFD3) * 256))
logf(string.format("  ROMRAM      %02X", P:read_u8(0xEF08)))

logf("")
if find("A0>") then
  logf("BOOT: A0> -- ROM 2.0 booted the hard disk")
else
  logf("BOOT: no A0>.  The chain above is what the ROM does; the hand-over is one")
  logf("  store short.  Measured: CCPADR (0EFD2h) is 0000h, so the 60 Hz handler's")
  logf("  return-to-RAM exit (ROMJP1 = CCPADR+1633h) lands on 1633h -- the softROM's")
  logf("  page 1, the payload's own copy of the CBIOS's console dispatch -- and that")
  logf("  reads IOBYTE from a page zero that in ROM mode is the ROM (D3h, the IEEE")
  logf("  device), so the machine waits in the ROM's IEEE routine for ever.")
  logf("  The fix is proved before it is built: rom2handover.lua pokes")
  logf("  CCPADR=CB00h into RAM after the hand-over and the machine reaches A0>.")
  logf("  See docs/o1-rom-2.0.md 4.6 and 8 item 10.")
end
logf(string.format("ROM2BOOT: %s", (fail == 0) and "the chain is complete" or "CHAIN INCOMPLETE"))
os.exit(fail == 0 and 0 or 1)
