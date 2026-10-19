//! The interposer's board — the glue logic between the Z80 bus and the MCU's
//! pins, as the emulator has to have it (#304, part of #192).
//!
//! # Why this file is here, and not in picoem or MAME
//!
//! The three layers, and the line between them:
//!
//! | Piece | Home |
//! |---|---|
//! | the RP2354B — core, SIO/GPIO, PIO | **picoem**, unchanged. It *is* the chip |
//! | the machine, its I/O decode, the wire | **MAME** + our patch |
//! | **the board — the 245, the 688, the 595, the 165, the pull-ups** | **here** |
//!
//! The 595 and the 165 are the *board*, not the chip: a shift fabric inside a chip
//! emulator would be the wrong layer, and picoem is a permanent fork (its tracker is
//! disabled and its PRs are refused), so every line added there is ours forever.
//! This file adds none. And the bridge is already the board — `chip.rs` drives the
//! strobes and the data as external stimulus, i.e. it already plays the Z80, the 245
//! and the board's pull-ups, and reads the answer back as the 245's Z80 side. The
//! 688, the 595 and the 165 are the same job.
//!
//! # The parts, and what each one does on the board
//!
//! `hardware/interposer-upgrade/revb/README.md` is the pin map; the mechanism is:
//!
//! - **74AHCT595** — serial in, parallel out, clocked by the firmware
//!   (`SR_MOSI`/`SR_SCK`, latched by `SR_RCK`, outputs enabled by `/OE_ADDR`). Its
//!   parallel outputs are the **match value** the comparator sees.
//! - **74AHCT688** — an identity comparator watching `A8–15` against the 595's
//!   outputs, driving **`ADDR_HIT`** (GP23) combinationally. It is what makes the
//!   live path need no address pins: the firmware programs a window and gets a
//!   single line saying "a cycle landed in it".
//! - **74AHCT165** — parallel in, serial out, clocked by the firmware
//!   (`SR_LOAD`/`SR_SCK` → `SR_MISO`). This is how the **full address** reaches the
//!   firmware: the 688 says *that* a cycle is in the window, the 165 says *where*.
//!   Rev B's README is explicit that the CPU "never knows it was slowed by
//!   microseconds" — the `/WAIT` stretch is what pays for this chain.
//!
//! # The widths are parameters, on purpose
//!
//! `hardware/interposer-upgrade/revb/` has a **README and no schematic** (`rev0/` and
//! `reva/` have `.kicad_sch`; `revb/` does not). So the *parts'* behaviour is
//! modelled from the datasheets and the widths are explicit parameters, defaulted to
//! the numbers the README implies — rather than hard-coding a wiring nobody has
//! drawn yet. When the schematic lands, the widths move here and the model is
//! checked against it; that is one constant, and the tests below pin the behaviour
//! either way.
//!
//! # It is testable without an emulator
//!
//! Every type here is pure logic over pin levels, so the whole board is unit-tested
//! by `cargo test` with no picoem, no firmware and no MAME — the same argument
//! `firmware/library/README.md` makes for its host harness.

/// The width of the 595/165 chain, in bits.
///
/// Rev B's README says "full address + data come from the 165 snapshot chain", which
/// implies at least 16 address + 8 data = 24. It is a parameter because the
/// schematic does not exist yet, and a wrong guess here would be a wiring claim
/// rather than a model.
pub const FABRIC_BITS: u32 = 24;

/// The bits the 688 compares: `A8–15`, eight of them.
pub const MATCH_BITS: u32 = 8;

/// The Rev B fabric pins (`hardware/interposer-upgrade/revb/README.md`, GP26–30).
pub const PIN_SR_SCK: u8 = 26;
/// The 165's serial output — an **input** to the chip, so the board drives it.
pub const PIN_SR_MISO: u8 = 27;
/// The 165's parallel load — an **output** from the chip, active low.
pub const PIN_SR_LOAD: u8 = 28;
/// The 595's serial input — an **output** from the chip.
pub const PIN_SR_MOSI: u8 = 29;
/// The 595's latch clock — an **output** from the chip.
pub const PIN_SR_RCK: u8 = 30;
/// The 688's combinational output — an **input** to the chip.
pub const PIN_ADDR_HIT: u8 = 23;
/// The 595's output enable — an **output** from the chip, active low.
pub const PIN_OE_ADDR: u8 = 31;

