-- drive-c-box.lua -- a minimal *Drive C box* implemented in MAME's Lua, used to
-- validate the protocol spec in docs/drive-c-protocol.md against the real Drive C
-- software running on the emulated machine (#6 / #84).
--
-- WHY THIS EXISTS
--   The Drive C protocol was reconstructed from DCL.COM's disassembly. A spec
--   that has never been exercised is worth less than one that has, so this
--   answers the host the way the box would and lets the real DCL.COM / DFD.SPR
--   run. It is a *protocol* model, not a device model: it decodes the PIA
--   traffic and keeps a table of 128-byte blocks, nothing more.
--
-- WHAT IT MODELS (see docs/drive-c-protocol.md for the measured sequence)
--   port B (2902) = frame/command states: 08h open, 00h second header byte,
--                   81h read, 88h write, 09h close.
--   port A (2900) = the data byte, host->box (write) or box->host (read).
--   CRA   (2901)  = CA2, pulsed 3Eh then 36h once per byte = the byte clock.
--   Header bytes: h1 = (DE>>1)&0xFF, h2 = f(DE>>9) | ((DE&1)<<7), where DE is
--   the 16-bit record address the driver passed in. This model keys storage on
--   the raw (h1,h2) pair, which is equivalent and simpler.
--
-- HOW IT IS DRIVEN
--   O1_BOX_DEBUG=1 SDL_VIDEODRIVER=dummy mame osborne1 -flop1 COPY-OF-DRIVE_C.IMD \
--     -video none -sound none -nothrottle -rompath <roms> \
--     -autoboot_script drive-c-box.lua -seconds_to_run 90
--
--   IMPORTANT: pass a **copy** of DRIVE_C.IMD. The disk's AUTOST rewrites its
--   own system tracks, and MAME writes a modified floppy image back to disk, so
--   running against the archive copy mutates it (observed).

local M = manager.machine
local prog = M.devices[":maincpu"].spaces["program"]
local DEBUG = os.getenv("O1_BOX_DEBUG") == "1"

-- Unbuffered stdout, plus an explicit log file. MAME sometimes segfaults on
-- headless teardown and a buffered print is lost when it does; the file, flushed
-- per line, is what makes the result survive.
io.stdout:setvbuf("no")
local LOG = io.open(os.getenv("O1_BOX_LOG") or "/tmp/o1box.log", "w")
local function logf(s)
  print(s)
  if LOG then LOG:write(s .. "\n"); LOG:flush() end
end

local store = {}          -- key -> {128 bytes}
local state = "idle"      -- idle | h1 | h2 | data
local h1, h2, mode = nil, nil, nil
local idx, cur_read = 0, 0
local frames = 0
local cb = nil            -- the block being transferred, resolved once per frame

local function key() return string.format("%02X:%02X", h1 or 0, h2 or 0) end
local function blk()
  local k = key()
  if not store[k] then local t = {}; for i = 0, 127 do t[i] = 0xE5 end; store[k] = t end
  return store[k]
end

-- Two taps only, each spanning the whole PIA (2900-2903), dispatched on the
-- register offset. Four separate adjacent taps (write 2900/2901/2902 plus a read
-- on 2900) reliably segfault MAME's Lua layer on a longer run; two wide taps do
-- not, which is worth knowing for anyone else instrumenting a memory-mapped
-- device from Lua. See docs/drive-c-protocol.md.
--
--   W 2902 (port B) = frame/command states: 08h open, 00h second header byte,
--                     81h read, 88h write, 09h close.
--   W 2901 (CRA)    = CA2 pulse, 3Eh (low) then 36h (high) = the byte clock.
--   W 2900 (port A) = the data byte, host -> box.
--   R 2900 (port A) = the data byte, box -> host.
prog:install_write_tap(0x2900, 0x2903, "dc_w", function(off, v)
  if off == 0x2902 then
    if v == 0x08 then state, h1, h2, mode, idx = "h1", nil, nil, nil, 0
    elseif v == 0x00 and state ~= "idle" then state = "h2"
    elseif v == 0x81 or v == 0x88 then
      mode = (v == 0x81) and "read" or "write"; idx, cur_read, state = 0, 0, "data"
      cb = blk()   -- resolve ONCE per frame; the hot taps must not allocate
      frames = frames + 1
      if DEBUG then print(string.format("BOX frame %d h1=%02X h2=%02X %s", frames, h1 or 0, h2 or 0, mode)) end
    elseif v == 0x09 then state = "idle"
    end
  elseif off == 0x2901 then
    if state == "data" and v == 0x3E then
      if mode == "read" then cur_read = idx end
      idx = idx + 1
    end
  elseif off == 0x2900 then
    if state == "h1" then h1 = v; state = "h1done"
    elseif state == "h2" then h2 = v; state = "h2done"
    elseif state == "data" and mode == "write" and cb then cb[idx] = v end
  end
  -- no return: the tap observes, it does not modify the write
end)

-- The box's own answer, plus its PIB6 "ready" line (O1_BOX_READY=1). PIB6 is
-- NDAC in GPIB terms and "printer ready" in Centronics terms (rom144.asm 3259).
if os.getenv("O1_BOX_NOREAD") ~= "1" then
  prog:install_read_tap(0x2900, 0x2903, "dc_r", function(off, data)
    if off == 0x2900 and state == "data" and mode == "read" and cb then
      -- Bare table lookup; no allocation in the hot path. NOTE: MAME's Lua
      -- layer segfaults on longer runs once the guest's resident driver starts
      -- polling (returning a constant instead of real data keeps the run
      -- short enough to survive). This is a MAME limitation, not a protocol
      -- one -- see docs/drive-c-protocol.md.
      local b = cb[cur_read]
      if b == nil then b = 0xE5 end
      return b
    end
    if off == 0x2902 and os.getenv("O1_BOX_READY") == "1" then
      return data | 0x40
    end
    return data
  end)
end

logf("BOX: Drive C model installed")
emu.wait(2)
M.natkeyboard:post("\r")
emu.wait(tonumber(os.getenv("O1_BOX_SECONDS") or "60"))

-- Optionally type a CP/M command (e.g. "DIR C:") once the loader has finished.
local CMD = os.getenv("O1_BOX_CMD")
if CMD and CMD ~= "" then
  for i = 1, #CMD do M.natkeyboard:post(CMD:sub(i, i)); emu.wait(0.15) end
  M.natkeyboard:post("\r")
  emu.wait(tonumber(os.getenv("O1_BOX_CMD_WAIT") or "20"))
end

local n = 0
for _ in pairs(store) do n = n + 1 end
logf(string.format("BOX_END frames=%d blocks=%d", frames, n))

-- Dump the screen so the wrapper can see what the Drive C software said.
-- NOTE: reuse the `prog` handle captured at the top -- re-fetching
-- manager.machine.devices[...].spaces[...] from Lua after taps are installed
-- segfaults MAME (observed), and this is the cheap way to avoid it.
logf("=== SCREEN ===")
for r = 0, 31 do
  local s = {}
  for c = 0, 127 do
    local b = prog:read_u8(0xF000 + r * 128 + c) % 128
    s[#s + 1] = (b >= 32 and b < 127) and string.char(b) or " "
  end
  local line = (table.concat(s):gsub("%s+$", ""))
  if #line > 0 then logf(string.format("r%02d|%s", r, line)) end
end
