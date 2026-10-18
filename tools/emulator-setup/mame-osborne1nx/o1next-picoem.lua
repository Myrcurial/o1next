-- o1next-picoem.lua -- the MAME half of the picoem bridge (#286, part of #192).
--
-- THE SHAPE
--   A real RP2354B firmware image is running inside picoem (tools/picoem-bridge),
--   and this script is the machine's side of the wire between them: every I/O
--   access in the card's window goes out as a 24-byte frame and the firmware's
--   answer comes back as another.  What that proves is the thing #192 exists
--   for -- the interposer's *firmware* in the loop, not a Lua script pretending
--   to be it.
--
-- THE WIRE IS A PAIR OF FIFOs, NOT A SOCKET, AND THAT WAS MEASURED
--   #192's option 3 says "a socket/pipe protocol", and a socket is not
--   available here: MAME's Lua preloads exactly four modules -- `zlib`, `lfs`,
--   `linenoise`, `lsqlite3` -- and `3rdparty/` has no luasocket at all.  The
--   alternatives were both changes to MAME (vendor luasocket, or write a C++
--   device), and a FIFO costs neither.  `io.open(path, "r+b")` is O_RDWR on a
--   FIFO, which is a blocking byte stream with no open-order deadlock -- the
--   same semantics a socket would have given, and *blocking* is what the
--   ACB-4000 needs: the Z80's cycle is answered before it continues.
--   tools/picoem-bridge/src/fifo.rs has the long version.
--
-- HOW IT IS DRIVEN
--   A *standalone* -autoboot_script, like the other harnesses in this directory.
--
--     tools/picoem-bridge/target/release/picoem-bridge \
--         --flash firmware/picoem-smoke/build/picoem-smoke.bin \
--         --bootrom "$PICOEM_CLONE/roms/rp2350/bootrom-combined.bin" &
--     SDL_VIDEODRIVER=dummy mame <osborne1nx> -rompath tools/emulator-setup/roms \
--         -video none -sound none -nothrottle -seconds_to_run 4 \
--         -autoboot_script tools/emulator-setup/mame-osborne1nx/o1next-picoem.lua
--
--   `picoem-check.sh` does all of that and checks the answer.
--
-- ENVIRONMENT
--   O1_PICOEM_IN    request FIFO  (default /tmp/o1next-picoem/in)
--   O1_PICOEM_OUT   reply FIFO    (default /tmp/o1next-picoem/out)
--   O1NEXT_LOG      this script's log (default /tmp/o1next-picoem-mame.log)
--   O1_PICOEM_PORT_LO / _HI        the window to tap (default 30h / 33h)
--   O1_PICOEM_DRIVE the I/O accesses to make, as "W30=A5,R30,W31=5A,R31"
--                   (default: none -- the guest's own traffic is tapped and
--                   logged, and nothing is synthesised)
--   O1_PICOEM_SCRATCH  a guest address to write each reply byte to, so that the
--                   answer is *in the machine* and not only in this log.  Off
--                   by default: a diagnostic that scribbles in a running
--                   system's RAM is not something to do unasked.
--   O1_PICOEM_REQUIRE  1 = a missing bridge is fatal (picoem-check.sh sets it).
--
-- THE ONE THING THAT IS NOT DONE HERE
--   The read tap does **not** return the firmware's byte to the guest.  MAME's
--   read taps can, and a read tap that returns data segfaults once the guest
--   polls in a tight loop (tools/research/acb4000.lua, GOTCHAS -- measured on
--   MAME 0.289).  So the answer is logged, and optionally written to a scratch
--   byte; making the *guest* read it needs the card's own device to carry it,
--   which is #179's work and not this acceptance.

local M = manager.machine

local IN_PATH  = os.getenv("O1_PICOEM_IN")  or "/tmp/o1next-picoem/in"
local OUT_PATH = os.getenv("O1_PICOEM_OUT") or "/tmp/o1next-picoem/out"
local LOG_PATH = os.getenv("O1NEXT_LOG")    or "/tmp/o1next-picoem-mame.log"
local PORT_LO  = tonumber(os.getenv("O1_PICOEM_PORT_LO") or "0x30")
local PORT_HI  = tonumber(os.getenv("O1_PICOEM_PORT_HI") or "0x33")
local SCRATCH  = tonumber(os.getenv("O1_PICOEM_SCRATCH") or "")
local REQUIRE  = os.getenv("O1_PICOEM_REQUIRE") == "1"
local DRIVE    = os.getenv("O1_PICOEM_DRIVE") or ""

io.stdout:setvbuf("no")
local LOG = io.open(LOG_PATH, "w")
local function logf(s)
  print(s)
  if LOG then LOG:write(s .. "\n"); LOG:flush() end
end

-- ---------------------------------------------------------------------------
-- The frame format.  src/frame.rs is the other copy of this contract and
-- docs/picoem-bridge.md is the prose; if they disagree, they are all wrong and
-- the Rust tests are right.
-- ---------------------------------------------------------------------------
local MAGIC = "O1B1"
local LEN = 24

local OP_HELLO, OP_BUS_WRITE, OP_BUS_READ = 0, 1, 2

local FLAG_SPACE_MEM = 0x01

local REPLY_HEARTBEAT, REPLY_DATA_OE, REPLY_DRIVEN = 0x01, 0x02, 0x04

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function u32(v)
  return string.char(v % 256, math.floor(v / 256) % 256,
                     math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end
local function le16(s, i) return s:byte(i) + s:byte(i + 1) * 256 end
local function le32(s, i)
  return s:byte(i) + s:byte(i + 1) * 256 + s:byte(i + 2) * 65536 + s:byte(i + 3) * 16777216
end
local function checksum(s)
  local t = 0
  for i = 1, #s do t = (t + s:byte(i)) % 65536 end
  return t
end

local function request(op, port, data, seq, cycles)
  local body = MAGIC .. string.char(op, 0, port, data) .. u16(0) .. u16(seq) .. u32(cycles)
      .. "\0\0\0\0"                      -- 12..15 cycles, then 16..19 reserved
  return body .. u16(checksum(body)) .. "\0\0"
end

local function parse_reply(s)
  if #s < LEN or s:sub(1, 4) ~= MAGIC then return nil, "bad magic" end
  if le16(s, 21) ~= checksum(s:sub(1, 20)) then return nil, "bad checksum" end
  return {
    status = s:byte(5),
    data   = s:byte(6),
    hb     = s:byte(7),
    flags  = s:byte(8),
    addr   = le16(s, 9),
    seq    = le16(s, 11),
    pc     = le32(s, 13),
    cycles = le32(s, 17),
  }
end

local function flags_str(f)
  return string.format("%s%s%s",
    (f % 2 >= 1) and "HB " or "-- ",
    (math.floor(f / 2) % 2 >= 1) and "OE " or "-- ",
    (math.floor(f / 4) % 2 >= 1) and "DRV" or "---")
end

-- ---------------------------------------------------------------------------
-- The channel.
-- ---------------------------------------------------------------------------
local fin, fout = io.open(IN_PATH, "r+b"), io.open(OUT_PATH, "r+b")
if not fin or not fout then
  logf(string.format("picoem: NO BRIDGE -- %s / %s could not be opened", IN_PATH, OUT_PATH))
  logf("picoem: start tools/picoem-bridge first (see docs/picoem-bridge.md); no taps installed")
  if REQUIRE then os.exit(1) end
  return
end
logf(string.format("picoem: channel %s -> %s", IN_PATH, OUT_PATH))

local seq = 0
local reply_cache = {}

local function transact(op, port, data, cycles)
  seq = (seq + 1) % 65536
  local frame = request(op, port, data, seq, cycles or 0)
  fin:write(frame)
  fin:flush()
  local s = fout:read(LEN)
  if not s or #s < LEN then return nil, "short read" end
  local r, why = parse_reply(s)
  if not r then return nil, why end
  if r.seq ~= seq then return nil, string.format("seq %d, expected %d", r.seq, seq) end
  return r
end

-- The answer, in the machine and not only in this log, when asked for.
local function poke_scratch(r)
  if not SCRATCH then return end
  M.devices[":maincpu"].spaces["program"]:write_u8(SCRATCH, r.data)
end

local function hello()
  local r, why = transact(OP_HELLO, 0, 0)
  if not r then
    logf("picoem: HELLO failed: " .. tostring(why))
    return false
  end
  logf(string.format("picoem: HELLO  status %02X  firmware pc=%08X cycles=%d",
    r.status, r.pc, r.cycles))
  return r.status == 0
end

if not hello() then
  logf("picoem: the bridge is there but the firmware is not running -- no taps installed")
  if REQUIRE then os.exit(1) end
  return
end

-- ---------------------------------------------------------------------------
-- The taps: the card's window, both directions.
-- ---------------------------------------------------------------------------
local IOS = M.devices[":maincpu"].spaces["io"]

IOS:install_write_tap(PORT_LO, PORT_HI, "picoem_w", function(off, v)
  local r, why = transact(OP_BUS_WRITE, off, v)
  if not r then
    logf(string.format("picoem: W %02X <- %02X  bridge error: %s", off, v, tostring(why)))
    return
  end
  reply_cache[off] = r
  poke_scratch(r)
  logf(string.format("picoem: W %02X <- %02X  firmware drove %02X  hb=%d %s  pc=%08X",
    off, v, r.data, r.hb, flags_str(r.flags), r.pc))
end)

-- Deliberately returns nothing: see the header.  A read tap that returns data
-- segfaults once the guest polls in a tight loop.
IOS:install_read_tap(PORT_LO, PORT_HI, "picoem_r", function(off, data)
  local r, why = transact(OP_BUS_READ, off, 0)
  if not r then
    logf(string.format("picoem: R %02X      bridge error: %s", off, tostring(why)))
    return
  end
  reply_cache[off] = r
  poke_scratch(r)
  logf(string.format("picoem: R %02X      firmware drove %02X  hb=%d %s  (guest saw %02X)",
    off, r.data, r.hb, flags_str(r.flags), data))
end)

logf(string.format("picoem: taps installed on %02X-%02X", PORT_LO, PORT_HI))

-- ---------------------------------------------------------------------------
-- Optionally *make* the machine do some I/O in the window.
--
-- The accesses go through the machine's own I/O space, so the taps fire exactly
-- as they would for the MD-10's driver: this is a bus cycle in `osborne1nx`,
-- not a call into the bridge.  The guest does not touch 30h-33h without a hard
-- disk booted, and `picoem-check.sh` needs a deterministic proof, so it drives
-- the window itself rather than waiting for a guest that may never ask.
-- ---------------------------------------------------------------------------
if DRIVE ~= "" then
  local frame_no = 0
  emu.register_frame_done(function()
    frame_no = frame_no + 1
    if frame_no ~= 60 then return end -- one emulated second in, once
    logf("picoem: driving the window from the harness: " .. DRIVE)
    for item in DRIVE:gmatch("[^,]+") do
      local dir, port, val = item:match("^%s*([WRw]?)%s*(%x+)%s*=?%s*(%x*)%s*$")
      if dir and port and dir ~= "" then
        port = tonumber(port, 16)
        if dir == "W" then
          IOS:write_u8(port, tonumber(val, 16) or 0)
        else
          local got = IOS:read_u8(port)
          logf(string.format("picoem: guest read %02X -> %02X", port, got))
        end
      end
    end
  end)
end
