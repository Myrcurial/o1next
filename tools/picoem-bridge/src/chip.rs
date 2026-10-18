//! The emulated RP2354B, and the bus cycle it is asked to answer (#286).
//!
//! # The finding this file exists because of
//!
//! #192's open question was "does `rp2350-emu` expose a public API to observe or
//! drive the emulated chip's GPIO/PIO/bus from outside the crate?" The answer,
//! read out of the pinned commit's public surface, is **yes, three of them**,
//! and no patch to picoem is needed:
//!
//!   - `Emulator::gpio_read(pin)` / `gpio_read_all()` -- observe the merged pin
//!     state. `gpio_read_all()` is a 48-bit word, bank 1 in bits 32..47.
//!   - `Emulator::bus` is a **public field** and `Bus::gpio_external_in` /
//!     `gpio_external_mask` (and their `_hi` companions, plus
//!     `Bus::set_gpio_external_in_hi`) are **public fields and methods**. That
//!     is the external stimulus overlay `update_gpio` applies last: masked bits
//!     of `gpio_in` come from the host instead of from SIO/PIO. It is the same
//!     mechanism picoem's own OneROM harness uses to drive an address bus from
//!     outside (see its HLD "OneROM Serving Oracle Fixture Generalization",
//!     where A0..A2 are driven through `set_gpio_external_in_hi`).
//!   - `Emulator::mmio_read32` / `mmio_write32`, `peek` / `poke` -- the
//!     memory-mapped peripheral level, for anything the overlay does not cover.
//!
//! Two things are *not* there, and both are worth knowing:
//!
//!   - `Emulator::gpio_write(pin, value)` is an **explicit no-op stub** in this
//!     commit (`pub fn gpio_write(&mut self, _pin: u8, _value: bool) {}`). The
//!     way to drive an input pin is the external-stimulus overlay above, not
//!     this call. Anything that trusts the name instead of reading it will
//!     spend an afternoon wondering why its stimulus does nothing.
//!   - `Bus::gpio_external_mask` is a **plain `u32` field, not an atomic**, so
//!     it is written through `&mut Emulator` while `gpio_external_in` is an
//!     atomic. That is fine for this bridge, which owns the emulator and drives
//!     it single-threaded; it is not fine for a design that steps the emulator
//!     on one thread and pokes pins from another. This is why the bridge is a
//!     **process that owns the chip**, not a device inside MAME.
//!
//! # Reading the answer
//!
//! The external overlay masks bits of `gpio_in`, so during the part of a cycle
//! where the host is driving the data pins, `gpio_in` holds the *host's* byte
//! and the chip's own answer is invisible there. `merged_out()` recomputes the
//! word the chip is *driving* -- SIO `gpio_out & gpio_oe`, with each PIO block's
//! `pad_out & pad_oe` overlaid -- from public fields only, exactly as
//! `Emulator::update_gpio` does internally. That is the measurement: the byte
//! the firmware put on the bus, read from outside the crate.

use std::sync::atomic::Ordering;

/// How the chip is started.
///
/// **The bootrom path does not work at this pin, and that is measured, not
/// assumed.** `crates/rp2350-emu/src/tests.rs::test_flash_boot_blinky` is
/// `#[ignore]`d in the pinned commit with the reason: the bootrom's first
/// `rcp_iequal` mismatch is at `PC=0x000039b6` inside `___step4_init_rcp_seeds`
/// -- picoem's CP7 canary/count state does not match silicon, so the bootrom
/// stops before it ever looks at flash. Reproduced here: 40 M cycles of settle
/// leaves PC at `0x000003ee`, inside the mask ROM, forever.
///
/// So the default is [`Entry::Image`]: take the initial SP and the reset vector
/// from the flash image's own vector table and set them on the core. That is
/// what the bootrom would have done, word for word -- the SDK's image for this
/// chip begins with the vector table at offset 0, because the chip has no boot2
/// stage -- and it is what picoem's own `hello_*` tests do for their RAM images.
/// `Entry::Bootrom` keeps the real path reachable so that the day the CP7 work
/// lands, "does it boot through the bootrom yet?" is one flag, not a rewrite.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Entry {
    /// Start the core at the image's reset vector (the default).
    Image,
    /// Start at the mask ROM's reset vector and let the bootrom boot flash.
    Bootrom,
}

use rp2350_emu::{Config, Emulator, EmulatorError};

use crate::frame;

/// The Rev B pin map (hardware/interposer/revb/README.md), in one place.
pub const PIN_MREQ: u8 = 8;
pub const PIN_IORQ: u8 = 9;
pub const PIN_RD: u8 = 10;
pub const PIN_WR: u8 = 11;
pub const PIN_DATA_OE: u8 = 24;
/// The heartbeat pin. GP26, not the Rev B map's spare GP37, because picoem's
/// SIO models GPIO bank 0 only -- see `firmware/picoem-smoke/smoke.c`.
pub const PIN_HB: u8 = 26;