/// A 74AHCT595: serial in, parallel out.
///
/// Shifted by `SR_SCK`'s **rising** edge, transferred to the outputs by `SR_RCK`'s
/// rising edge, and driving only when `/OE_ADDR` is low. All three are modelled,
/// because all three are ways for a firmware to be wrong and only one of them is
/// obvious: a firmware that shifts and never latches has a match value of zero, and
/// one that latches with the outputs disabled has a comparator watching the
/// pull-downs.
#[derive(Debug, Clone, Copy, Default)]
pub struct Sr595 {
    shift: u32,
    out: u32,
    bits: u32,
    enabled: bool,
}

impl Sr595 {
    pub fn new(bits: u32) -> Sr595 {
        Sr595 { shift: 0, out: 0, bits, enabled: false }
    }

    fn mask(&self) -> u32 {
        if self.bits >= 32 { u32::MAX } else { (1u32 << self.bits) - 1 }
    }

    /// One `SR_SCK` rising edge: the bit on `SR_MOSI` enters the shift register.
    ///
    /// The first bit in ends up in the **highest** stage after `bits` clocks — the
    /// datasheet's order, and the order a firmware that sends MSB-first depends on.
    pub fn shift(&mut self, bit: bool) {
        self.shift = ((self.shift << 1) | u32::from(bit)) & self.mask();
    }

    /// One `SR_RCK` rising edge: the shift register becomes the outputs.
    pub fn latch(&mut self) {
        self.out = self.shift;
    }

    /// `/OE_ADDR`: low (true) drives the outputs, high leaves them to the pull-downs.
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }

    /// What the comparator sees. With the outputs disabled the lines are pulled
    /// down, so this reads 0 — which is a *value*, not an error, and a firmware that
    /// forgot `/OE_ADDR` gets a window it did not ask for.
    pub fn outputs(&self) -> u32 {
        if self.enabled { self.out } else { 0 }
    }

    /// The value in the shift register, latched or not — so a check can tell
    /// "shifted but not latched" from "not shifted at all".
    pub fn shifted(&self) -> u32 {
        self.shift
    }
}

/// A 74AHCT165: parallel in, serial out.
///
/// `SR_LOAD` is active **low**. While it is low the parallel inputs are presented
/// (so `QH` follows the MSB); the **rising** edge captures them and re-arms the shift
/// order; each `SR_SCK` rising edge then presents the next bit, **MSB first**, on
/// `SR_MISO`. Past the end the part shifts in its serial input, which is modelled as
/// zero — a real behaviour, and the reason a firmware that clocks too far reads
/// zeros rather than the last bit for ever.
#[derive(Debug, Clone, Copy, Default)]
pub struct Sr165 {
    value: u32,
    out: u32,
    bits: u32,
    loaded: bool,
    next: u32,
    level: bool,
}

impl Sr165 {
    pub fn new(bits: u32) -> Sr165 {
        Sr165 { value: 0, out: 0, bits, loaded: false, next: 0, level: false }
    }

    fn mask(&self) -> u32 {
        if self.bits >= 32 { u32::MAX } else { (1u32 << self.bits) - 1 }
    }

    /// The bit at shift position `i`, MSB first; zero past the end.
    fn bit_at(&self, i: u32) -> bool {
        if i >= self.bits {
            return false;
        }
        (self.out >> (self.bits - 1 - i)) & 1 != 0
    }

    /// What the parallel inputs are presented with — the address the machine is
    /// driving, plus the data byte and whatever else the chain carries.
    ///
    /// While `/PL` is low the part is **transparent**: the register follows the
    /// inputs and so does `QH`, which is why this has to move `level` too. The
    /// rising edge is what freezes it.
    pub fn set_inputs(&mut self, value: u32) {
        self.value = value & self.mask();
        if !self.loaded {
            self.out = self.value;
            self.level = self.bit_at(0);
        }
    }

