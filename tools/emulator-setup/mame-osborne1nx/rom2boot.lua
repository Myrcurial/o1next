-- rom2boot.lua -- what ROM 2.0's HCBOOT does, measured in the machine (#247).
--
-- WHY THIS EXISTS
--   ROM 2.0's monitor fills in HCBOOT -- the entry the monitor takes when RETURN
--   is pressed at the sign-on prompt (#247 step 4; docs/o1-rom-2.0.md 3.3) --
--   with the ACB-4000 cold boot: the CBIOS and the MD-10 BIOS come out of the
--   softROM's window into RAM, the MD-10 BIOS is patched with the CBIOS's
--   vectors, and the machine hands over to it (docs/o1-rom-2.0.md 4.6).  That is
--   a *chain*, and a boot comparison cannot see it: this reads each stage back.
--
--   It also records where the chain ends, and it is the machine's own interrupt
--   exit: the ROM's 60 Hz handler returns through the CBIOS at `CCPADR + 1633h`,
--   and `CCPADR` is the ROM's own `CBOOT`'s to write.  That store can only be
--   made from RAM, so `HCBOOT` copies a 14-byte stub out of the payload's spare,
--   switches the bank to it, and the stub makes the store.  So this checks the
--   chain *and* the prompt: with a drive mounted the machine has to reach `A0>`,
--   and without one there is no system to read and the chain is what the run is
--   about (docs/o1-rom-2.0.md 4.6, 8 item 10).
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
-- RETURN is the key, and it is a plain carriage return (#247 step 4).  ROM 2.0's
-- sign-on dispatch boots the machine's own hard disk on RETURN, `:` is floppy A
-- and `"` is floppy B, and ESC is released (docs/o1-rom-2.0.md 3.3).  The
-- dispatch's two key bytes are read back out of the running monitor below.  The
-- harness used to press ESC, which on this machine is a MAME *key* code and had
-- to be read out of the natkeyboard's own table (see o1keys.lua's `key esc`);
-- RETURN needs none of that.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local kb = M.natkeyboard
local VRAM, STRIDE = 0xF000, 128

local WINDOW = 0x1000          -- the softROM's window, bank 2 only
local CBIOS, CBIOS_LEN = 0xE100, 2048
local MD10, MD10_LEN = 0xD800, 1477
local CCP = 0xC200
local STUB_SRC, STUB = 0x1E01, 0xE0F0   -- the hand-over stub: window -> RAM
local STUB_LEN = 14
local CCPADR, CCPADR_VALUE = 0xEFD2, 0xCB00
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
-- The window is bank 2 only, and the bank follows the CPU: at the sign-on prompt
-- the monitor is running from the ROM, so the window is visible *then* -- and by
-- the end of a run that boots, the machine is running from RAM, where a read of
-- 1000h is a read of RAM.  So the chain's sources are snapshotted while they can
-- be read, and the copies in RAM are compared against the snapshots.
local function snapshot(addr, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = P:read_u8(addr + i) end
  return t
end
local function same_table(t, addr)
  for i = 1, #t do
    if t[i] ~= P:read_u8(addr + i - 1) then return false, i - 1 end
  end
  return true
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

-- Read the window now, while the bank is still the monitor's.  Everything the
-- chain copies is compared against these, not against the window at the end.
local e = 0
while e < 10 and bank() ~= "ROM" do emu.wait(0.5); e = e + 0.5 end
logf("  the bank at the sign-on prompt: " .. bank())
local win = { cbios = snapshot(WINDOW, CBIOS_LEN),
              md10  = snapshot(WINDOW + 0x800, 6),
              stub  = snapshot(STUB_SRC, STUB_LEN) }
logf("  the window: CBIOS " .. peek(WINDOW, 4) ..
     ", MD-10 " .. peek(WINDOW + 0x800, 4) ..
     ", stub " .. peek(STUB_SRC, STUB_LEN))

-- The key map itself, read out of the running monitor (#247 step 4).  Below
-- 0F67h these two immediates are the *only* bytes ROM 2.0 moves, and they are the
-- whole difference between "a facerolled RETURN boots a disk nobody asked for"
-- and the machine's own hard disk: 0047h/0048h is the `CMP` after `CALL CI`, and
-- 004Fh/0050h the one after `LD HL,DSKSWP`.  Read now, while the bank is the
-- monitor's.
local KEY_CR, KEY_COLON = 0x0D, 0x3A
verdict("the sign-on dispatch is ROM 2.0's key map (RETURN = the hard disk, " ..
        "':' = floppy A, '\"' = floppy B)",
        P:read_u8(0x0047) == 0xFE and P:read_u8(0x0048) == KEY_CR and
        P:read_u8(0x004F) == 0xFE and P:read_u8(0x0050) == KEY_COLON)

local ram_seen = false
kb:post("\r")
for i = 1, 40 do
  emu.wait(0.05)
  if bank() == "RAM" then ram_seen = true end
end
emu.wait(4)

logf("")
logf("the chain the ROM runs:")
-- The window was read at the sign-on prompt (bank 2); the RAM is live.
verdict("the CBIOS is at 0E100h, and it is the window's 1000h",
        (same_table(win.cbios, CBIOS)))
-- The MD-10 BIOS *runs* after it lands and uses its own RAM cells (its parameter
-- block, its CDB), so comparing all 1477 bytes against the window's copy after
-- the fact is not meaningful.  What is checked is that it is there -- its own two
-- vectors, which the patch does not touch -- and that the patch landed.
verdict("the MD-10 BIOS's own jump table is at 0D800h",
        (same_table(win.md10, MD10)))
local patched = true
for _, p in ipairs(PATCHES) do
  local ok = same(p[2], p[1], p[3])
  patched = patched and ok
end
verdict("it is patched from the CBIOS's vectors (5 LDIRs, 90 bytes)", patched)
verdict("the bank switched to RAM at some point after RETURN (observed: " ..
        tostring(ram_seen) .. ")", ram_seen)
-- The hand-over's own store, and the only part of the chain that has to run in
-- RAM: HCBOOT copies the stub out of the payload's spare and switches the bank
-- to it, and the stub writes the cell the ROM's 60 Hz exit adds 1633h to
-- (docs/o1-rom-2.0.md 4.6).  Without it the exit lands on 1633h and the machine
-- never comes back -- which is what rom2handover.lua proved by poking it.
verdict("the hand-over stub is in RAM at 0E0F0h, and it is the window's 1E01h",
        (same_table(win.stub, STUB)))
verdict(string.format("CCPADR (0EFD2h) is %04Xh, the store the ROM's own CBOOT "
                      .. "makes", CCPADR_VALUE),
        (P:read_u8(CCPADR) + P:read_u8(CCPADR + 1) * 256) == CCPADR_VALUE)
if os.getenv("O1_ROM2_DRIVE") then
  verdict("the system was read off the drive into 0C200h",
          (P:read_u8(CCP) == 0xC3))
end

logf("")
logf("  page zero   " .. peek(0, 8) .. "   (in bank 2 this is the ROM, not RAM)")
logf("  0E100       " .. peek(CBIOS, 8))
logf("  0D800       " .. peek(MD10, 8))
logf("  0C200       " .. peek(CCP, 8))
logf("  0E0F0       " .. peek(STUB, STUB_LEN) .. "   (the hand-over stub, in RAM)")
logf("  bank now    " .. bank())
logf(string.format("  CCPADR      %04X   (CB00h -- what the 60 Hz exit adds 1633h "
                   .. "to, docs/o1-rom-2.0.md 4.6)",
                   P:read_u8(CCPADR) + P:read_u8(CCPADR + 1) * 256))
logf(string.format("  ROMRAM      %02X", P:read_u8(0xEF08)))

logf("")
-- The prompt is the ROM's own business now that the hand-over is in it: with a
-- drive mounted there is a system to read, and the machine has to reach it.
local at_prompt = find("A0>")
if os.getenv("O1_ROM2_DRIVE") then
  verdict("the machine reached A0> -- the ROM booted the hard disk, no floppy",
          at_prompt)
  if not at_prompt then
    logf("  A drive is mounted, so there was a system to read and the machine did")
    logf("  not reach it.  The chain above says how far it got: the stub in RAM and")
    logf("  CCPADR are the hand-over, and the rest is the MD-10 BIOS's own boot")
    logf("  (docs/o1-rom-2.0.md 4.6, 8 item 10).")
  end
else
  logf("BOOT: no drive mounted, so the prompt is not checked -- there is no system")
  logf("  to read.  Mount one with O1_HARD to check the boot as well as the chain.")
  if at_prompt then logf("  (it reached A0> anyway)") end
end
logf(string.format("ROM2BOOT: %s", (fail == 0) and "the chain is complete" or "CHAIN INCOMPLETE"))
os.exit(fail == 0 and 0 or 1)
