-- o1_mame_probe.lua -- interrogate a running Osborne 1 and check that the
-- machine actually behaves the way docs/o1-memory-io-map.md says it does.
--
-- This is the "run it as a machine" half of the schematic work: the scanned
-- schematic says what the logic is *supposed* to do, this says what the
-- emulated machine *does*.  Where they disagree, one of the two is wrong, and
-- that is exactly the kind of question worth spending time on.
--
-- Driven by tools/check_o1_map.sh; not run directly.
--
-- Method: every probe is a direct bus access through MAME's Lua address-space
-- objects, so it does not depend on the guest running anything in particular.
-- RAM is told from ROM by writing back the complement of the byte that was
-- there and restoring it: a RAM cell follows, a ROM cell does not.

local M    = manager.machine
local prog = M.devices[":maincpu"].spaces["program"]
local io   = M.devices[":maincpu"].spaces["io"]

local npass, nfail = 0, 0
local function check(ok, id, msg, detail)
    if ok then
        npass = npass + 1
        print(string.format("PASS  %-5s %s", id, msg))
    else
        nfail = nfail + 1
        print(string.format("FAIL  %-5s %s%s", id, msg,
                            detail and ("  [" .. tostring(detail) .. "]") or ""))
    end
    return ok
end

local function rd(a) return prog:read_u8(a) end
local function wr(a, v) prog:write_u8(a, v) end
local function hex(n) return string.format("0x%04X", n) end

