-- acb4000.lua -- a MAME-side *trace* of the MD-10's ACB-4000 host-adapter ports
-- (30h-33h), loaded by o1keys.lua when O1_ACB is set. Written for #178.
--
-- WHY THIS EXISTS, AND WHAT IT FOUND
--   #178's residue is the *numeric* DPB the MD-10 driver builds at run time.
--   docs/harddisk-decision.md 7.3 says the values are absent from the archive
--   (nothing initialises the low-RAM DPH/DPB tables at 0x055E/0x056E) and that
--   the next step is to *watch the driver build them* against a stub controller
--   on ports 30h-33h -- the move drive-c-box.lua made for the Drive C box.
--
--   This tool was written to do that, and it produced a *negative* result that
--   is the finding: **MAME's osborne1 cannot address those ports.** Its io_map is
--   only `0x00-0x03` (bankswitch_w) -- the on-board decode uses two address bits
--   -- so 30h-33h alias onto the ROM-bank ports, and the CBIOS drives those same
--   ports on every console character. A Lua-side stub therefore lands on
--   bankswitch_w and cannot answer the adapter. The route needs a MAME *driver*
--   change (a card device with its own full 8-bit I/O decode). See
--   docs/acb4000-host-adapter.md 2.
--
-- MODES (O1_ACB)
--   trace -- install write/read taps on the io space (0-3) and log each access.
--            This is the instrument the finding above came from.
--   (a `stub` mode is deliberately not implemented -- see the header of
--   docs/acb4000-host-adapter.md.)
--
-- HOW IT IS DRIVEN
--   O1_ACB=trace O1_KEYS='type MD10 0' tools/research/o1keys.sh osborne1 SYS.IMD [UTL.IMD]
--   O1_ACB_LOG=/tmp/o1acb.log overrides the log path (default /tmp/o1acb.log).
--
-- GOTCHAS (all measured, MAME 0.289)
--   * The host adapter is on the CPU's *I/O* space (IN/OUT), not the program
--     space the Drive C PIA taps use -- hence spaces["io"]. Its address mask is
--     3, so a tap range must be inside 0x00-0x03; a wider range is rejected.
--   * `write_u8(0x30, v)` reports tap offset 0x00 -- the alias, made visible.
--   * A tap callback that touches `cpu.state["PC"]` THROWS, and because the PC is
--     evaluated as an argument to string.format the whole log line vanishes. That
--     trap made an earlier trace look like it fired nothing; do not add the PC.
--   * The guest's console output floods these ports (one write per character), so
--     expect a large log and filter it.
--   * MAME's Lua layer segfaults on a read tap that *returns a value* once the
--     guest polls in a tight loop (observed with drive-c-box.lua). Keep any such
--     answer pure arithmetic, no allocation, and prefer short runs.

local M = manager.machine
local cpu = M.devices[":maincpu"]
local IOS = cpu.spaces["io"] or cpu.spaces["program"]
local MODE = os.getenv("O1_ACB")
if not MODE or MODE == "" then return end

io.stdout:setvbuf("no")
local LOG = io.open(os.getenv("O1_ACB_LOG") or "/tmp/o1acb.log", "w")
local function logf(s)
  print(s)
  if LOG then LOG:write(s .. "\n"); LOG:flush() end
end

logf("ACB: model mode=" .. MODE .. " on I/O ports 30h-33h (alias 0-3)")

if MODE == "trace" then
  IOS:install_write_tap(0x00, 0x03, "acb_w", function(off, v)
    logf(string.format("W %02X <- %02X", 0x30 + off, v))
  end)
  IOS:install_read_tap(0x00, 0x03, "acb_r", function(off, data)
    logf(string.format("R %02X -> %02X", 0x30 + off, data))
    return data
  end)
  return
end
