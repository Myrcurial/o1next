-- o1next-romservice.lua -- headless check of the ROM service's door, and of page
-- 1 (#247 step 8, turn 2; rewritten for #278, 2026-10-17).
--
-- WHY THIS EXISTS
--   The interposer's side of the ROM's window is a bank-2 register pair and the
--   page it selects.  This drives the door from the machine's side -- the same
--   writes the ROM's own code makes -- and checks what page 1 then holds
--   (docs/rom-pico-protocol.md 4).
--
--   Page 1 used to be a selector: `PRESENT(1)` and `PRESENT(2)` put the boot
--   frame's two halves there and `PRESENT(3)` the screen's own code.  All three
--   retired with the ROM-side frame path (#278) -- the RP2354B is the display and
--   the monitor's screen code lives in its own tail now -- so `PRESENT(0)`, the
--   payload, is the one content id left, and this checks that the other three
--   answer "no such content" and leave page 1 alone.
--
-- THE ADDRESS IS THE ONE THING THE MACHINE CAN SETTLE
--   The protocol proposed 2300h/2301h, on the grounds that
--   docs/o1-memory-io-map.md 7 calls 2300-23FF the largest clean block.  It is
--   not clean: the onboard selects check two address bits, so 0x2301 is the
--   floppy's track register *and* the keyboard's row 0 (measured --
--   docs/o1-mainboard-schematic.md 7a), and a reply ANDed with the FDC's track
--   register (0x00 at the sign-on) reads "not ready" for ever.  This harness
--   measures that first -- 0x2301 reads what 0x2101 reads -- and then uses
--   0x2800, the part of that recommended block that nothing selects.
--
-- Run it as a *standalone* -autoboot_script:
--
--   SDL_VIDEODRIVER=dummy \
--     mame osborne1nx -video none -sound none -nothrottle \
--     -rompath tools/emulator-setup/roms -softrom /tmp/rom2.rom \
--     -autoboot_script o1next-romservice.lua -seconds_to_run 2
--
-- Environment:
--   O1_SOFTROM_IMAGE  the image mounted with -softrom, if any (page 1's payload)
-- (there are no flash assets to mount any more: the -frame and -bootsplash slots
-- retired with the frame path, #278)
--   O1_SOFTROM_MONITOR  the stock 4 KB monitor, needed only with no -softrom
--   O1_DOOR           the door's base in bank 2 (default 0x2800)
--   O1_CONTRACT       the base the protocol proposed (default 0x2300)
--   O1_FDC_TRACK      the floppy's track register, its documented address
--                     (default 0x2101) -- the aliasing proof's other side
--
-- It prints ROMSERVICE: PASS or ROMSERVICE: FAIL, and exits 0 or 1.

local M = manager.machine
local P = M.devices[":maincpu"].spaces["program"]
local I = M.devices[":maincpu"].spaces["io"]

local STOCK     = 0x1000
local WINDOW    = 0x2000
local DOOR      = tonumber(os.getenv("O1_DOOR") or "") or 0x2800
local CONTRACT  = tonumber(os.getenv("O1_CONTRACT") or "") or 0x2300
local FDC_TRACK = tonumber(os.getenv("O1_FDC_TRACK") or "") or 0x2101
local IMAGE     = os.getenv("O1_SOFTROM_IMAGE")
local MONITOR   = os.getenv("O1_SOFTROM_MONITOR")
-- an empty environment variable is an unset one: Lua would call "" a mounted file
if IMAGE == "" then IMAGE = nil end
if MONITOR == "" then MONITOR = nil end

-- the ROM service's opcodes and result codes (docs/mailbox-protocol.md 4, plus
-- the one code the ROM's class adds)
local OP_NOP, OP_ECHO, OP_PRESENT, OP_INFO = 0x00, 0x01, 0x40, 0x41
local RC_OK, RC_UNKNOWN, RC_NO_CONTENT = 0x00, 0x01, 0x09

io.stdout:setvbuf("no")
local fails = 0
local function logf(s) print(s) ; io.stdout:flush() end
local function hex(v) return string.format("%02X", v) end

local function check(ok, what, detail)
  if ok then
    logf("  PASS  " .. what)
  else
    fails = fails + 1
    logf("  FAIL  " .. what .. (detail and ("  --  " .. detail) or ""))
  end
  return ok
end

local function slurp(path)
  local f = assert(io.open(path, "rb"), "no such file: " .. path)
  local d = f:read("a")
  f:close()
  return d
end

local function list(bytes, n)
  local t = {}
  for i = 1, n do t[#t + 1] = hex(bytes[i]) end
  return table.concat(t, " ")
end

-- One transaction: the request's bytes, then the reply.  The reply's *first*
-- read is its length and the next N reads are its bytes, exactly as the mailbox
-- protocol says (0 = not ready, poll again), so the poll loop here is the ROM's.
-- Returns the N reply bytes -- reply[1] is the result code -- and N.
local function door(...)
  for _, b in ipairs({...}) do P:write_u8(DOOR, b) end
  local n = 0
  for _ = 1, 1000 do
    n = P:read_u8(DOOR + 1)
    if n ~= 0 then break end
  end
  if n == 0 then return nil, 0, "the reply register never became ready" end
  local r = {}
  for i = 1, n do r[i] = P:read_u8(DOOR + 1) end
  return r, n
end

local function window()
  local w = {}
  for a = 0, WINDOW - 1 do w[a] = P:read_u8(a) end
  return w
end

-- what page 1 should hold for PRESENT(0): the payload, which is the window
-- image's own page 1 -- or the monitor, mirrored, when there is no image or the
-- image *is* the stock part (softrom.h)
local function payload_byte(image, monitor, a)
  if image and (#image > STOCK) then
    return (STOCK + a < #image) and string.byte(image, STOCK + a + 1) or 0xff
  end
  if image then return string.byte(image, (a % STOCK) + 1) end
  return string.byte(monitor, (a % STOCK) + 1)
end

local function page1_diff(w, want, n)
  for a = 0, n - 1 do
    if w[STOCK + a] ~= want(a) then return a, w[STOCK + a], want(a) end
  end
  return nil
end

local function run()
  -- the window lives in bank 2, and the machine boots there
  I:write_u8(0x00, 0)

  local image = IMAGE and slurp(IMAGE) or nil
  local monitor = MONITOR and slurp(MONITOR) or nil

  logf(string.format("romservice: the door at %04X, page 1, and the address the protocol proposed",
                     DOOR))
  logf("")

  -- --- the measurement that decides the address ----------------------------
  logf(string.format("== the contract's base, %04X/%04X", CONTRACT, CONTRACT + 1))
  local track_before = P:read_u8(FDC_TRACK)
  local contract_reply = P:read_u8(CONTRACT + 1)
  logf(string.format("  floppy track register    %04X reads %02X", FDC_TRACK, track_before))
  logf(string.format("  contract reply register  %04X reads %02X", CONTRACT + 1, contract_reply))
  check(contract_reply == track_before,
        "the contract's reply register is the floppy's track register",
        string.format("%04X reads %02X, %04X reads %02X",
                      CONTRACT + 1, contract_reply, FDC_TRACK, track_before))
  logf("  -- so a reply ANDed with it reads 0 (not ready) for ever: the door")
  logf("     cannot live there.  docs/o1-mainboard-schematic.md 7a, re-measured")
  logf("     here, in the machine that has the door.")

  -- a request written there goes to the floppy controller's own registers, not
  -- to a door
  local page_before = P:read_u8(STOCK)
  P:write_u8(CONTRACT, OP_PRESENT)
  logf(string.format("  after PRESENT's opcode is written to %04X -- the floppy's", CONTRACT))
  logf(string.format("  command register -- track %02X -> %02X and page 1's first byte",
                     track_before, P:read_u8(FDC_TRACK)))
  logf(string.format("  %02X -> %02X: the door is not there", page_before, P:read_u8(STOCK)))
  check(P:read_u8(STOCK) == page_before,
        "the contract's base does not reach the door (page 1 is untouched)")
  logf("")

  -- --- the door, at the address that nothing else selects ------------------
  logf(string.format("== the door at %04X/%04X", DOOR, DOOR + 1))

  -- ECHO: the presence probe, twice with two patterns (mailbox-protocol.md 3)
  local r, n = door(OP_ECHO, 0x5a)
  check(r and (n == 2) and (r[1] == RC_OK) and (r[2] == 0x5a),
        "ECHO 5A comes back", r and list(r, n))
  r, n = door(OP_ECHO, 0xa5)
  check(r and (n == 2) and (r[1] == RC_OK) and (r[2] == 0xa5),
        "ECHO A5 comes back", r and list(r, n))

  -- INFO: the version, and the flags byte -- which has no bits left to report,
  -- because the frame and the screen-code slots retired (#278).  It stays in the
  -- reply because the reply's *shape* is the protocol's.
  r, n = door(OP_INFO)
  check(r and (n == 3) and (r[1] == RC_OK),
        "INFO answers with the version and the flags", r and list(r, n))
  if r and (n == 3) then
    logf(string.format("  INFO: version %02X, flags %02X (no assets to report -- #278)",
                       r[2], r[3]))
    check(r[3] == 0x00,
          "and the flags byte is clear: there is no asset slot left to report")
  end

  -- PRESENT(0): the payload, which is where page 1 already is
  r, n = door(OP_PRESENT, 0)
  check(r and (n == 1) and (r[1] == RC_OK), "PRESENT(0) -- the payload -- answers OK",
        r and list(r, n))
  local w = window()
  local bad, got, want = page1_diff(w, function(a) return payload_byte(image, monitor, a) end, STOCK)
  check(not bad, "PRESENT(0) leaves the payload in page 1",
        bad and string.format("page 1 +%04X is %02X, expected %02X", bad, got, want))

  -- PRESENT(1), (2) and (3): the ids that retired with the ROM-side frame path
  -- (#278).  The frame's two halves and the screen's own code used to be served
  -- here; nothing asks for them now, so each id answers 09h and leaves page 1
  -- alone -- which is the ROM's own "no such content" case
  -- (docs/rom-pico-protocol.md 4.2).
  local before = P:read_u8(STOCK)
  for _, id in ipairs({ 1, 2, 3 }) do
    r, n = door(OP_PRESENT, id)
    check(r and (n == 1) and (r[1] == RC_NO_CONTENT),
          string.format("PRESENT(%d) answers 'no such content' -- that id retired with the frame path (#278)", id),
          r and list(r, n))
    check(P:read_u8(STOCK) == before, "and leaves page 1 alone")
  end

  -- NOP, and an unknown opcode: the way back to a known state
  r, n = door(OP_NOP)
  check(r and (n == 1) and (r[1] == RC_OK), "NOP answers OK", r and list(r, n))
  r, n = door(0x77)
  check(r and (n == 1) and (r[1] == RC_UNKNOWN),
        "an unknown opcode answers 01h", r and list(r, n))

  -- a write while a reply is pending abandons it: ECHO's reply is left unread,
  -- and INFO's is what comes back (mailbox-protocol.md 3).  (A write *before*
  -- the reply is complete is an operand, not a new opcode -- which is why the
  -- rule is about the pending reply rather than about any write.)
  P:write_u8(DOOR, OP_ECHO)
  P:write_u8(DOOR, 0x5a)      -- ECHO's reply is pending now, and never read
  r, n = door(OP_INFO)
  check(r and (n == 3) and (r[1] == RC_OK),
        "a write while a reply is pending abandons it and starts a new one",
        r and list(r, n))

  -- and the payload comes back, which is the last thing the screen does
  r, n = door(OP_PRESENT, 0)
  check(r and (n == 1) and (r[1] == RC_OK), "PRESENT(0) brings the payload back",
        r and list(r, n))
  w = window()
  bad, got, want = page1_diff(w, function(a) return payload_byte(image, monitor, a) end, STOCK)
  check(not bad, "page 1 is the payload again",
        bad and string.format("page 1 +%04X is %02X, expected %02X", bad, got, want))

  logf("")
  if fails == 0 then
    logf("ROMSERVICE: PASS -- the door, page 1, and the address the machine settles")
  else
    logf("ROMSERVICE: FAIL -- " .. fails .. " check(s) failed")
  end
  os.exit(fails == 0 and 0 or 1)
end

local done = false
emu.register_frame_done(function()
  if done then return end
  done = true
  run()
end)