const CTRL_MASK: u32 = 0x0000_0F00; // GP8-GP11
const DATA_MASK: u32 = 0x0000_00FF; // GP0-GP7

/// What one bus transaction observed.
#[derive(Debug, Clone, Copy)]
pub struct Tx {
    /// The byte the chip drove on GP0-GP7 at the end of the transaction.
    pub data: u8,
    /// GP37 edges seen during the transaction. 1 = the firmware handled it.
    pub hb: u8,
    /// `frame::REPLY_*` bits.
    pub flags: u8,
    pub pc: u32,
    pub cycles: u64,
}

/// The chip's merged output word: what SIO and the PIO blocks are driving.
struct Out {
    lo: u32,
    oe_lo: u32,
}

pub struct Chip {
    emu: Emulator,
    cycles_per_phase: u64,
}

/// The image's own vector table: initial SP in word 0, reset vector in word 1.
///
/// Both are checked against the addresses they have to be for an RP2354B image
/// -- SP at the top of SRAM, reset vector in the XIP window with the Thumb bit
/// set -- so a wrong file is refused here rather than executing as garbage.
fn image_entry(flash: &[u8]) -> Option<(u32, u32)> {
    if flash.len() < 8 {
        return None;
    }
    let sp = u32::from_le_bytes([flash[0], flash[1], flash[2], flash[3]]);
    let reset = u32::from_le_bytes([flash[4], flash[5], flash[6], flash[7]]);
    let sp_ok = (0x2000_0000..=0x2008_2000).contains(&sp);
    let reset_ok = reset & 1 == 1 && (0x1000_0000..0x2000_0000).contains(&reset);
    (sp_ok && reset_ok).then_some((sp, reset & !1))
}

/// The Rev B control strobes, as an external-stimulus value.
fn ctrl(mreq: u32, iorq: u32, rd: u32, wr: u32) -> u32 {
    (mreq << PIN_MREQ) | (iorq << PIN_IORQ) | (rd << PIN_RD) | (wr << PIN_WR)
}

impl Chip {
    pub fn new(bootrom: &[u8], flash: &[u8], cycles_per_phase: u64, entry: Entry) -> Chip {
        Self::with_quantum(bootrom, flash, cycles_per_phase, entry, None)
    }

    /// `quantum` of `Some(1)` makes every `step_one()` a single instruction,
    /// which is what `--trace-fault` needs to name the faulting address.
    pub fn with_quantum(
        bootrom: &[u8],
        flash: &[u8],
        cycles_per_phase: u64,
        entry: Entry,
        quantum: Option<u32>,
    ) -> Chip {
        let mut emu = match quantum {
            Some(n) => rp2350_emu::EmulatorBuilder::new(Config::default())
                .step_quantum(n)
                .build()
                .expect("Serial build is infallible"),
            None => Emulator::new(Config::default()),
        };
        emu.load_bootrom(bootrom);
        emu.load_flash(flash);
        emu.reset();
        // The firmware under test is single-core; core 1 parked is the same
        // thing the picoem TUI does with a plain firmware image.
        emu.core_mut(1).halt();

        if entry == Entry::Image {
            let (sp, pc) = image_entry(flash).unwrap_or_else(|| {
                panic!(
                    "the flash image has no RP2354B vector table at offset 0 \
                     (first 8 bytes: {:02X?}) -- is it an image built for this chip?",
                    &flash[..flash.len().min(8)]
                )
            });
            let arm = emu.cores.expect_arm_mut();
            for core in arm.iter_mut() {
                // The bootrom's hand-over includes turning the coprocessors on,
                // and bypassing it means doing that here. Without this the SDK's
                // *first* runtime initializer -- which calls the ROM's `reset`
                // function, whose first instruction is `mrc2 p7, ...` -- takes a
                // UsageFault on a disabled CP7 and the firmware never starts.
                //
                // The trap: picoem sets UFSR.UNDEFINSTR for *every* UsageFault
                // (`core/exceptions.rs`), so this arrives looking like an
                // undefined instruction at a bootrom address, and the honest
                // reading of it is not the true one. CPACR, not the opcode, is
                // what to check first.
                for cp in 0..=7u8 {
                    core.enable_coprocessor(cp);
                }
                core.enable_coprocessor(10); // FPU
                core.enable_coprocessor(11);
            }
            arm[0].regs.msp = sp;
            arm[0].regs.r[13] = sp;
            arm[0].regs.set_pc(pc);
            arm[0].regs.xpsr = 1 << 24; // Thumb bit
        }

        Chip { emu, cycles_per_phase }
    }

