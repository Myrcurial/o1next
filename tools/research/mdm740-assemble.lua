-- mdm740-assemble.lua -- assemble the Comm-Pac overlay on the machine, with ASM.COM.
--
-- WHAT THIS IS FOR
--   The drive carries `MDM740.COM` as FOG126 ships it: the **uninstalled
--   distribution**, whose overlay is a PMMI placeholder.  The overlay that makes
--   it a Comm-Pac terminal is M7OD-5 (FOG129, "Osborne 1 w/Comm-Pac or CTS
--   Datacomm modem"), and FOG stores it as `.AQM` -- which is `.ASM`, squeezed,
--   i.e. *source*.  So it has to be assembled, and the only 8080 assembler this
--   project has is CP/M 2.2's ASM.COM, on the shipped system disk:
--   `populate-hd.py --stage` puts ASM.COM, DDT.COM and M7OD-5.ASM on the drive
--   (A: and B:), so the machine can do it itself.
--
--   This is that session, scripted.  It leaves `M7OD-5.HEX` on B:;
--   `tools/research/mdm740-overlay.py` then does DDT's job on the host, where it
--   is repeatable.
--
-- HOW TO RUN IT
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms \
--     -softrom <staged>/assets/rom2.rom -harddisk <staged>/assets/hd.chd \
--     -autoboot_script tools/research/mdm740-assemble.lua -seconds_to_run 200
--
--   `<staged>` is a machine from tools/emulator-setup/mame-osborne1nx/stage-o1next.sh.
--   It runs the drive at the machine's own speed; `-nothrottle` is safe here
--   because every step waits for a *screen* pattern rather than a clock.
--
-- WHY THE WAITS ARE rom2drives.lua's
--   That harness already proved this machine boots the hard disk with no floppy
--   and reaches `A0>` (#247), so its two waits -- the ROM's "Insert disk" and the
--   CCP's "A0>" -- are the ones known to work here.  o1keys.lua's VRAM scan is
--   for the *stock* machine's screen, and a session driven by blind sleeps never
--   reached a prompt at all: the assembler's output showed up on the screen while
--   the later commands went to the CCP as unknown commands.
local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local kb = M.natkeyboard
local VRAM, STRIDE = 0xF000, 128

io.stdout:setvbuf("no")
local function logf(s) print(s); io.stdout:flush() end
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
local function dump(tag)
  logf("=== DUMP " .. tag .. " ===")
  for r, line in pairs(rows()) do
    if #line > 0 then logf(string.format("r%02d|%s", r, line)) end
  end
end
local function type_text(s)
  for i = 1, #s do kb:post(s:sub(i, i)); emu.wait(0.15) end
  kb:post("\r")
end
-- Type a command and wait for the CCP prompt to come back.  The prompt is what
-- makes this safe: a `type` that outruns the guest is the failure mode o1keys.lua
-- warns about, and the assembler is the slow step.
local function command(cmd, prompt, budget)
  logf("TYPE " .. cmd)
  type_text(cmd)
  local ok = wait_for(prompt or "0>", budget or 60)
  logf("  -> " .. (ok and "prompt" or "NO PROMPT"))
  return ok
end

logf("MDM740 + the Comm-Pac overlay, assembled on the machine")
logf("  sign-on: " .. tostring(wait_for("Insert disk", 25)))
emu.wait(1)
kb:post("\r")
local booted = wait_for("A0>", 60)
logf("  the machine booted the hard disk: " .. tostring(booted))
if not booted then dump("no-boot"); os.exit(1) end

command("B:", "B0>", 20)
command("ASM M7OD-5", "B0>", 90)          -- the 583-line overlay
dump("assembled")
logf("ASSEMBLED: " .. tostring(find("END OF ASSEMBLY")))
logf("M7OD-5.HEX is on B: -- now run tools/research/mdm740-overlay.py")
