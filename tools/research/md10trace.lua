-- md10trace.lua -- log every MD-10 host-adapter transaction, with the status byte.
-- Written for #198; see docs/md10-system.md section 7.
--
-- WHY THIS EXISTS
--   #198 was "the system boots but never reaches its prompt", and the reading of
--   it was a stalled drive login. This is the instrument that showed the reading
--   was wrong: it logs each transaction's select byte, its six CDB bytes, the
--   status transitions of the card's control register and the *status byte*, so
--   "is the read failing?" stops being a guess. The answer was that the READ of
--   LBA 5 succeeds -- 5632 bytes moved, status 00 -- and repeats byte for byte
--   1 303 times in 150 emulated seconds, which is a warm-boot loop and not a
--   login. The fault was above the card, in the operating system's relocation.
--
-- THE REGISTER MODEL (docs/osborne1ng-machine.md section 3)
--   base+0 data, base+2 control/status.  Status bits: 01h select handshake,
--   02h REQ, 04h the controller field, 20h phase, 40h the phase is complete.
--   A command is: write the select byte to base+0, write 10h to base+2
--   (assert), write 00h to base+2 (release), one CDB byte per REQ on base+0
--   until the status reads END, the data phase, then the status byte.
--
-- HOW IT IS DRIVEN
--   A *standalone* -autoboot_script, not through o1keys.sh: o1keys.lua's VRAM
--   polling silences the io taps (tools/research/acb4000.lua, GOTCHAS).  It
--   presses RETURN at the BIOS prompt, types HARD, and runs.
--
--     O1NG_LOG=/tmp/md10trace.log \
--       mame osborne1ng -rompath tools/emulator-setup/roms \
--         -flop1 /tmp/md10/u.imd -hard /tmp/md10/hd.chd \
--         -video none -sound none -nothrottle -seconds_to_run 160 \
--         -autoboot_script tools/research/md10trace.lua
--
--   O1NG_LOG overrides the log path (default /tmp/md10trace.log).
--
-- GOTCHAS (all measured, MAME 0.289)
--   * MAME's tap callbacks get the **absolute** io offset, not an offset within
--     the tap range.  An earlier version added the base port again and labelled
--     every access 0x60-0x63.
--   * The read tap must **not return a value** -- a read tap that returns data
--     segfaults once the guest polls in a tight loop (acb4000.lua, GOTCHAS).
--     It still segfaults eventually on a long run; keep the budget short, and
--     read the log rather than the exit status.
--   * Only the first 10 transactions are logged in full; after that the log
--     carries the status lines alone, which is what keeps it readable.

local M = manager.machine
local I = M.devices[":maincpu"].spaces["io"]
local kb = M.natkeyboard

io.stdout:setvbuf("no")
local LOG = io.open(os.getenv("O1NG_LOG") or "/tmp/md10trace.log", "w")
local function logf(s) LOG:write(s .. "\n"); LOG:flush() end

local state, sel, cdb = "idle", nil, {}
local run30, last32, expect_status, tx = 0, nil, false, 0

local function flush30()
  if run30 > 0 then
    if tx <= 10 then logf("R30 x" .. run30) end
    run30 = 0
  end
end

local function cdb_hex()
  local s = {}
  for i = 1, #cdb do s[#s + 1] = string.format("%02x", cdb[i]) end
  return table.concat(s, " ")
end

I:install_write_tap(0x30, 0x33, "md10w", function(off, v)
  flush30()
  if off == 0x30 then
    if state == "cmd" and #cdb < 6 then cdb[#cdb + 1] = v; return end
    sel = v
    tx = tx + 1
    if tx <= 10 then logf(string.format("SEL %02x", v)) end
  elseif off == 0x32 then
    if v == 0x10 then state = "assert"
    elseif v == 0x00 and state == "assert" then state, cdb = "cmd", {}
    elseif tx <= 10 then logf(string.format("W32 %02x", v)) end
  elseif tx <= 10 then
    logf(string.format("W%02X %02x", off, v))
  end
end)

I:install_read_tap(0x30, 0x33, "md10r", function(off, data)
  if off == 0x30 then
    run30 = run30 + 1
    if expect_status then
      expect_status = false
      logf(string.format("  STATUS %02x   (tx %d, sel %02x, cdb %s)",
                         data, tx, sel or 0, cdb_hex()))
    end
    return
  end
  if off == 0x32 then
    if data ~= last32 then
      flush30()
      last32 = data
      if tx <= 10 then logf(string.format("R32 %02x", data)) end
      -- The status phase asserts 20h (phase) *and* 40h (complete), and it is a
      -- *change* of the register.  Arming on the change rather than on every
      -- poll is what keeps (a) the first *data* byte (0xC3, the CCP's own `JP`)
      -- and (b) the next command's entry poll, which still sees the previous
      -- transaction's status, from being logged as status bytes.
      if (data & 0x60) == 0x60 then expect_status = true end
    end
    return
  end
  flush30()
  logf(string.format("R%02X %02x", off, data))
end)

local function type_text(s)
  for i = 1, #s do kb:post(s:sub(i, i)); emu.wait(0.15) end
end

emu.wait(20)
kb:post("\r")                                  -- the BIOS waits for RETURN
emu.wait(6)
type_text("HARD")
kb:post("\r")
emu.wait(tonumber(os.getenv("O1NG_SECONDS") or "150"))
flush30()
logf(string.format("TRACE: done, %d transactions", tx))
