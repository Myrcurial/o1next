-- rom2trace.lua -- where ROM 2.0's boot goes after HCBOOT's chain, and what
-- calls the ROM's IEEE-488 routine (#247).
--
-- WHY THIS EXISTS
--   rom2boot.lua proves the chain -- the CBIOS and the MD-10 BIOS out of the
--   softROM's window into RAM, the patch, the bank switch, the system off the
--   drive -- and then reports, honestly, that the machine does not reach A0>:
--   it ends in the ROM's IEEE-488 output routine with the bank back in ROM.
--   *What sends it there* was the open question, and a boot comparison cannot
--   see it.
--
--   This is the instrument that answers it.  It samples the PC finely from the
--   moment ESC is pressed, catches the first entry into the IEEE routine, and
--   then reads the call chain off the stack -- because the PC stream alone
--   cannot name the caller.  The routine at 09EBh-0A4Fh is a *leaf*: push hl,
--   all `jr`, pop hl, ret.  So the word at SP is its own return address, and the
--   words under it are the trampoline's -- and the CBIOS's ROMJMP runs the ROM
--   on a private stack, so it pushes the *caller's* SP, which is what carries
--   the chain back into the guest.
--
--   It also samples the two things the hypothesis turns on: the bank, and page
--   zero+3 (the CBIOS's IOBYTE) *as the guest reads it* -- in bank 2 that read
--   returns the ROM's own byte, not RAM.
--
-- Run it as a standalone -autoboot_script, with the image mounted:
--
--   SDL_VIDEODRIVER=dummy mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -autoboot_script rom2trace.lua -seconds_to_run 40
--
-- Environment:
--   O1_ROM2_SAMPLE  seconds between PC samples (default 0.01)
--   O1_ROM2_SPAN    seconds to keep sampling after ESC (default 8)
--
-- ESC is not ASCII 27 on this machine -- the Osborne's ESC key is declared
-- PORT_CHAR(UCHAR_MAMEKEY(ESC)), so the code is read out of the natkeyboard's
-- own table here, as rom2boot.lua and o1keys.lua do.

local M = manager.machine
local CPU = M.devices[":maincpu"]
local P = CPU.spaces["program"]
local kb = M.natkeyboard

local WINDOW = 0x1000           -- the softROM's window, bank 2 only
local CCP, MD10, CBIOS = 0xC200, 0xD800, 0xE100
local CBIOS_END = 0xE900
local IEEE_LO, IEEE_HI = 0x09EB, 0x0A50
local PZ_IOBYTE = 0x0003        -- page zero: the CBIOS's IOBYTE

local SAMPLE = tonumber(os.getenv("O1_ROM2_SAMPLE") or "") or 0.002
local SPAN = tonumber(os.getenv("O1_ROM2_SPAN") or "") or 6

io.stdout:setvbuf("no")
local function logf(s) print(s); io.stdout:flush() end

-- Registers -----------------------------------------------------------------
local function reg(name)
  local ok, v = pcall(function() return CPU.state[name].value end)
  return ok and v or nil
end
local function regs()
  local t = {}
  for _, n in ipairs({ "AF", "BC", "DE", "HL", "IX", "IY", "SP", "AF'", "BC'",
                       "DE'", "HL'" }) do
    t[#t + 1] = string.format("%s=%04X", n, reg(n) or 0)
  end
  return table.concat(t, " ")
end

-- Memory --------------------------------------------------------------------
local function rd(a) return P:read_u8(a) end
local function word(a) return rd(a) + rd(a + 1) * 256 end
local function hex(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02X", rd(a + i)) end
  return table.concat(t, " ")
end
-- Write 5A to 1000h and read it back: RAM keeps it, ROM does not.  1000h is the
-- one address that tells the banks apart without disturbing the guest.
local function bank()
  local before = rd(WINDOW)
  P:write_u8(WINDOW, 0x5A)
  local after = rd(WINDOW)
  P:write_u8(WINDOW, before)
  return (after == 0x5A) and "RAM" or "ROM"
end
local function region(pc)
  if pc < 0x1000 then return "ROM" end
  if pc >= CCP and pc < MD10 then return "CCP/BDOS" end
  if pc >= MD10 and pc < CBIOS then return "MD-10" end
  if pc >= CBIOS and pc < CBIOS_END then return "CBIOS" end
  if pc >= 0xF000 and pc < 0xF800 then return "VRAM" end
  return "other"
end
local function in_ieee(pc) return pc >= IEEE_LO and pc <= IEEE_HI end

-- A word looks like a return address if the instruction three bytes below it is
-- a CALL, or the byte below it is an RST.  That is the filter that makes a raw
-- stack dump readable: every CALL pushes exactly this shape.
local CALLS = { [0xC4] = true, [0xCC] = true, [0xD4] = true, [0xDC] = true,
                [0xE4] = true, [0xEC] = true, [0xF4] = true, [0xFC] = true }
local RESTS = { [0xC7] = true, [0xCF] = true, [0xD7] = true, [0xDF] = true,
                [0xE7] = true, [0xEF] = true, [0xF7] = true, [0xFF] = true }
local function why_return(w)
  if w < 0x0100 then return nil end
  if rd(w - 3) == 0xCD or CALLS[rd(w - 3)] then
    return string.format("call at %04X", w - 3)
  end
  if RESTS[rd(w - 1)] then return string.format("rst at %04X", w - 1) end
  return nil
end

local function esc_code()
  for line in kb:dump():gmatch("[^\n]+") do
    local code, name = line:match("^([0-9A-F]+) %((.-)%)")
    if name == "Escape" then return tonumber(code, 16) end
  end
end
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
local function wait_for(pat, t)
  local e = 0
  while e < t do
    if find(pat) then return true end
    emu.wait(0.5); e = e + 0.5
  end
  return false
end

-- The measurement ------------------------------------------------------------
logf("ROM 2.0's boot after HCBOOT's chain -- what calls the IEEE routine")
local signed = wait_for("Insert disk", 25)
logf("  sign-on: " .. tostring(signed))

local esc = esc_code()
logf(string.format("  ESC is natkeyboard code %s",
                   esc and string.format("%06X", esc) or "NOT FOUND"))
if not esc then os.exit(1) end

-- Press ESC and sample.  The ring buffer is the run-up to the first IEEE
-- sample, which is what "catch the caller" means when the sample is coarser
-- than the call: the stack then supplies the exact address.
local ring, ring_max = {}, 24
local hist, samples = {}, 0
local last_region, last_bank, last_pz3 = nil, nil, nil
local first_ieee = nil
local changes = {}
local ram_pz3, rom_pz3 = nil, nil

local function push(pc, sp, b, pz)
  ring[#ring + 1] = string.format("t=%.3f pc=%04X sp=%04X %s pz3=%02X",
                                  emu.time(), pc, sp, b, pz)
  if #ring > ring_max then table.remove(ring, 1) end
end

kb:post(utf8.char(esc))
local elapsed = 0
while elapsed < SPAN do
  emu.wait(SAMPLE)
  elapsed = elapsed + SAMPLE

  local pc, sp = reg("PC"), reg("SP")
  if pc and sp then
    local b = bank()
    local pz = rd(PZ_IOBYTE)
    samples = samples + 1
    local r = region(pc)
    hist[r] = (hist[r] or 0) + 1
    push(pc, sp, b, pz)

    if b == "RAM" and ram_pz3 == nil then ram_pz3 = pz end
    if b == "ROM" and rom_pz3 == nil then rom_pz3 = pz end

    if r ~= last_region or b ~= last_bank or pz ~= last_pz3 then
      changes[#changes + 1] = string.format(
        "  t=%6.3f  %s / %-8s  pc=%04X sp=%04X pz3=%02X",
        emu.time(), b, r, pc, sp, pz)
      last_region, last_bank, last_pz3 = r, b, pz
    end

    if in_ieee(pc) and not first_ieee then
      -- Freeze the run-up *now*: the machine stays in the routine for ever, so
      -- the ring a few seconds later holds nothing but the routine.
      local runup = {}
      for _, l in ipairs(ring) do runup[#runup + 1] = l end
      first_ieee = { pc = pc, sp = sp, bank = b, pz3 = pz, t = emu.time(),
                     regs = regs(), ring = runup }
    end
  end
end

logf("")
logf(string.format("the journey (%d samples, %.2f s apart):", samples, SAMPLE))
for _, line in ipairs(changes) do logf(line) end

logf("")
logf("where the time went:")
local order = { "ROM", "MD-10", "CCP/BDOS", "CBIOS", "VRAM", "other" }
for _, k in ipairs(order) do
  if hist[k] then
    logf(string.format("  %-9s %5d  (%.0f%%)", k, hist[k],
                       100 * hist[k] / samples))
  end
end

logf("")
if not first_ieee then
  logf("no sample landed in the ROM's IEEE routine -- nothing to unwind.")
  logf("last samples:")
  for _, l in ipairs(ring) do logf("  " .. l) end
  logf("ROM2TRACE: no dispatch observed")
  os.exit(1)
end

logf(string.format("first entry into the IEEE routine: pc=%04X sp=%04X %s pz3=%02X",
                   first_ieee.pc, first_ieee.sp, first_ieee.bank, first_ieee.pz3))
logf("the run-up, frozen at that sample (what was running when the call was made):")
for _, l in ipairs(first_ieee.ring) do logf("  " .. l) end

logf("")
logf("registers at entry: " .. first_ieee.regs)
logf(string.format("page zero   %s   (in bank 2 this is the ROM, not RAM)",
                   hex(0, 8)))
logf(string.format("  0003h reads %02X -- the CBIOS's IOBYTE is page zero+3, and"
                   .. " its low two bits", first_ieee.pz3))
logf(string.format("  select the console device: %d = %s", first_ieee.pz3 % 4,
                   ({ [0] = "CRTOUT", [1] = "SPOUT", [2] = "PAROUT",
                      [3] = "IEOUT" })[first_ieee.pz3 % 4]))
logf(string.format("  RAM value seen: %s   ROM value seen: %s",
                   ram_pz3 and string.format("%02X", ram_pz3) or "<never sampled in RAM>",
                   rom_pz3 and string.format("%02X", rom_pz3) or "<never>"))

-- Is an interrupt handler live?  The 60 Hz handler saves SP at 0EF6F and runs on
-- its own stack at 0EF99; its key cells are 0EF59 (locked) and 0EF5E (the key).
-- And the two cells the hand-over turns on: ROMRAM (0EF08) is the ROM/RAM flag
-- the interrupt exit tests, and CCPADR (0EFD2) is the base the ROM's ROMJP1 adds
-- 1633h to -- the CBIOS's RRI, which restores the bank.
logf("")
local romram, ccpadr = rd(0xEF08), word(0xEFD2)
logf(string.format("interrupt state: IFF1=%s IFF2=%s  (0EF6F)=%04X  "
                   .. "KEYLCK(0EF59)=%02X  key(0EF5E)=%02X",
                   tostring(reg("IFF1")), tostring(reg("IFF2")),
                   word(0xEF6F), rd(0xEF59), rd(0xEF5E)))
logf(string.format("ROMRAM (0EF08) = %02X -- the ROM/RAM flag the interrupt exit"
                   .. " tests", romram))
logf(string.format("CCPADR (0EFD2) = %04X -- ROMJP1 jumps to CCPADR+1633h = %04X",
                   ccpadr, (ccpadr + 0x1633) % 0x10000))
logf("  the CBIOS's RRI (the interrupt exit that restores the bank) is at 0E133h,")
logf("  so CCPADR must be CB00h for that exit to be taken; with 0000h it lands in")
logf("  the softROM's page 1, which is the payload's own copy of the CBIOS.")

-- The stack.  The routine is a leaf, so the top word is its own return address
-- and the ones under it are the trampoline's frames.
local sp = first_ieee.sp
logf("")
logf(string.format("the stack from SP=%04X (words, with what each could be):", sp))
for i = 0, 15 do
  local a = sp + i * 2
  local w = word(a)
  logf(string.format("  %04X: %04X  %s   %s", a, w, region(w) == "other"
                     and "--------" or string.format("%-8s", region(w)),
                     why_return(w) or ""))
end

-- The chain: ROMJMP runs the ROM on a private stack and pushes the caller's SP,
-- so somewhere in this window is a word that is itself a stack pointer.  Follow
-- it and read the return address off *that* stack.
logf("")
logf("following the pushed stack pointers (the CBIOS's ROMJMP saves the caller's):")
local seen = {}
for i = 0, 63 do
  local a = sp + i * 2
  local w = word(a)
  if not seen[a] and w >= 0xE000 and w <= 0xF000 and w ~= sp then
    seen[a] = true
    local top = word(w)
    logf(string.format("  [%04X]=%04X looks like a stack pointer; (SP)=%04X  %s  %s",
                       a, w, top, region(top) == "other" and "--------"
                       or string.format("%-8s", region(top)),
                       why_return(top) or ""))
  end
end

logf("")
logf("ROM2TRACE: the dispatch above is the measurement")
os.exit(0)

