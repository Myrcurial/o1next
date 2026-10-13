-- o1keys.lua -- boot a disk (optionally with a second in flop2) and drive the
-- guest with a *scripted* sequence of keystrokes, dumping the screen as it goes.
--
-- WHY THIS EXISTS
--   #178's drive-table question is settled by running `MD10.COM` -- a
--   menu-driven editor -- editing exactly one field, saving, and diffing
--   `DRIVETBL.DAT`. `o1disk-copy.lua` types one command and waits for the
--   prompt; that is not enough for a program that never returns to `A>` until
--   you walk its menus. This harness types a whole scripted session.
--   See docs/harddisk-decision.md 7.2 and #178.
--
-- HOW IT IS DRIVEN
--   tools/research/o1keys.sh MACHINE FLOP1 [FLOP2] [SECONDS]
--   with O1_KEYS holding the script, one directive per line:
--     wait  <text>      wait (up to O1_WAIT seconds, default 30) for <text>
--     type  <text>      type <text> then RETURN, ~0.15 s per character
--     key   <token>     post one key: cr, esc, or a single character
--     sleep <secs>      emulated seconds
--     dump  <tag>       print the screen
--     shot  <path>      write a PNG of the screen
--     peek  <addr> <n>  print n bytes of guest memory from addr (hex or dec)
--     poke  <addr> <hh>...  write bytes to guest memory (hex, space-separated)
--     pc                print the guest's PC and AF/BC/DE/HL/SP
--
--   `pc` was added chasing the MD-10's boot (#179): a hang that shows no screen
--   change is ambiguous between "spinning in the loader" and "jumped into a
--   system that never printed", and one line of PC answers it.  Sampling it a
--   few times is what showed the guest executing inside the MD-10 BIOS's block
--   read, i.e. CP/M running out of the emulated hard disk -- see
--   docs/md10-system.md 7.
--   Lines starting with # and blank lines are ignored.
--
-- ENVIRONMENT
--   O1_ACB=<mode>   load acb4000.lua (a trace of the ACB-4000 host-adapter ports
--                   30h-33h) before the guest runs. See acb4000.lua / #178.
--
-- GOTCHAS (docs/mame-emulation.md section 6)
--   * natkeyboard:post() drops a character posted while the previous one is
--     still being typed, and the guest flushes input around disk I/O -- pace at
--     0.15 s and wait for the prompt before typing.
--   * VRAM is a ring buffer; search the whole screen, never a fixed row.
--   * emu.wait() counts emulated seconds.
--   * Do NOT os.exit(): MAME flushes a modified floppy image at a *clean*
--     shutdown, and os.exit() skips that, silently discarding guest writes.

local MACHINE = manager.machine
local scr = MACHINE.screens[":screen"]
local space = MACHINE.devices[":maincpu"].spaces["program"]
local kb = MACHINE.natkeyboard