    /// `/SR_LOAD`, as a pin: `asserted` is the pin being **low**, which is the state
    /// that makes the part transparent. Named for the pin's bar rather than for its
    /// level, because "`set_load(false)`" reads like "do not load" and means the
    /// opposite — which is exactly the mistake this model exists to catch in a
    /// firmware.
    ///
    /// Only transitions matter: while asserted the inputs are presented, and the
    /// release is the rising edge that captures them and restarts the order. Calling
    /// it repeatedly with the same state does nothing, which is what lets `Board`
    /// call it on every observation.
    pub fn load_bar(&mut self, asserted: bool) {
        if asserted {
            self.loaded = false;
            self.out = self.value & self.mask();
            self.next = 0;
            self.level = self.bit_at(0);
        } else if !self.loaded {
            self.out = self.value & self.mask();
            self.loaded = true;
            self.next = 0;
            self.level = self.bit_at(0);
        }
    }

    /// One `SR_SCK` rising edge. Inhibited while `/PL` is low — the part's own rule,
    /// and a way for a firmware to clock bits that never move.
    pub fn clock(&mut self) {
        if !self.loaded {
            return;
        }
        self.next += 1;
        self.level = self.bit_at(self.next);
    }

    /// The level on `SR_MISO` — what the board drives into the chip.
    pub fn level(&self) -> bool {
        self.level
    }

    /// How many bits have been clocked out since the load.
    pub fn shifted(&self) -> u32 {
        self.next
    }

    /// The value the chain captured.
    pub fn captured(&self) -> u32 {
        self.out
    }

    pub fn value(&self) -> u32 {
        self.value
    }
}

/// The 74AHCT688's job: is the address's high byte the value the 595 holds?
///
/// Combinational, so it follows the address and the 595 together — which is why the
/// live path costs no firmware time at all. `mask` is the bits the part actually
/// compares (`0xFF` for `A8–15`).
pub fn cmp688(address: u16, match_value: u32, mask: u32) -> bool {
    (u32::from(address >> 8) & mask) == (match_value & mask)
}

/// The board, as the bridge drives it: the two shift registers, the comparator, and
/// the pin levels that make edges edges.
///
/// [`Board::observe`] is the whole interface to the emulator — hand it the chip's
/// output levels after every emulated step and it does the rest, which is the same
/// shape as `Chip::merged_out()`: one word in, and [`Board::stimulus`] one word out.
///
/// **One consequence of the emulator's resolution, stated rather than hidden.** A
/// step is a whole quantum (64 cycles, `chip.rs`), so two pin changes inside one
/// quantum are seen as their net level and their *order* is lost. The fabric is
/// therefore modelled at quantum resolution, which means the firmware has to hold
/// each level for at least one quantum — 2.3 MHz at 150 MHz, comfortably inside the
/// 74AHCT parts' own limits, and the second place the quantum shows up as a design
/// constraint (the first is `ACB4000_CYCLE_BUDGET`). The alternative is stepping the
/// chip one instruction at a time, which the settle would never finish.
#[derive(Debug, Clone)]
pub struct Board {
    /// The 595: the match value the 688 compares against.
    pub match_reg: Sr595,
    /// The 165: the address (and data) snapshot the firmware reads back.
    pub chain: Sr165,
    /// The address the machine is driving *this* cycle.
    address: u16,
    /// Is this a memory cycle? The 688 watches bank-2 status as well as `A8–15`.
    memory: bool,
    /// The chip's output levels at the last observation, for edge detection.
    prev_sck: bool,
    prev_rck: bool,
    prev_load: bool,
    /// Counters, so a check can tell "the firmware never clocked it" from "the
    /// firmware clocked it and the value was wrong".
    pub sck_edges: u64,
    pub latches: u64,
    pub loads: u64,
}

impl Default for Board {
    fn default() -> Board {
        Board::new()
    }
}

impl Board {
    pub fn new() -> Board {
        Board {
            match_reg: Sr595::new(MATCH_BITS),
            chain: Sr165::new(FABRIC_BITS),
            address: 0,
            memory: false,
            prev_sck: false,
            prev_rck: false,
            prev_load: false,
            sck_edges: 0,
            latches: 0,
            loads: 0,
        }
    }

    /// The machine is driving this address, this data byte, and this kind of cycle.
    pub fn set_cycle(&mut self, address: u16, data: u8, memory: bool) {
        self.address = address;
        self.memory = memory;
        // What the 165's parallel inputs see: the address, then the data byte.
        self.chain
            .set_inputs(u32::from(address) | (u32::from(data) << 16));
    }

