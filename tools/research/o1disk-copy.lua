-- o1disk-copy.lua -- boot a disk in flop1, type a CP/M command at A> (which
-- can read or write the disk in flop2), and report what happened.
--
-- WHY THIS EXISTS
--   #95's acceptance test is "format/copy a diskette and read it back". MAME's
--   Osborne 1 has two 525ssdd connectors, so a command typed at the guest's A>
--   prompt can move files between the image in -flop1 and the image in -flop2.
--   This is the keyboard-injecting counterpart to mame-boot-probe.lua: the probe
--   only presses RETURN, this one types a whole command line. Written for #95;
--   see docs/dd-upgrade-formats.md.
--
-- HOW IT IS DRIVEN
--   tools/research/o1disk-copy.sh MACHINE FLOP1 FLOP2 "PIP B:=A:MBASIC.COM"
--   (see that wrapper for the environment it sets: O1_CMD, O1_SHOT, O1_ROMPATH)
--
-- GOTCHAS (see docs/mame-emulation.md section 6)
--   * natkeyboard:post() drops a character posted while the previous one is
--     still being typed, and the guest flushes its input around disk I/O, so
--     characters go out ~0.15 s apart and we wait after the command.
--   * VRAM is a ring buffer -- search the whole screen, never a fixed row.
--   * emu.wait() counts EMULATED seconds, so timings are true 4 MHz Z80.

local MACHINE = manager.machine
local scr = MACHINE.screens[":screen"]
local space = MACHINE.devices[":maincpu"].spaces["program"]
local kb = MACHINE.natkeyboard
local VRAM, STRIDE = 0xF000, 128
local CMD = os.getenv("O1_CMD") or ""
local SHOT = os.getenv("O1_SHOT")

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

local function find_row(pat)
  for r = 0, 31 do
    if rows()[r]:find(pat, 1, true) then return r end
  end
  return nil
end

-- A fresh prompt is a row *below* the echoed command line whose text is just
-- "A>". Matching a bare "A>" anywhere is a false positive: the typed line
-- "A>PIP ..." already contains one, which is how the first version of this
-- harness reported success before the command had run.
local function prompt_after(row)
  for r = (row or -1) + 1, 31 do
    local line = rows()[r]:gsub("%s+$", "")
    if line == "A>" then return r end
  end
  return nil
end

local function type_line(s)
  for i = 1, #s do kb:post(s:sub(i, i)); emu.wait(0.15) end
  kb:post("\r")
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
emu.wait(3)                                    -- let AUTOST/XDIR settle
dump("booted")
print("PROMPT: " .. tostring(booted))

if booted and CMD ~= "" then
  print("CMD: " .. CMD)
  kb:post("\r"); emu.wait(1)                    -- get a clean prompt line
  type_line(CMD)
  local echo_row = find_row(CMD)
  emu.wait(2)
  local done, t = false, 0
  while t < 120 do
    if prompt_after(echo_row) then done = true; break end
    emu.wait(1); t = t + 1
  end
  emu.wait(2)
  dump("after")
  print("CMD_DONE: " .. tostring(done))
end
if SHOT then print("SNAPSHOT: " .. tostring(scr:snapshot(SHOT))) end
-- NOTE: do NOT os.exit() here. MAME flushes a modified floppy image to disk when
-- the device is torn down at a clean shutdown, and os.exit() skips that -- the
-- guest writes succeed but never reach the .imd file (verified for #95: a
-- `SAVE 1 HELLO.TXT` under os.exit() left the image byte-identical). Ending the
-- script lets MAME run on to -seconds_to_run and exit cleanly, which saves.
print("DONE")
