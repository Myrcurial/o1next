-- drive-c-trace.lua -- log every access to the Osborne 1's IEEE-488 PIA while a
-- Drive C program runs, so the host-side protocol can be *measured* rather than
-- only read out of the disassembly.
--
-- WHY THIS EXISTS
--   DCL.COM's transport (0x16d5-0x17be) bit-bangs the 6821 at 2900-2903 to talk to
--   the Drive C box. The disassembly says what the host does; this says what the
--   machine *actually* does when the real Drive C software runs, which is the
--   evidence the protocol spec needs (#6 / #84). See docs/drive-c-protocol.md.
--
-- HOW IT IS DRIVEN
--   SDL_VIDEODRIVER=dummy mame osborne1 -flop1 COPY-OF-DRIVE_C.IMD -video none \
--     -sound none -nothrottle -rompath <roms> \
--     -autoboot_script drive-c-trace.lua -seconds_to_run N
--
--   IMPORTANT: pass a **copy** of DRIVE_C.IMD. The disk's AUTOST rewrites its
--   own system tracks, and MAME writes a modified floppy image back to disk, so
--   running against the archive copy mutates it (observed).
--
-- WHAT IT PRINTS
--   One line per PIA access:  T<emu-seconds> <R|W> <reg> = <value>
--   where reg is 2900(portA) 2901(CRA) 2902(portB) 2903(CRB). Reads of port A
--   are the box->host data path; writes of 2901 are the CA2 (IFC/busy) strobe.

local M = manager.machine
local prog = M.devices[":maincpu"].spaces["program"]

local NAMES = { [0x2900] = "A  ", [0x2901] = "CRA", [0x2902] = "B  ", [0x2903] = "CRB" }
local MAX = tonumber(os.getenv("O1_TRACE_MAX") or "4000")
local n = 0
local t0 = emu.time()

local function stamp() return string.format("%8.4f", emu.time() - t0) end

local function log(kind, off, val)
  n = n + 1
  if n > MAX then return end
  -- 'off' comes back relative to the tapped range (0..3) in MAME's Lua binding.
  print(string.format("T%s %s %s = %02X", stamp(), kind, NAMES[off] or ("?" .. off), val))
end

prog:install_write_tap(0x2900, 0x2903, "dc_w", function(offset, data, mask)
  log("W", offset, data); return data
end)
prog:install_read_tap(0x2900, 0x2903, "dc_r", function(offset, data, mask)
  log("R", offset, data); return data
end)

print("TRACE: taps installed on 2900-2903")
print(string.format("SCREEN: %dx%d", M.screens[":screen"].width, M.screens[":screen"].height))
-- Press RETURN at the BIOS prompt, then let the disk's AUTOST/DCL run.
emu.wait(2)
M.natkeyboard:post("\r")
emu.wait(tonumber(os.getenv("O1_TRACE_SECONDS") or "30"))
print("TRACE_END accesses=" .. n)