    /// A one-line snapshot of the core: PC, SP, and the fault state. The fault
    /// registers are here because "the PC is not in the firmware" and "the
    /// firmware faulted" look identical from outside, and they are not.
    pub fn describe(&self) -> String {
        let c = self.emu.core(0);
        let fault_addr = if self.emu.bus.bus_fault(0) {
            format!(" bfar={:#010x}", self.emu.bus.bus_fault_addr(0))
        } else {
            String::new()
        };
        format!(
            "pc={:#010x} sp={:#010x} lr={:#010x} ipsr={} cfsr={:#010x} hfsr={:#010x}{} \
             sio_out={:#010x} sio_oe={:#010x} gpio_in={:#010x} cycles={} firmware_running={}",
            c.regs.pc(),
            c.regs.r[13],
            c.regs.r[14],
            c.regs.ipsr(),
            c.ppb.cfsr,
            c.ppb.hfsr,
            fault_addr,
            self.emu.bus.sio.gpio_out,
            self.emu.bus.sio.gpio_oe,
            self.emu.gpio_read_all() as u32,
            self.cycles(),
            self.firmware_running()
        )
    }

    /// Has either core latched a fault? `CFSR` is the specific cause, `HFSR` the
    /// escalation to HardFault; either being non-zero is the answer to "why is
    /// the PC not in the firmware?".
    pub fn faulted(&self) -> bool {
        let c = self.emu.core(0);
        c.ppb.cfsr != 0 || c.ppb.hfsr != 0
    }

    pub fn cfsr(&self) -> u32 {
        self.emu.core(0).ppb.cfsr
    }

    pub fn hfsr(&self) -> u32 {
        self.emu.core(0).ppb.hfsr
    }

    /// Advance by one step. With the quantum set to 1 (see `--trace-fault`) this
    /// is one instruction, which is what makes the fault address exact.
    pub fn step_one(&mut self) -> Result<(), EmulatorError> {
        self.emu.step()?;
        Ok(())
    }

    /// Run the chip with no bus cycle in progress, to let the bootrom and the
    /// firmware's own startup reach `main()`.
    ///
    /// **The idle state has to be *driven*, not left alone.** An undriven pin
    /// reads 0 in picoem exactly as it does on a board with no pull-up, and 0 is
    /// "asserted" for /MREQ, /IORQ, /RD and /WR -- every one of them active low.
    /// A bridge that simply leaves the pins floating therefore presents the
    /// firmware with a write cycle that never ends, and the firmware sits in its
    /// `/WR` release loop forever. Measured: the first version of this file did
    /// exactly that, and the smoke firmware blocked at PC 0x100002d8 with no
    /// fault and no bus activity, which looks like a firmware bug and is not.
    /// On Rev B the same job is done by the board's pull-ups.
    pub fn settle(&mut self, cycles: u64) -> Result<(), EmulatorError> {
        self.idle();
        self.emu.run(cycles)?;
        Ok(())
    }

    pub fn pc(&self) -> u32 {
        self.emu.core(0).regs.pc()
    }

    pub fn lr(&self) -> u32 {
        self.emu.core(0).regs.r[14]
    }

    pub fn sp(&self) -> u32 {
        self.emu.core(0).regs.r[13]
    }

    pub fn cycles(&self) -> u64 {
        self.emu.cycles()
    }

    /// Is the PC somewhere the firmware can be? XIP flash or SRAM -- anywhere
    /// else means the bootrom is still running, or the cores have stopped.
    /// The SRAM bound is inclusive: the initial SP is exactly the top of SRAM.
    pub fn firmware_running(&self) -> bool {
        let pc = self.pc();
        (0x1000_0000..0x2000_0000).contains(&pc) || (0x2000_0000..=0x2008_2000).contains(&pc)
    }

    /// A whole Z80 I/O write: drive the byte with /IORQ and /WR low, sample the
    /// chip's answer *while the strobe is still open* -- which is when a real
    /// Z80 samples it -- then end the cycle and let the firmware go back to idle.
    pub fn bus_write(&mut self, data: u8, cycles: u64) -> Result<Tx, EmulatorError> {
        let cycles = self.phase(cycles);

        // Phase A: the Z80 owns the data bus; the chip answers on its own pins.
        self.set_ext(CTRL_MASK | DATA_MASK, ctrl(1, 0, 1, 0) | (data as u32));
        let hb = self.run_counting_heartbeat(cycles)?;
        let tx = self.observe(hb);

        // Phase B: /WR rises, the Z80 stops driving, and the data pins go back
        // to the chip. This is the turnaround a real 74AHCT245 does, and it is
        // what lets the firmware leave its hold loop and re-arm.
        self.set_ext(CTRL_MASK, ctrl(1, 1, 1, 1));
        self.emu.run(cycles)?;

        Ok(tx)
    }

