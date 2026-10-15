-- rom2handover.lua -- prove the hand-over's fix before building it (#247).
--
-- WHY THIS EXISTS
--   The measured diagnosis is that ROM 2.0's hand-over is one store short:
--   `CCPADR` (`0EFD2h`), which the ROM's own `CBOOT` writes at `02A3h`, is what
--   the ROM's 60 Hz interrupt handler's *return to RAM* exit adds 1633h to
--   (`ROMJP1` -> the CBIOS's `RRI` at `0E133h`, whose `OUT (C),A` restores the
--   bank).  With it zero the exit lands on `1633h` -- the softROM's page 1, the
--   payload's own copy of the CBIOS's console dispatch -- which reads `IOBYTE`
--   from a page zero that in ROM mode is the ROM (`D3h`, the IEEE device), and
--   the machine never returns.
--
--   This is the cheap experiment that turns that diagnosis into a proof: poke
--   `CCPADR = CB00h` -- and the CBIOS's own IOBYTE, `80h`, at page zero+3 -- into
--   RAM just after the hand-over, and see whether the boot reaches `A0>`.  It
--   does, with no floppy in the machine.  So the next step (putting that store
--   into `HCBOOT`, from RAM, after the bank switch) has a known outcome rather
--   than a hoped-for one.
--
--   The poke is repeated across a window, because the bank is re-derived on every
--   instruction fetch and on interrupt acknowledge (docs/o1-memory-io-map.md 4):
--   only a poke that lands while RAM is selected reaches page zero, and the last
--   one wins.  `CCPADR` is above `3FFFh`, so it is visible either way.
--
-- USAGE
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -harddisk /tmp/md10/hd.chd -autoboot_script rom2handover.lua \
--     -seconds_to_run 40

local M = manager.machine
local CPU = M.devices[":maincpu"]
local P = CPU.spaces["program"]
local kb = M.natkeyboard

local CCPADR, IOBYTE = 0xEFD2, 0x0003
local CCP, IOBITE = 0xCB00, 0x80

io.stdout:setvbuf("no")
local function logf(s) print(s); io.stdout:flush() end
local function rd(a) return P:read_u8(a) end
local function rows()
  local out = {}
  for r = 0, 31 do
    local s = {}
    for c = 0, 127 do
      local b = rd(0xF000 + r * 128 + c) % 128
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

-- ESC is not ASCII 27 on this machine: the code comes out of the natkeyboard's
-- own table, as rom2boot.lua and o1keys.lua do.
local esc
for line in kb:dump():gmatch("[^\n]+") do
  local code, name = line:match("^([0-9A-F]+) %((.-)%)")
  if name == "Escape" then esc = tonumber(code, 16) end
end
if not esc then logf("no ESC code in the natkeyboard table"); os.exit(1) end

local e = 0
while e < 25 and not find("Insert disk") do emu.wait(0.5); e = e + 0.5 end
logf("sign-on seen; posting ESC (the monitor's HCBOOT entry)")
kb:post(utf8.char(esc))

-- HCBOOT reaches its bank switch about 85 ms after ESC; poke across that window.
emu.wait(0.085)
for _ = 1, 20 do
  P:write_u8(CCPADR, CCP % 256)         -- CCPADR = CB00h, little endian
  P:write_u8(CCPADR + 1, CCP // 256)
  P:write_u8(IOBYTE, IOBITE)            -- the CBIOS's own default
  emu.wait(0.002)
end
logf(string.format("poked CCPADR=%04X IOBYTE=%02X",
                   rd(CCPADR) + rd(CCPADR + 1) * 256, rd(IOBYTE)))

emu.wait(6)
logf("")
logf("the screen:")
for _, line in ipairs(rows()) do
  if line ~= "" then logf("  |" .. line .. "|") end
end
logf("")
logf("A0> on screen: " .. tostring(find("A0>")))
logf("ROM2HANDOVER: " .. (find("A0>") and "the hand-over boots with that one store"
                          or "no A0>"))
os.exit(find("A0>") and 0 or 1)