-- Video RAM lives at 0xF000 in the RAM bank; 128 bytes per row, 32 rows.
local function screen()
    local out = {}
    for row = 0, 31 do
        local r = {}
        for col = 0, 127 do
            local b = rd(0xF000 + row * 128 + col) % 128
            r[#r + 1] = (b >= 32 and b < 127) and string.char(b) or " "
        end
        out[#out + 1] = table.concat(r)
    end
    return table.concat(out, "\n")
end

-- True if a behaves like RAM: flip the top bit, look, put it back.
local function is_ram(a)
    local save = rd(a)
    local flipped = (save + 128) % 256
    wr(a, flipped)
    local got = rd(a)
    wr(a, save)
    return got == flipped
end

-- A 16-byte window at a: true if anything but 0xFF answers.
local function responds(a)
    for i = 0, 15 do
        if rd(a + i) ~= 0xFF then return true end
    end
    return false
end

print("== Osborne 1 memory / I/O map check (MAME, running machine) ==")
print(string.format("program space: mask=%s width=%d   io space: mask=%s width=%d",
      hex(prog.address_mask), prog.data_width,
      hex(io.address_mask), io.data_width))

-- Boot to the A> prompt so the machine is in its normal running state.
emu.wait(2)
M.natkeyboard:post("\r")
local waited, booted = 0, false
while waited < 60 do
    if screen():find("A>", 1, true) then booted = true break end
    emu.wait(0.5)
    waited = waited + 0.5
end
print(string.format("booted to A> after %.1f emulated seconds", emu.time()))
check(booted, "B1", "CP/M reaches the A> prompt in the emulated machine")

-- C1: the screen really is memory-mapped at 0xF000 in the RAM bank.
check(is_ram(0xF000), "C1",
      "0xF000 behaves as RAM (video RAM is in the RAM bank)")

-- C2: main RAM spans 0x4000-0xEFFF.
local ram_pages, first_bad = 0, nil
for page = 0x40, 0xEF do
    if is_ram(page * 256) then ram_pages = ram_pages + 1
    elseif not first_bad then first_bad = page end
end
check(ram_pages == 0xB0, "C2",
      string.format("0x4000-0xEFFF is RAM (%d/176 pages)", ram_pages),
      first_bad and ("first page that is not: " .. hex(first_bad * 256)) or nil)

-- C3/C4: the bank switch is I/O ports 0x00-0x03, and it is the *port number*
-- that selects the action - the data byte is ignored.  0x00 = ROM bank,
-- 0x01 = RAM bank (driver: "the value on the data bus is completley ignored").
-- NOTE: no emu.wait() between the write and the read below.  The bank latch
-- takes effect immediately, but the bank is then *re-derived* on every
-- instruction fetch from the M1/IRQACK flip-flops (driver: opcode_r), and the
-- video PIA interrupts at 60 Hz - so a 100 ms wait is six interrupts and the
-- bank has already flipped back.  C10 below measures that directly.
local initial_rom = not is_ram(0x0000)
io:write_u8(0x00, 0x00)
local rom_bank = not is_ram(0x0000)
io:write_u8(0x01, 0xff)
local ram_bank = is_ram(0x0000)
check(rom_bank, "C3", "I/O write to port 0x00 selects the ROM bank")
check(ram_bank, "C4", "I/O write to port 0x01 selects the RAM bank")
print(string.format("      bank seen at the A> prompt before probing: %s",
                    initial_rom and "ROM" or "RAM"))

-- C5: the data byte really is ignored - writing 0x00 *with data 0x01* still
-- selects the ROM bank, even though 0x01 as a *port* would select RAM.
io:write_u8(0x00, 0x01)
check(not is_ram(0x0000), "C5", "the data byte on a bank-switch write is ignored")

-- C6: only A0/A1 of the port number are decoded (driver: global_mask(0x03)),
-- so port 0x05 is port 0x01 and port 0x04 is port 0x00.
io:write_u8(0x05, 0x00)
local alias1 = is_ram(0x0000)
io:write_u8(0x04, 0x00)
local alias0 = not is_ram(0x0000)
check(alias1 and alias0, "C6",
      "I/O ports 0x04/0x05 alias 0x00/0x01 (only A0/A1 decoded)",
      "io space address mask is " .. hex(io.address_mask))

-- C10: the selected bank does not stay selected.  Put the machine in the RAM
-- bank, let a little emulated time pass, and it is back in the ROM bank -
-- because the bank is re-derived on instruction fetches, not latched.  This is
-- why the machine reads ROM at 0x0000 even while CP/M is running.
io:write_u8(0x01, 0x00)
local stayed = is_ram(0x0000)
emu.wait(0.05)
local flipped = not is_ram(0x0000)
check(stayed and flipped, "C10",
      "the selected bank is re-derived on instruction fetch, not latched",
      string.format("RAM right after the write, %s after 0.05 emulated seconds",
                    flipped and "ROM" or "RAM"))

-- C7: ports 0x02/0x03 select the bank-3 attribute plane at 0xF000-0xFFFF.  It
-- is one bit wide - the low seven bits are discarded and read back high - so a
-- 0x00 written there reads back as 0x7F.  If bank 3 were not mapped we would
-- be writing the 8-bit video plane and read back 0x00.
io:write_u8(0x01, 0x00)                      -- RAM bank
io:write_u8(0x02, 0x00)                      -- map bank 3 (BIT 9) over 0xF000
wr(0xF000, 0x00)
local attr = rd(0xF000)
io:write_u8(0x03, 0x00)                      -- back to the bank 1/2 plane
check(attr == 0x7F, "C7", "I/O port 0x02 maps the 1-bit bank-3 plane over 0xF000",
      string.format("read back 0x%02X, expected 0x7F", attr))

-- C8: in the ROM bank the ROM is mirrored over 0x1000-0x1FFF.
io:write_u8(0x00, 0x00)
local mirror_bad = nil
for i = 0, 255 do
    if rd(0x0000 + i) ~= rd(0x1000 + i) then mirror_bad = i break end
end
check(mirror_bad == nil, "C8", "ROM at 0x0000-0x0FFF mirrors 0x1000-0x1FFF",
      mirror_bad and ("first difference at +" .. mirror_bad) or nil)

-- C9: the bank-2 I/O decode checks only two address bits, so a nominally-dead
-- address selects the same register as a documented one.  Each pair below
-- decodes to exactly the same device *and* the same register within it, so the
-- two reads must agree.
-- (Pairs that differ by a bit another device also checks do NOT agree - e.g.
-- 0x2301 is the keyboard *and* the floppy, 0x2f00 is the video PIA *and* the
-- serial ACIA.  That bus fighting is the same sloppiness, seen from the other
-- side, and is reported after the check.)
--
-- One device has to be allowed for, and it is asked rather than assumed: a
-- machine with the SCREEN-PAC fitted answers across 0x2400-0x27FF as well, and
-- pulls bit 2 LOW there -- that is the board's documented presence flag
-- (docs/mame-emulation.md 2).  So an alias that lands in that range reads one
-- bit lower than its documented partner *because the board is fitted*, which is
-- not a decode disagreement at all.  The board's own flag says whether to
-- expect it: 2400h bit 2 LOW is fitted, HIGH is not, and the stock machine is
-- HIGH.
local screenpac = (rd(0x2400) & 0x04) == 0
local function in_sp(a) return a >= 0x2400 and a <= 0x27ff end
local aliases = {
    { 0x2100, 0x2500, "floppy register 0" },
    { 0x2201, 0x2601, "keyboard row 0" },
    { 0x2900, 0x2904, "IEEE-488 PIA port A" },
    { 0x2a00, 0x2a02, "serial ACIA status" },
    { 0x2c00, 0x2c04, "video PIA port A" },
}
print(string.format("      SCREEN-PAC: %s (2400h bit 2 %s)",
                    screenpac and "fitted" or "not fitted",
                    screenpac and "LOW" or "HIGH"))
print("      bank-2 I/O decode: documented address vs nominally-dead alias")
local all_alias = true
for _, a in ipairs(aliases) do
    local v1, v2 = rd(a[1]), rd(a[2])
    -- If the board answers on either address, both reads are compared through
    -- its pull (bit 2 low): the two devices' own answers are what this check is
    -- about, and the board is not one of them.
    local same
    if screenpac and (in_sp(a[1]) or in_sp(a[2])) then
        same = (v1 & 0xfb) == (v2 & 0xfb)
    else
        same = v1 == v2
    end
    if not same then all_alias = false end
    print(string.format("        %s vs %s  %-20s reads 0x%02X / 0x%02X  %s",
                        hex(a[1]), hex(a[2]), a[3], v1, v2,
                        same and "aliased" or "DIFFERENT"))
end
check(all_alias, "C9",
      "nominally-dead bank-2 addresses alias real devices (sloppy decode)")

-- Report: addresses that hit two devices at once.  The values are the AND of
-- both devices' outputs (the driver simulates the bus fight that way).
local fights = {
    { 0x2301, "keyboard row 0 + floppy" },
    { 0x2f00, "video PIA + serial ACIA" },
    { 0x2900, "IEEE-488 PIA alone" },
}
print("      addresses that decode to two devices at once:")
for _, f in ipairs(fights) do
    print(string.format("        %s %-28s reads 0x%02X", hex(f[1]), f[2], rd(f[1])))
end

-- Report (do not assert) what the documented windows read back.  Many read
-- 0xFF legitimately - an idle keyboard row, a clear ACIA status - so a 0xFF
-- here is not evidence that a device is missing.
local windows = {
    { 0x2100, "floppy (WD179x) status" },
    { 0x2103, "floppy data" },
    { 0x2201, "keyboard row 0" },
    { 0x2280, "keyboard row 7" },
    { 0x2900, "IEEE-488 PIA port A" },
    { 0x2a00, "serial ACIA status" },
    { 0x2c00, "video PIA port A" },
    { 0x2c02, "video PIA port B (beeper)" },
}
print("      documented bank-2 windows, read back (0xFF is often legitimate):")
for _, w in ipairs(windows) do
    print(string.format("        %s %-26s 0x%02X", hex(w[1]), w[2], rd(w[1])))
end

-- D1: the ROM is not just a boot loader - it is live while CP/M runs.  Sample
-- the Z80's PC over a second at the idle A> prompt and see which regions it is
-- executing in.  This is how the "ROM is paged in and out during normal
-- operation" claim was established: at the prompt the machine is parked in a
-- ROM polling loop waiting for a key, with bank 2 selected.
local regions = {}
local saw_rom = false
for _ = 1, 20 do
    local ok, pc = pcall(function()
        return M.devices[":maincpu"].state["PC"].value
    end)
    if ok and pc then
        local where
        if pc < 0x1000 then
            where = "ROM 0x0000-0x0FFF"; saw_rom = true
        elseif pc < 0x2000 then
            where = "ROM mirror 0x1000-0x1FFF"
        elseif pc < 0x4000 then
            where = "bank-2 I/O 0x2000-0x3FFF"
        else
            where = string.format("RAM 0x%04X page", pc - pc % 0x1000)
        end
        regions[where] = (regions[where] or 0) + 1
    end
    emu.wait(0.05)
end
print("      Z80 PC sampled 20x at the idle A> prompt:")
local keys = {}
for k in pairs(regions) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
    print(string.format("        %-28s %d", k, regions[k]))
end
check(saw_rom, "D1", "the Z80 executes in the ROM while CP/M is running",
      "no sample landed in the ROM")

-- Page map of both banks: W=RAM  R=ROM or device  .=nothing (reads 0xFF).
-- Caveat: a device register that reads back what was written looks like W, so
-- W in the bank-2 I/O range means "answers to a write/readback", not "RAM".
local function classify_bank(label)
    print("      " .. label)
    print("            0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F")
    for hi = 0x00, 0xF0, 0x10 do
        local row = {}
        for lo = 0, 15 do
            local base = (hi + lo) * 256
            if is_ram(base) then row[#row + 1] = " W"
            elseif responds(base) then row[#row + 1] = " R"
            else row[#row + 1] = " ." end
        end
        print(string.format("        %04X %s", hi * 256, table.concat(row)))
    end
end

io:write_u8(0x00, 0x00)
classify_bank("bank 2 (ROM + I/O bank):")
io:write_u8(0x01, 0x00)
classify_bank("bank 1 (RAM bank):")

print(string.format("== %d passed, %d failed ==", npass, nfail))
os.exit(nfail == 0 and 0 or 1)
