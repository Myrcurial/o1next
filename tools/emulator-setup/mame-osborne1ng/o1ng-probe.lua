-- o1ng-probe.lua -- headless check of the osborne1ng I/O decode and the card.
-- Written for #191; see docs/osborne1ng-machine.md.
--
-- Run it as a *standalone* -autoboot_script.  Do not fold it into o1keys.lua or
-- another harness: the taps go silent once a harness polls memory from Lua
-- (tools/research/acb4000.lua's gotchas), and a probe has to keep its own reads
-- and writes adjacent -- Lua runs between CPU timeslices, so a write and the
-- read that follows it in the same callback cannot be interleaved by the guest.
--
--   O1NG_LOG=/tmp/o1ng.log mame osborne1ng -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -autoboot_script o1ng-probe.lua \
--     -seconds_to_run 6
--
-- It answers three questions, in order:
--   1. does the mainboard's 2-bit decode still bank-switch (ports 00h-03h)?
--   2. does it still alias across the low port page, and does the card's window
--      at 30h-33h *not* alias onto it?
--   3. does the MD-10's presence probe read 04h at base+2?

local M = manager.machine
local cpu = M.devices[":maincpu"]
local P = cpu.spaces["program"]
local I = cpu.spaces["io"]

io.stdout:setvbuf("no")
local LOG = io.open(os.getenv("O1NG_LOG") or "/tmp/o1ng.log", "w")
local function logf(s)
  print(s)
  if LOG then LOG:write(s .. "\n"); LOG:flush() end
end

local done = false
local function probe()
  if done then return end
  done = true

  -- 1 and 2: bank switching, direct and through the alias.  The ROM is mapped
  -- over 0000-0FFF in bank 2 and RAM in bank 1, so a read of 0000 tells them
  -- apart without reaching into the driver.
  I:write_u8(0x00, 0)
  local rom = P:read_u8(0x0000)
  I:write_u8(0x01, 0)
  local ram = P:read_u8(0x0000)
  I:write_u8(0x05, 0)                       -- alias of 01h
  local alias05 = P:read_u8(0x0000)
  I:write_u8(0x3d, 0)                       -- alias of 01h, top of the page
  local alias3d = P:read_u8(0x0000)
  I:write_u8(0x00, 0)
  local rom_again = P:read_u8(0x0000)
  logf(string.format("bank: rom=%02X ram=%02X alias05=%02X alias3d=%02X rom_again=%02X",
    rom, ram, alias05, alias3d, rom_again))
  logf(string.format("  mainboard 2-bit decode preserved: %s",
    (ram == alias05 and ram == alias3d and rom ~= ram) and "yes" or "NO"))

  -- the card's window is the card's, not the bank switch's
  I:write_u8(0x01, 0)                       -- bank 1
  local before = P:read_u8(0x0000)
  I:write_u8(0x31, 0x8f)                    -- card control: must not bank-switch
  I:write_u8(0x33, 0xcf)
  local after = P:read_u8(0x0000)
  logf(string.format("card window: 30h-33h left the bank alone: %s (%02X/%02X)",
    (before == after) and "yes" or "NO", before, after))

  -- 3: the presence probe, byte for byte (docs/acb4000-host-adapter.md 1)
  I:write_u8(0x31, 0x8f)
  I:write_u8(0x31, 0x07)
  I:write_u8(0x33, 0xcf)
  I:write_u8(0x33, 0x6b)
  I:write_u8(0x33, 0x07)
  I:write_u8(0x32, 0x04)
  local data = I:read_u8(0x30)
  local status = I:read_u8(0x32)
  logf(string.format("presence probe: IN 30h=%02X  IN 32h=%02X  -> %s",
    data, status, (status == 0x04) and "one controller on-line" or "FAILED"))

  -- ... and the other half of the probe: clearing the register must read clear,
  -- which is what the overlays' good path tests (0x8244 in CNTLRCOD.OVL)
  I:write_u8(0x32, 0x00)
  local cleared = I:read_u8(0x32)
  logf(string.format("  register clears: IN 32h=%02X -> %s",
    cleared, (cleared == 0x00) and "yes" or "NO"))
end

emu.register_frame_done(function() probe() end)