    /// A whole Z80 I/O read: /IORQ and /RD low, the chip driving the data bus,
    /// and the answer sampled while the strobe is open. The data pins are
    /// deliberately *not* masked here -- the chip owns them.
    pub fn bus_read(&mut self, cycles: u64) -> Result<Tx, EmulatorError> {
        let cycles = self.phase(cycles);

        self.set_ext(CTRL_MASK, ctrl(1, 0, 0, 1));
        let hb = self.run_counting_heartbeat(cycles)?;
        let tx = self.observe(hb);

        self.set_ext(CTRL_MASK, ctrl(1, 1, 1, 1));
        self.emu.run(cycles)?;

        Ok(tx)
    }

    /// The bus idle: every control strobe released high, the data pins left to
    /// the chip. This is the state the firmware must see whenever there is no
    /// cycle, including before the first one.
    pub fn idle(&mut self) {
        self.set_ext(CTRL_MASK, ctrl(1, 1, 1, 1));
        self.emu.bus.set_gpio_external_in_hi(0, 0);
    }

    /// What the firmware would read at SIO GPIO_IN (0xD0000004), with the
    /// harness's own stimulus applied.
    ///
    /// This is the bridge checking itself: if the stimulus does not reach this
    /// view, no firmware can see it, and "the firmware never answered" is the
    /// harness's fault rather than the firmware's.
    ///
    /// It drives the **data pins only** and leaves every strobe idle, so it
    /// proves the overlay without starting a bus cycle. An earlier version
    /// asserted /IORQ and /WR to "make it a real cycle", and the firmware --
    /// correctly -- consumed that cycle; the transaction that followed then
    /// found it already inside its /WR hold loop and reported no heartbeat. A
    /// probe that changes the thing it is measuring is not a probe.
    pub fn probe_stimulus(&mut self, data: u8) -> u32 {
        self.set_ext(CTRL_MASK | DATA_MASK, ctrl(1, 1, 1, 1) | (data as u32));
        let _ = self.emu.run(64);
        let seen = self.emu.mmio_read32(0xD000_0004);
        self.idle();
        let _ = self.emu.run(64);
        seen
    }

    fn phase(&self, requested: u64) -> u64 {
        if requested == 0 { self.cycles_per_phase } else { requested }
    }

    fn set_ext(&mut self, mask: u32, value: u32) {
        self.emu.bus.gpio_external_mask = mask;
        self.emu.bus.gpio_external_in.store(value, Ordering::Relaxed);
    }

    /// Run `cycles`, sampling GP37 as we go, and return the number of edges.
    ///
    /// The heartbeat is the liveness signal, and sampling it only at the ends
    /// of a phase would miss an even number of toggles. The phase is therefore
    /// run in chunks and the level compared between them.
    fn run_counting_heartbeat(&mut self, cycles: u64) -> Result<u8, EmulatorError> {
        const CHUNKS: u64 = 32;
        let chunk = (cycles / CHUNKS).max(1);
        let mut remaining = cycles;
        let mut edges = 0u8;
        let mut prev = self.hb_level();
        while remaining > 0 {
            let n = chunk.min(remaining);
            self.emu.run(n)?;
            remaining -= n;
            let now = self.hb_level();
            if now != prev {
                edges = edges.saturating_add(1);
                prev = now;
            }
        }
        Ok(edges)
    }

    fn hb_level(&self) -> bool {
        (self.emu.gpio_read_all() >> PIN_HB) & 1 != 0
    }

    fn observe(&self, hb: u8) -> Tx {
        let out = self.merged_out();
        let mut flags = 0u8;
        if self.hb_level() {
            flags |= frame::REPLY_HEARTBEAT;
        }
        if (out.lo >> PIN_DATA_OE) & 1 != 0 {
            flags |= frame::REPLY_DATA_OE;
        }
        if out.oe_lo & DATA_MASK != 0 {
            flags |= frame::REPLY_DRIVEN;
        }
        Tx {
            data: (out.lo & DATA_MASK) as u8,
            hb,
            flags,
            pc: self.pc(),
            cycles: self.cycles(),
        }
    }

    /// What the chip is driving, recomputed from public fields.
    fn merged_out(&self) -> Out {
        let sio = &self.emu.bus.sio;
        let mut lo = sio.gpio_out & sio.gpio_oe;
        let mut oe_lo = sio.gpio_oe;
        for pio in &self.emu.bus.pio {
            let (pio_out, _) = pio.local_to_physical_pins(pio.pad_out);
            let (pio_oe, _) = pio.local_to_physical_pins(pio.pad_oe);
            lo = (lo & !pio_oe) | (pio_out & pio_oe);
            oe_lo = (oe_lo & !pio_oe) | pio_oe;
        }
        Out { lo, oe_lo }
    }
}
