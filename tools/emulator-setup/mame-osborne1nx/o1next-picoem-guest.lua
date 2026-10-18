-- o1next-picoem-guest.lua -- the acceptance for Gate A (#192): the *guest* reads
-- the firmware's answer.
--
-- WHY THIS IS NOT THE OLD HARNESS
--   `o1next-picoem.lua` taps the card's window from Lua and logs what the
--   firmware drove.  It cannot return that byte to the guest, because a Lua read
--   tap that returns data segfaults once the guest polls in a tight loop
--   (measured on MAME 0.289, tools/research/acb4000.lua GOTCHAS).  So it drives
--   the I/O *from Lua* and the Z80 never runs the cycle.
--
--   This harness does the opposite, and that is the whole point: the Z80 runs a
--   real `OUT`/`IN` pair in the card's window, the `picoem_link_device` in the
--   `osborne1nxp` machine answers it out of a real RP2354B firmware, and the
--   value the guest *itself* read is what is asserted.
--
-- WHAT IT DOES
--   1. waits for the machine to settle,
--   2. pokes an 11-byte Z80 routine into RAM at 4000h:
--          DI              ; no interrupts, so nothing can move the PC
--          LD A,0A5h
--          OUT (30h),A     ; the firmware latches A5
--          IN A,(30h)      ; the firmware drives it back
--          LD (4020h),A    ; the guest's own result
--          HALT
--   3. sets PC to 4000h and lets it run,
--   4. reads 4020h back through the *program space* and asserts it is A5.
--
--   `LD (4020h),A` is the trick that makes this honest: the value is read back
--   from the guest's own memory, so a device that returned the wrong byte (or
--   nothing) fails, and nothing in this script can fake it.
--
-- WHY 4000h
--   The Osborne banks 0000h-3FFFh (bank 1 RAM / bank 2 ROM); 4000h and up is
--   RAM in both banks and is where the ROM never looks.  The ROM does not touch
--   30h-33h either -- that is the whole reason the machine exists -- so the only
--   accesses in the window are the two this routine makes.
--
-- ENVIRONMENT
--   O1NEXT_LOG      this script's log (default /tmp/o1next-picoem-guest.log)
--   O1_GUEST_PAT    the byte to drive (default A5)
--   O1_GUEST_SETTLE frames to wait before injecting (default 60)
--   O1_GUEST_DEADLINE frames to allow the routine to finish (default 60)

local M = manager.machine

local LOG_PATH = os.getenv("O1NEXT_LOG") or "/tmp/o1next-picoem-guest.log"
local PAT      = tonumber(os.getenv("O1_GUEST_PAT") or "0xA5")
local SETTLE   = tonumber(os.getenv("O1_GUEST_SETTLE") or "60")
local DEADLINE = tonumber(os.getenv("O1_GUEST_DEADLINE") or "60")
local PORT     = tonumber(os.getenv("O1_GUEST_PORT") or "0x30")

local PROG     = 0x4000
local RESULT   = 0x4020

io.stdout:setvbuf("no")
local LOG = io.open(LOG_PATH, "w")
local function logf(s)
  print(s)
  if LOG then LOG:write(s .. "\n"); LOG:flush() end
end

local CPU = M.devices[":maincpu"]
if not CPU then
  logf("picoem-guest: no :maincpu -- wrong machine?")
  return
end
local SPACE = CPU.spaces["program"]
if not SPACE then
  logf("picoem-guest: no program space")
  return
end

-- The routine.  Byte-for-byte, so the comment above and the code cannot drift.
local CODE = {
  0xF3,                       -- DI
  0x3E, PAT,                  -- LD A,pat
  0xD3, PORT,                 -- OUT (port),A
  0xDB, PORT,                 -- IN A,(port)
  0x32, RESULT % 256, math.floor(RESULT / 256), -- LD (result),A
  0x76,                       -- HALT
}

local injected = false
local finished = false
local waited = 0

local function inject()
  for i = 1, #CODE do
    SPACE:write_u8(PROG + i - 1, CODE[i])
  end
  logf(string.format("picoem-guest: routine at %04X (%d bytes), result at %04X, port %02X, pattern %02X",
    PROG, #CODE, RESULT, PORT, PAT))
  CPU.state["PC"].value = PROG
  injected = true
end

emu.register_frame_done(function()
  if not injected then
    if waited < SETTLE then
      waited = waited + 1
      return
    end
    inject()
    return
  end

  if finished then return end

  -- The routine is done when it has halted or when the PC has left the routine.
  -- Either way the result byte is what matters, and reading it is cheap.
  local pc = CPU.state["PC"].value
  local result = SPACE:read_u8(RESULT)
  local out_of_band = (pc < PROG) or (pc > PROG + #CODE + 1)

  if result == PAT or out_of_band or waited > SETTLE + DEADLINE then
    finished = true
    logf(string.format("picoem-guest: guest PC=%04X, the guest read %02X back from port %02X",
      pc, result, PORT))
    if result == PAT then
      logf(string.format("picoem-guest: the GUEST's own IN returned %02X  => RESULT: PASS", result))
    else
      logf(string.format("picoem-guest: expected %02X in guest RAM at %04X, found %02X  => RESULT: FAIL",
        PAT, RESULT, result))
    end
  end
  waited = waited + 1
end)

logf("picoem-guest: armed -- the guest will drive the window itself")