-- Optional ACB-4000 host-adapter model/trace on I/O ports 30h-33h (#178).
-- Loaded here so the taps are installed before the guest runs. See acb4000.lua.
local ACB_LUA = os.getenv("O1_ACB_LUA")
if os.getenv("O1_ACB") and ACB_LUA then dofile(ACB_LUA) end
local VRAM, STRIDE = 0xF000, 128
local KEYS = os.getenv("O1_KEYS") or ""
local WAIT = tonumber(os.getenv("O1_WAIT") or "30")

local function rows()
  local out = {}
  for r = 0, 31 do
    local s = {}
    for c = 0, STRIDE - 1 do
      local b = space:read_u8(VRAM + r * STRIDE + c) % 128
      s[#s + 1] = (b >= 32 and b < 127) and string.char(b) or " "
    end
    out[r] = (table.concat(s):gsub("%s+$", ""))
  end
  return out
end

local function find(pat)
  for _, line in pairs(rows()) do
    if line:find(pat, 1, true) then return true end
  end
  return false
end

local function wait_for(pat, timeout)
  local t = 0
  while t < timeout do
    if find(pat) then return true end
    emu.wait(0.5); t = t + 0.5
  end
  return false
end

local function dump(tag)
  print("=== DUMP " .. tag .. " ===")
  for r, line in pairs(rows()) do
    if #line > 0 then print(string.format("r%02d|%s", r, line)) end
  end
end

local function type_text(s)
  for i = 1, #s do kb:post(s:sub(i, i)); emu.wait(0.15) end
end

local function key(token)
  if token == "cr" then kb:post("\r")
  elseif token == "esc" then kb:post("\27")
  else kb:post(token) end
end

print(string.format("MACHINE: %s  flop1: %s  flop2: %s",
                    tostring(os.getenv("O1_MACHINE")),
                    tostring(os.getenv("O1_FLOP1")),
                    tostring(os.getenv("O1_FLOP2"))))
print(string.format("SCREEN: %dx%d  (%d columns, %d rows)",
                    scr.width, scr.height, scr.width / 8, scr.height / 10))

print("BANNER: " .. tostring(wait_for("OSBORNE", 25) or wait_for("OZROM", 25)))
kb:post("\r")                                  -- BIOS waits for RETURN
local booted = wait_for("A>", 90)
emu.wait(3)
dump("booted")
print("PROMPT: " .. tostring(booted))

for line in KEYS:gmatch("[^\n]+") do
  if line:sub(1, 1) ~= "#" then
    local verb, arg = line:match("^(%S+)%s*(.*)$")
    if verb == "wait" then
      print("WAIT " .. arg .. ": " .. tostring(wait_for(arg, WAIT)))
    elseif verb == "type" then
      print("TYPE " .. arg)
      type_text(arg); kb:post("\r"); emu.wait(2)
    elseif verb == "key" then
      print("KEY " .. arg)
      key(arg); emu.wait(1)
    elseif verb == "sleep" then
      emu.wait(tonumber(arg) or 1)
    elseif verb == "dump" then
      dump(arg)
    elseif verb == "shot" then
      print("SNAPSHOT: " .. tostring(scr:snapshot(arg)))
    elseif verb == "peek" then
      local a, n = arg:match("^(%S+)%s+(%S+)")
      a, n = tonumber(a), tonumber(n) or 1
      local b = {}
      for i = 0, n - 1 do b[#b + 1] = string.format("%02x", space:read_u8(a + i)) end
      print(string.format("PEEK %04x (%d): %s", a, n, table.concat(b, " ")))
    elseif verb == "pc" then
      -- Where is the guest?  Reading `cpu.state` from a *tap* throws (see the
      -- GOTCHAS), but between directives the guest is idle and it is fine.
      -- Written chasing the MD-10's boot (#179): a hang that shows no screen
      -- change is ambiguous between "spinning in the loader" and "jumped into
      -- a system that never printed", and the PC tells them apart in one line.
      local cpu = MACHINE.devices[":maincpu"]
      local ok, val = pcall(function() return cpu.state["PC"].value end)
      if ok then
        local regs = {}
        for _, r in ipairs({ "AF", "BC", "DE", "HL", "SP" }) do
          local okr, v = pcall(function() return cpu.state[r].value end)
          regs[#regs + 1] = string.format("%s=%04x", r, okr and v or 0)
        end
        print(string.format("PC: %04x  %s", val, table.concat(regs, " ")))
      else
        print("PC: unavailable (" .. tostring(val) .. ")")
      end
    elseif verb == "poke" then
      -- Patching a *file* inside an image (md10patch.py) only reaches bytes the
      -- loader copies verbatim; a run-time variable -- e.g. the MD-10 host
      -- adapter's select byte at 0x8023, which the overlay reads before every
      -- transaction -- is set by the program and has to be written while it
      -- runs.  This is that lever; see docs/osborne1ng-machine.md.
      local a, rest = arg:match("^(%S+)%s+(.*)$")
      a = tonumber(a)
      local b = {}
      for hex in rest:gmatch("%S+") do
        b[#b + 1] = string.format("%02x", tonumber(hex, 16))
        space:write_u8(a + #b - 1, tonumber(hex, 16))
      end
      print(string.format("POKE %04x: %s", a, table.concat(b, " ")))
    end
  end
end

emu.wait(3)
dump("final")
print("DONE")
