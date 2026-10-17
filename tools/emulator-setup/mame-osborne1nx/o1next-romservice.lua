-- o1next-romservice.lua -- headless check of the ROM service's door, and of page
-- 1's selector (#247 step 8, turn 2).
--
-- WHY THIS EXISTS
--   Step 8's first pieces are the interposer's side of the ROM's screen: the ROM
--   asks for the boot frame's halves through a bank-2 register pair, and page 1
--   of the ROM window is the payload *or* one of those halves
--   (docs/rom-pico-protocol.md 4 and 5); and the *code* that draws the screen is
--   a third asset the same way, asked for with PRESENT(3) and copied to RAM by
--   the monitor's stub (docs/o1-rom-2.0.md 4.7).  Both are driven from the
--   machine's side here, with the same writes the ROM's screen code makes, and
--   what page 1 then holds is what is checked.
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
--     -frame /tmp/frame.bin \
--     -bootsplash firmware/rom-service/screen.bin \
--     -autoboot_script o1next-romservice.lua -seconds_to_run 2
--
-- Environment:
--   O1_SOFTROM_IMAGE  the image mounted with -softrom, if any (page 1's payload)
--   O1_FRAME          the image mounted with -frame, if any (the boot frame)
--   O1_BOOTSPLASH     the image mounted with -bootsplash, if any (the screen's code)
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
local FRAME     = os.getenv("O1_FRAME")
local SPLASH    = os.getenv("O1_BOOTSPLASH")
local MONITOR   = os.getenv("O1_SOFTROM_MONITOR")
-- an empty environment variable is an unset one: Lua would call "" a mounted file
if IMAGE == "" then IMAGE = nil end
if FRAME == "" then FRAME = nil end
if SPLASH == "" then SPLASH = nil end
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

-- each half carries its own trailer at 0FF8h *of the half* -- which is page 1's
-- 0FF8h while that half is up (docs/rom-pico-protocol.md 5)
local function trailer(w)
  local magic = ""
  for i = 0, 5 do magic = magic .. string.char(w[STOCK + 0xff8 + i]) end
  local sum = 0
  for i = 0, 0xff7 do sum = (sum + w[STOCK + i]) % 0x10000 end
  return magic, sum, w[STOCK + 0xffe] | (w[STOCK + 0xfff] << 8)
end

local function run()
  -- the window lives in bank 2, and the machine boots there
  I:write_u8(0x00, 0)

  local image = IMAGE and slurp(IMAGE) or nil
  local monitor = MONITOR and slurp(MONITOR) or nil
  local frame = FRAME and slurp(FRAME) or nil
  local splash = SPLASH and slurp(SPLASH) or nil

  logf(string.format("romservice: the door at %04X, page 1's selector, and the address the protocol proposed",
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

  -- INFO: the version, and the flags -- bit 0 a frame, bit 1 the boot splash
  -- (softrom.h's INFO_FLAG_FRAME and INFO_FLAG_BOOTSPLASH)
  r, n = door(OP_INFO)
  check(r and (n == 3) and (r[1] == RC_OK),
        "INFO answers with the version and the flags", r and list(r, n))
  local has_frame, has_splash = false, false
  if r and (n == 3) then
    local flags = r[3]
    has_frame, has_splash = (flags & 0x01) ~= 0, (flags & 0x02) ~= 0
    logf(string.format("  INFO: version %02X, flags %02X (%s, %s)",
                       r[2], flags,
                       has_frame and "a frame is mounted" or "no frame",
                       has_splash and "a boot splash is mounted" or "no boot splash"))
  end
  check(has_frame == (FRAME ~= nil),
        "INFO's frame flag agrees with what the harness mounted",
        "the flag says " .. tostring(has_frame) .. ", O1_FRAME is " ..
        (FRAME and "set" or "unset"))
  check(has_splash == (SPLASH ~= nil),
        "INFO's boot splash flag agrees with what the harness mounted",
        "the flag says " .. tostring(has_splash) .. ", O1_BOOTSPLASH is " ..
        (SPLASH and "set" or "unset"))

  -- PRESENT(0): the payload, which is where page 1 already is
  r, n = door(OP_PRESENT, 0)
  check(r and (n == 1) and (r[1] == RC_OK), "PRESENT(0) -- the payload -- answers OK",
        r and list(r, n))
  local w = window()
  local bad, got, want = page1_diff(w, function(a) return payload_byte(image, monitor, a) end, STOCK)
  check(not bad, "PRESENT(0) leaves the payload in page 1",
        bad and string.format("page 1 +%04X is %02X, expected %02X", bad, got, want))

  -- PRESENT(1): the frame's character half
  r, n = door(OP_PRESENT, 1)
  if has_frame then
    check(r and (n == 1) and (r[1] == RC_OK),
          "PRESENT(1) -- the frame's characters -- answers OK", r and list(r, n))
    w = window()
    bad, got, want = page1_diff(w, function(a) return string.byte(frame, a + 1) end, STOCK)
    check(not bad, "page 1 now holds the frame's character half",
          bad and string.format("page 1 +%04X is %02X, expected %02X", bad, got, want))
    local magic, sum, carried = trailer(w)
    logf(string.format("  chars trailer at 0FF8: %s + sum %04X  (%s)",
                       magic, carried, ((magic == "O1NEXT") and (carried == sum))
                       and "trailer ok" or "trailer BAD"))
    -- the half the ROM is served is the frame's own bytes, unvalidated: the
    -- check is the ROM's job, and a bad frame is the same case as no frame
    check(P:read_u8(STOCK + 0xff8) == string.byte(frame, 0xff8 + 1),
          "the served half is the frame's own bytes, trailer included")

    -- PRESENT(2): the attribute half, the 9th bit
    r, n = door(OP_PRESENT, 2)
    check(r and (n == 1) and (r[1] == RC_OK),
          "PRESENT(2) -- the frame's attributes -- answers OK", r and list(r, n))
    w = window()
    bad, got, want = page1_diff(w, function(a) return string.byte(frame, STOCK + a + 1) end, STOCK)
    check(not bad, "page 1 now holds the frame's attribute half",
          bad and string.format("page 1 +%04X is %02X, expected %02X", bad, got, want))
    local amagic, asum, acarried = trailer(w)
    logf(string.format("  attrs trailer at 0FF8: %s + sum %04X  (%s)",
                       amagic, acarried, ((amagic == "O1NEXT") and (acarried == asum))
                       and "trailer ok" or "trailer BAD"))
  else
    check(r and (n == 1) and (r[1] == RC_NO_CONTENT),
          "PRESENT(1) with no frame answers 'no such content'", r and list(r, n))
    check(P:read_u8(STOCK) == payload_byte(image, monitor, 0),
          "and leaves page 1 alone (the payload is still there)")
  end

  -- PRESENT(3): the boot splash -- the code the monitor's stub copies to RAM at
  -- 4000h and enters (docs/o1-rom-2.0.md 4.7).  One 4096-byte window page, served
  -- byte for byte: unlike the frame it is *not* someone else's file whose trailer
  -- is the ROM's business, it is the interposer's own asset, and its provenance
  -- is the trailer at its own 0FF0h (tools/research/rom2blob.py).
  local before = P:read_u8(STOCK)
  r, n = door(OP_PRESENT, 3)
  if has_splash then
    check(r and (n == 1) and (r[1] == RC_OK),
          "PRESENT(3) -- the boot splash -- answers OK", r and list(r, n))
    w = window()
    bad, got, want = page1_diff(w, function(a) return string.byte(splash, a + 1) end, STOCK)
    check(not bad, "page 1 now holds the boot splash, byte for byte",
          bad and string.format("page 1 +%04X is %02X, expected %02X", bad, got, want))
    local magic = ""
    for i = 0, 5 do magic = magic .. string.char(w[STOCK + 0xff0 + i]) end
    logf(string.format("  splash trailer at 0FF0: %s   (the asset's own provenance, " ..
                       "not the ROM's check)", magic))
  else
    check(r and (n == 1) and (r[1] == RC_NO_CONTENT),
          "PRESENT(3) with no boot splash answers 'no such content'", r and list(r, n))
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
    logf("ROMSERVICE: PASS -- the door, the selector, and the address the machine settles")
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