    pub fn address(&self) -> u16 {
        self.address
    }

    pub fn is_memory(&self) -> bool {
        self.memory
    }

    /// `ADDR_HIT` — combinational, so it follows the address and the 595's outputs
    /// together and costs the firmware no time at all.
    pub fn addr_hit(&self) -> bool {
        cmp688(self.address, self.match_reg.outputs(), 0xFF)
    }

    /// What the board drives into the chip, as the external-stimulus overlay's
    /// `(mask, value)`. Both lines are bank 0, so no `_hi` companion is needed.
    pub fn stimulus(&self) -> (u32, u32) {
        let mut mask = 0u32;
        let mut value = 0u32;

        mask |= 1 << PIN_ADDR_HIT;
        if self.addr_hit() {
            value |= 1 << PIN_ADDR_HIT;
        }
        mask |= 1 << PIN_SR_MISO;
        if self.chain.level() {
            value |= 1 << PIN_SR_MISO;
        }

        (mask, value)
    }

    /// One observation of the chip's own output levels. Every edge the firmware makes
    /// moves the board.
    pub fn observe(&mut self, chip_out: u32) {
        let sck = bit(chip_out, PIN_SR_SCK);
        let rck = bit(chip_out, PIN_SR_RCK);
        let load = bit(chip_out, PIN_SR_LOAD);
        let mosi = bit(chip_out, PIN_SR_MOSI);

        // The 165's load pin first: it gates the shared clock, so a firmware that
        // clocks while `/PL` is asserted gets nothing — which is the part's
        // behaviour and not a special case here.
        self.chain.load_bar(!load);
        if load && !self.prev_load {
            self.loads += 1;
        }

        if sck && !self.prev_sck {
            self.sck_edges += 1;
            self.match_reg.shift(mosi);
            self.chain.clock();
        }
        if rck && !self.prev_rck {
            self.latches += 1;
            self.match_reg.latch();
        }
        self.match_reg.set_enabled(!bit(chip_out, PIN_OE_ADDR));

        self.prev_sck = sck;
        self.prev_rck = rck;
        self.prev_load = load;
    }
}

