-- rom2bank.lua -- the bank selects and the IOBYTE read, tapped (#247).
--
-- WHY THIS EXISTS
--   rom2trace.lua samples the PC and unwinds the stack, which says where the
--   machine ends up: in the ROM's IEEE-488 input routine, entered through the
--   CBIOS's ROMJMP trampoline.  What it cannot say is *why the console dispatch
--   chose the IEEE device*, because the dispatch is reached by a jump and leaves
--   no frame.  These two taps answer that directly:
--
--     * a read tap on 0003h (the CBIOS's IOBYTE) -- the value returned says which
--       bank answered.  D3h is the ROM's own byte: the opcode of the OUT (03h),A
--       at 0004h, whose low two bits are 3, the IEEE device.  80h is RAM, and is
--       the CBIOS's own default (its CBOOT writes it).
--     * a write tap on I/O ports 0-1 -- the only two offsets that select a bank
--       (0 = ROM, 1 = RAM; offsets 2 and 3 are the video DIM control, and the
--       decode is two address bits, so 2Ch-2Fh aliases here and only offsets
--       0/1 are bank selects).  Counting them says whether a guest *asks* for
--       RAM: the stock boot does it constantly (its trampolines bracket every
--       ROM call), the hand-over does it once.
--
--   Keep the callback tiny and do NOT poll memory from this script: acb4000.lua's
--   gotcha is that these taps stop firing once the harness reads the program
--   space from Lua, so it waits a fixed time rather than watching for the prompt.
--
-- USAGE
--   The same script drives both machines, because the comparison is the point:
--
--     # the stock boot (needs RETURN; a copy of the disk, since MAME writes back)
--     SDL_VIDEODRIVER=dummy mame osborne1 -flop1 /tmp/sys.imd -video none \
--       -sound none -nothrottle -rompath tools/emulator-setup/roms \
--       -autoboot_script rom2bank.lua -seconds_to_run 20
--
--     # ROM 2.0's hand-over (needs ESC)
--     O1_BANK_ESC=1 SDL_VIDEODRIVER=dummy mame osborne1nx -video none \
--       -sound none -nothrottle -rompath tools/emulator-setup/roms \
--       -softrom /tmp/rom2.rom -harddisk /tmp/md10/hd.chd \
--       -autoboot_script rom2bank.lua -seconds_to_run 20
--
-- ENVIRONMENT
--   O1_BANK_ESC  press ESC (the ROM 2.0 path) instead of RETURN (the stock boot)

local M = manager.machine
local CPU = M.devices[":maincpu"]
local P = CPU.spaces["program"]
local IOS = CPU.spaces["io"]
local kb = M.natkeyboard

io.stdout:setvbuf("no")
local function logf(s) print(s); io.stdout:flush() end

local counts, order, writes = {}, {}, 0
local rom_sel, ram_sel, sel_lines = 0, 0, {}

P:install_read_tap(0x0003, 0x0003, "iobyte", function(off, data)
  counts[data] = (counts[data] or 0) + 1
  if not order[data] then order[data] = {} end
  if #order[data] < 6 then order[data][#order[data] + 1] = emu.time() end
end)
P:install_write_tap(0x0000, 0x0007, "pzw", function(off, data)
  writes = writes + 1
end)
IOS:install_write_tap(0x00, 0x01, "sel", function(off, data)
  if off == 0 then rom_sel = rom_sel + 1 else ram_sel = ram_sel + 1 end
  if #sel_lines < 12 then
    sel_lines[#sel_lines + 1] = string.format("  t=%.4f  OUT %02X -> %s",
                                              emu.time(), off,
                                              off == 0 and "ROM" or "RAM")
  end
end)

local esc
for line in kb:dump():gmatch("[^\n]+") do
  local code, name = line:match("^([0-9A-F]+) %((.-)%)")
  if name == "Escape" then esc = tonumber(code, 16) end
end

logf(os.getenv("O1_BANK_ESC") and "the ROM 2.0 hand-over path (ESC)"
    or "the stock boot path (RETURN)")
emu.wait(1.2)
if os.getenv("O1_BANK_ESC") then
  if not esc then logf("no ESC code in the natkeyboard table"); os.exit(1) end
  kb:post(utf8.char(esc))
else
  kb:post("\r")
end
emu.wait(8)

logf("")
logf("reads of 0003h (the CBIOS's IOBYTE), by value:")
if next(counts) == nil then logf("  none -- no console call reached the dispatch") end
for v, n in pairs(counts) do
  local times = {}
  for _, t in ipairs(order[v]) do times[#times + 1] = string.format("%.3f", t) end
  logf(string.format("  %02X  x%-6d low two bits %d = %s   first at %s", v, n,
                     v % 4,
                     ({ [0] = "CRTOUT", [1] = "SPOUT", [2] = "PAROUT",
                        [3] = "IEEE" })[v % 4],
                     table.concat(times, ", ")))
end
logf("")
logf("writes to page zero 0000h-0007h: " .. writes)
logf(string.format("bank selects: ROM (OUT 0) x%d, RAM (OUT 1) x%d",
                   rom_sel, ram_sel))
for _, l in ipairs(sel_lines) do logf(l) end