/// One bit of an output word.
fn bit(word: u32, pin: u8) -> bool {
    (word >> pin) & 1 != 0
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A chip output word, as the firmware would leave the pins.
    fn pins(sck: bool, mosi: bool, rck: bool, load_high: bool, oe_high: bool) -> u32 {
        let mut w = 0u32;
        if sck {
            w |= 1 << PIN_SR_SCK;
        }
        if mosi {
            w |= 1 << PIN_SR_MOSI;
        }
        if rck {
            w |= 1 << PIN_SR_RCK;
        }
        if load_high {
            w |= 1 << PIN_SR_LOAD;
        }
        if oe_high {
            w |= 1 << PIN_OE_ADDR;
        }
        w
    }

    /// One `SR_SCK` rising edge with `mosi` presented — as a firmware makes it.
    fn clock_edge(b: &mut Board, mosi: bool) {
        b.observe(pins(false, mosi, false, true, false));
        b.observe(pins(true, mosi, false, true, false));
    }

    /// Program the 595 MSB-first, exactly as a firmware has to.
    fn program(b: &mut Board, value: u32, bits: u32, latch: bool) {
        for i in (0..bits).rev() {
            clock_edge(b, (value >> i) & 1 != 0);
        }
        if latch {
            b.observe(pins(false, false, false, true, false));
            b.observe(pins(false, false, true, true, false));
        }
    }

    #[test]
    fn the_595_does_not_reach_the_comparator_until_it_is_latched() {
        // The first way a firmware is wrong, and it is invisible: the bits are in,
        // the outputs are not, and the comparator silently sees zero.
        let mut b = Board::new();
        program(&mut b, 0x30, MATCH_BITS, false);

        assert_eq!(b.match_reg.shifted(), 0x30, "the bits are in the shift register");
        assert_eq!(b.match_reg.outputs(), 0, "the outputs have not taken them");
        b.set_cycle(0x3000, 0, true);
        assert!(!b.addr_hit(), "so a matching address does not hit");

        b.observe(pins(false, false, false, true, false));
        b.observe(pins(false, false, true, true, false)); // RCK rising
        assert_eq!(b.latches, 1);
        assert_eq!(b.match_reg.outputs(), 0x30, "the latch is what publishes it");
        assert!(b.addr_hit(), "and now it hits");
    }

    #[test]
    fn a_disabled_595_reads_as_the_pull_downs() {
        // The second way, and the one that produces a window nobody asked for: the
        // outputs are Hi-Z, the pull-downs win, and the comparator watches zero.
        let mut b = Board::new();
        program(&mut b, 0x30, MATCH_BITS, true);
        assert_eq!(b.match_reg.outputs(), 0x30);

        b.observe(pins(false, false, false, true, /* oe_high */ true));
        assert_eq!(
            b.match_reg.outputs(),
            0,
            "/OE_ADDR high leaves the outputs to the pull-downs"
        );

        b.set_cycle(0x0000, 0, true);
        assert!(b.addr_hit(), "and the window is now page zero, not page 30h");
    }

    #[test]
    fn the_688_compares_eight_bits_and_therefore_a_page() {
        // A finding rather than a detail: the 688 watches A8-A15, so the "window" is
        // a 256-byte page. Anything finer is the 165's job.
        let mut b = Board::new();
        program(&mut b, 0x30, MATCH_BITS, true);

        b.set_cycle(0x3000, 0, true);
        assert!(b.addr_hit(), "A8-A15 = 30h matches");
        b.set_cycle(0x30FF, 0, true);
        assert!(b.addr_hit(), "... anywhere in the page");
        b.set_cycle(0x3100, 0, true);
        assert!(!b.addr_hit(), "and 31h does not");
        b.set_cycle(0x2FFF, 0, true);
        assert!(!b.addr_hit(), "nor 2Fh");
    }

    #[test]
    fn the_688_cannot_select_an_io_port_and_that_is_why_the_165_exists() {
        // **The finding this model was worth writing for.** On a Z80 I/O cycle the
        // high half of the address bus is not the port: for `OUT (n),A` it is the
        // accumulator, and for `OUT (C),r` and the block moves it is `B`. So a
        // comparator on A8-A15 cannot select a port at all — it selects a *page of
        // memory* — and the ACB-4000's four registers at base 30h are told apart by
        // A0-A7, which only the 165 can hand over.
        //
        // The consequence, and the reason #303 is a decision rather than a pin edit:
        // a register-selected personality is **/IORQ plus a 165 snapshot per I/O
        // cycle**, not a window hit. `hardware/interposer-upgrade/revb/README.md` describes
        // the 688 as the live path, which is true for the *memory* windows (the ROM
        // window, Drive C, the bank-2 door at 2800h) and misleading for I/O ports.
        let mut b = Board::new();
        program(&mut b, 0x00, MATCH_BITS, true); // an I/O page: A8-A15 = 0

        let mut hits = Vec::new();
        for port in [0x30u16, 0x31, 0x32, 0x33] {
            // `OUT (n),A` with A = 0: the high byte is the accumulator, so it is 0.
            b.set_cycle(port, 0, false);
            hits.push(b.addr_hit());
        }
        assert_eq!(
            hits,
            vec![true, true, true, true],
            "all four registers hit the same window, so the window tells the firmware nothing"
        );

        // And it is worse than useless, because the hit moves with the *data*: the
        // address bus during `OUT (n),A` is `n` on A0-A7 and the **accumulator** on
        // A8-A15, so the same port with a different byte in `A` is a different high
        // byte and the window stops matching.
        b.set_cycle(0xA530, 0xA5, false); // `OUT (30h),A` with A = A5h
        assert!(
            !b.addr_hit(),
            "the same port, a different accumulator, no hit -- the window tracks the data"
        );
    }

    #[test]
    fn the_165_presents_the_msb_the_moment_it_loads() {
        let mut c = Sr165::new(24);
        c.set_inputs(0x00_8000);
        c.load_bar(true); // /PL asserted: the part is transparent
        assert!(!c.level(), "while /PL is asserted it follows the MSB, 0 here");
        c.set_inputs(0x80_0000);
        assert!(c.level(), "... and follows it as the inputs move");

        c.load_bar(false); // the release captures
        assert!(c.level(), "QH is the captured MSB, before any clock");
        assert_eq!(c.shifted(), 0);
    }

    #[test]
    fn the_165_shifts_msb_first_and_then_zeros() {
        let mut c = Sr165::new(4);
        c.set_inputs(0b1001);
        c.load_bar(true);
        c.load_bar(false);

        let mut bits = Vec::new();
        for _ in 0..4 {
            bits.push(c.level());
            c.clock();
        }
        assert_eq!(bits, vec![true, false, false, true], "MSB first, in order");
        assert_eq!(c.shifted(), 4);

        // Past the end the part shifts in its serial input, modelled as zero: a
        // firmware that clocks too far reads zeros, not the last bit for ever.
        for _ in 0..3 {
            assert!(!c.level(), "past the end");
            c.clock();
        }
    }

    #[test]
    fn the_165_does_not_clock_while_load_is_low() {
        // The part's own inhibition, and a firmware bug that looks like a wiring
        // fault: clocking with /PL low moves nothing.
        let mut b = Board::new();
        b.chain.set_inputs(0x12_3456);
        b.chain.load_bar(false);
        let before = b.chain.shifted();

        // /PL held low, SCK rising twice.
        b.observe(pins(false, false, false, false, false));
        b.observe(pins(true, false, false, false, false));
        b.observe(pins(false, false, false, false, false));
        b.observe(pins(true, false, false, false, false));

        assert_eq!(b.chain.shifted(), before, "the clocks were inhibited");
        assert_eq!(b.sck_edges, 2, "but they were seen -- the count says so");
    }

    #[test]
    fn the_board_remembers_the_cycle_it_was_given() {
        let mut b = Board::new();
        b.set_cycle(0x2800, 0x5A, true);
        assert_eq!(b.address(), 0x2800, "the address the machine is driving");
        assert!(b.is_memory(), "and the kind of cycle it is");
        assert_eq!(
            b.chain.value(),
            0x5A_2800,
            "the chain's parallel inputs carry the address and the data byte"
        );

        b.set_cycle(0x30, 0, false);
        assert!(!b.is_memory(), "an I/O cycle is not a memory cycle");
        assert_eq!(b.chain.value(), 0x30);
    }

    #[test]
    fn the_board_drives_addr_hit_from_the_programmed_window() {
        // The whole point of the 595 and the 688, end to end through `observe`.
        let mut b = Board::new();
        program(&mut b, 0x28, MATCH_BITS, true); // the bank-2 door's page

        b.set_cycle(0x2800, 0, true);
        let (mask, value) = b.stimulus();
        assert_ne!(mask & (1 << PIN_ADDR_HIT), 0, "the board drives ADDR_HIT");
        assert_ne!(value & (1 << PIN_ADDR_HIT), 0, "and it is asserted in the window");

        b.set_cycle(0x2700, 0, true);
        let (_, value) = b.stimulus();
        assert_eq!(value & (1 << PIN_ADDR_HIT), 0, "and clear outside it");
    }

    #[test]
    fn the_board_shifts_the_address_out_to_the_firmware() {
        // The other half of the contract: the firmware asks the 165 where the cycle
        // was, and gets the address and the data byte back, bit for bit.
        let mut b = Board::new();
        b.set_cycle(0x30A5, 0x5A, false);

        b.observe(pins(false, false, false, /* /PL asserted */ false, false));
        b.observe(pins(false, false, false, /* released: the capture */ true, false));

        assert_eq!(
            b.chain.captured(),
            0x00_30A5 | (0x5Au32 << 16),
            "the release captured the address and the data byte"
        );
        assert_eq!(b.chain.value(), b.chain.captured(), "and the inputs still present it");

        let mut got = 0u32;
        for _ in 0..FABRIC_BITS {
            got = (got << 1) | u32::from(b.chain.level());
            b.observe(pins(false, false, false, true, false));
            b.observe(pins(true, false, false, true, false)); // SCK rising
        }

        assert_eq!(
            got,
            0x00_30A5 | (0x5Au32 << 16),
            "the address in A0-A15 and the data byte above it, MSB first"
        );
    }
}
