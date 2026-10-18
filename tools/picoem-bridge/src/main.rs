//! picoem-bridge -- the host half of the picoem bridge (#286, part of #192).
//!
//! A real RP2354B firmware image runs inside `rp2350-emu`; this process owns
//! that emulator and answers the bus cycles MAME's `osborne1nx` sends it.  See
//! `docs/picoem-bridge.md` for the shape, `src/chip.rs` for the finding that
//! made it possible, and `src/fifo.rs` for why the channel is a FIFO and not
//! the socket #192 assumed.
//!
//! ```text
//!   osborne1nx (MAME)                    picoem-bridge (this process)
//!   +--------------------+               +------------------------------+
//!   | Z80 OUT/IN 30h-33h |               | rp2350-emu, one Emulator     |
//!   |  tap -> 24-byte    |--> in FIFO -->|  gpio_external_* = the Z80   |
//!   |  frame             |<- out FIFO <--|  gpio_out/oe  = the answer   |
//!   +--------------------+               +------------------------------+
//! ```
//!
//! `--self-test` needs no MAME and no FIFOs: it proves the firmware binary runs
//! and answers a bus cycle, which is the half of the acceptance that has
//! nothing to do with MAME.  Without it, the process opens the FIFOs and
//! serves frames until `--frames N` have been answered or the peer goes away.

mod chip;
mod fifo;
mod frame;

use std::fs::File;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use chip::Chip;
use frame::{Reply, Request, ST_BAD_REQUEST, ST_NO_FIRMWARE, ST_OK};

/// Where the two FIFOs live by default. A fixed, documented rendezvous is the
/// point: MAME's Lua side has to be able to find it without being told.
const DEFAULT_IN: &str = "/tmp/o1next-picoem/in";
const DEFAULT_OUT: &str = "/tmp/o1next-picoem/out";

/// Cycles to run the chip for each phase of a bus transaction. The firmware is
/// a polled loop, so this only has to be longer than one iteration of it; it is
/// generous because the cost is emulated, not wall-clock.
const DEFAULT_CYCLES: u64 = 20_000;

/// Cycles to run before the first bus cycle, to let the bootrom and the
/// firmware's own startup reach `main()`. The bootrom SHA-256s the image in
/// software, so this is not a small number.
const DEFAULT_SETTLE: u64 = 40_000_000;

struct Args {
    flash: PathBuf,
    bootrom: PathBuf,
    in_path: PathBuf,
    out_path: PathBuf,
    cycles: u64,
    settle: u64,
    frames: Option<u64>,
    log: Option<PathBuf>,
    self_test: bool,
    entry: chip::Entry,
    trace_fault: bool,
}

const USAGE: &str = "\
picoem-bridge -- run an RP2354B firmware image in picoem and answer MAME's bus cycles (#286)

  --flash FILE      the firmware's flash image (XIP at 0x10000000).  Required.
                    firmware/picoem-smoke/build.sh makes one.
  --bootrom FILE    the 32 KB mask ROM.  picoem ships it at
                    roms/rp2350/bootrom-combined.bin in its own tree; it is the
                    real Pi bootrom, which is why it is not in this repo.
  --in FIFO         requests come from here      (default $O1_PICOEM_IN or
  --out FIFO        replies go to here            /tmp/o1next-picoem/{in,out})
  --cycles N        emulated cycles per bus-cycle phase (default 20000)
  --settle N        emulated cycles before the first bus cycle (default 40000000)
  --frames N        answer N requests and exit (default: until the peer goes away)
  --log FILE        also write the transaction log here
  --self-test       no FIFOs, no MAME: boot the firmware, drive one write cycle
                    and one read cycle, print what the chip drove, and exit 0
                    only if the round trip worked
  --via-bootrom     start the core at the mask ROM's reset vector instead of at
                    the image's.  This does NOT work at the pinned picoem commit
                    (its bootrom path is broken -- src/chip.rs has the
                    evidence); the flag exists so that finding stays testable.
  --trace-fault     one instruction per step, until the core latches a fault,
                    then print the faulting PC and the fault registers.  This is
                    the tool for 'the firmware did not start and I do not know
                    why'; it is slow (one instruction per step) and short-lived.
  -h, --help        this text

The frame format is documented in docs/picoem-bridge.md and in src/frame.rs.
";

fn main() -> ExitCode {
    // picoem's own diagnostics (unmodelled MMIO, clock warnings) go to stderr;
    // RUST_LOG=debug or =trace turns on a great deal more.
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive(
                tracing_subscriber::filter::LevelFilter::WARN.into(),
            ),
        )
        .with_writer(std::io::stderr)
        .init();

    match run() {
        Ok(code) => code,
        Err(e) => {
            eprintln!("picoem-bridge: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<ExitCode, Box<dyn std::error::Error>> {
    let args = match parse_args()? {
        Some(args) => args,
        None => {
            print!("{USAGE}");
            return Ok(ExitCode::SUCCESS);
        }
    };

    let bootrom = std::fs::read(&args.bootrom).map_err(|e| {
        format!(
            "reading the bootrom {}: {e}\n  \
             It ships in picoem's own tree at roms/rp2350/bootrom-combined.bin -- \
             see REQUIREMENTS.md for the clone and the pin.",
            args.bootrom.display()
        )
    })?;
    let flash = std::fs::read(&args.flash)
        .map_err(|e| format!("reading the flash image {}: {e}", args.flash.display()))?;

    let mut log = Log::new(args.log.as_deref())?;
    log.line(&format!(
        "picoem-bridge: flash {} ({} bytes), bootrom {} ({} bytes), {} cycles/phase",
        args.flash.display(),
        flash.len(),
        args.bootrom.display(),
        bootrom.len(),
        args.cycles
    ));

    let mut chip = Chip::new(&bootrom, &flash, args.cycles, args.entry);
    log.line(&format!(
        "picoem-bridge: entry {} (see src/chip.rs for why the bootrom is not the default)",
        match args.entry {
            chip::Entry::Image => "= the image's own vector table",
            chip::Entry::Bootrom => "= the mask ROM's reset vector",
        }
    ));
    log.line(&format!("picoem-bridge: at entry {}", chip.describe()));
    let started = std::time::Instant::now();
    chip.settle(args.settle)?;
    log.line(&format!(
        "picoem-bridge: settled {} cycles in {:.2} s -> {}",
        args.settle,
        started.elapsed().as_secs_f64(),
        chip.describe()
    ));

    if args.trace_fault {
        chip = Chip::with_quantum(&bootrom, &flash, args.cycles, args.entry, Some(1));
    }

    if args.self_test {
        return self_test(&mut chip, &mut log);
    }

    if args.trace_fault {
        return trace_fault(&mut chip, &mut log);
    }

    serve(&mut chip, &args, &mut log)
}

/// Step one instruction at a time until the core latches a fault, and name the
/// instruction that did it.
///
/// This exists because the first failure a new firmware produces is "the PC is
/// not in the firmware", and from outside that looks identical whether the
/// image never started, the bootrom is still running, or the firmware executed
/// something picoem does not decode. The fault registers tell those apart, and
/// the stacked PC tells you *where*.
fn trace_fault(chip: &mut Chip, log: &mut Log) -> Result<ExitCode, Box<dyn std::error::Error>> {
    const HISTORY: usize = 24;
    let mut history: Vec<u32> = Vec::with_capacity(HISTORY);
    let mut pc = chip.pc();
    let mut lr = chip.lr();
    let mut sp = chip.sp();
    log.line(&format!("trace-fault: starting at pc={pc:#010x}"));
    for n in 0..200_000_000u64 {
        chip.step_one()?;
        if chip.faulted() {
            log.line(&format!(
                "trace-fault: FAULTED after {} steps\n  \
                 the instruction at pc={pc:#010x} (lr={lr:#010x} sp={sp:#010x})\n  \
                 cfsr={:#010x} hfsr={:#010x}\n  {}\n  \
                 the last {HISTORY} PCs, oldest first:\n    {}",
                n + 1,
                chip.cfsr(),
                chip.hfsr(),
                chip.describe(),
                history
                    .iter()
                    .map(|p| format!("{p:#010x}"))
                    .collect::<Vec<_>>()
                    .join(" ")
            ));
            return Ok(ExitCode::FAILURE);
        }
        history.push(pc);
        if history.len() > HISTORY {
            history.remove(0);
        }
        pc = chip.pc();
        lr = chip.lr();
        sp = chip.sp();
    }
    log.line(&format!("trace-fault: no fault after 200 M instructions ({})", chip.describe()));
    Ok(ExitCode::SUCCESS)
}

/// The half of the acceptance that does not involve MAME: the firmware binary
/// runs in picoem and answers a bus cycle driven from outside the crate.
fn self_test(chip: &mut Chip, log: &mut Log) -> Result<ExitCode, Box<dyn std::error::Error>> {
    if !chip.firmware_running() {
        log.line(&format!(
            "self-test: FAILED -- pc={:#010x} is not in the firmware; the bootrom is \
             still running, or the image did not boot",
            chip.pc()
        ));
        return Ok(ExitCode::FAILURE);
    }

    let wrote = 0xA5u8;
    let seen = chip.probe_stimulus(wrote);
    log.line(&format!(
        "self-test: with the data pins driven and the strobes idle (data {:02X}), \
         the chip's SIO GPIO_IN reads {:#010x} -> strobes {}, data {}",
        wrote,
        seen,
        if seen & 0x0F00 == 0x0F00 { "ok" } else { "WRONG" },
        if seen & 0xFF == wrote as u32 { "ok" } else { "WRONG" }
    ));

    let tx = chip.bus_write(wrote, 0)?;
    log.line(&format!(
        "self-test: write {:02X} -> chip drove {:02X}  hb={} flags={:02X} pc={:#010x}",
        wrote, tx.data, tx.hb, tx.flags, tx.pc
    ));

    let rx = chip.bus_read(0)?;
    log.line(&format!(
        "self-test: read      -> chip drove {:02X}  hb={} flags={:02X} pc={:#010x}",
        rx.data, rx.hb, rx.flags, rx.pc
    ));

    let echo_ok = tx.data == wrote && rx.data == wrote;
    let seen_ok = tx.hb == 1 && rx.hb == 1;
    log.line(&format!(
        "self-test: echo {}  heartbeat {}  => {}",
        if echo_ok { "ok" } else { "WRONG" },
        if seen_ok { "ok" } else { "WRONG" },
        if echo_ok && seen_ok { "PASS" } else { "FAILED" }
    ));
    Ok(if echo_ok && seen_ok { ExitCode::SUCCESS } else { ExitCode::FAILURE })
}

/// The MAME half: serve frames off the FIFOs until the peer stops asking.
fn serve(
    chip: &mut Chip,
    args: &Args,
    log: &mut Log,
) -> Result<ExitCode, Box<dyn std::error::Error>> {
    fifo::create_if_missing(&args.in_path)?;
    fifo::create_if_missing(&args.out_path)?;
    // O_RDWR on both ends: the open never blocks, and the order the two
    // processes start in does not matter.
    let mut input = fifo::open(&args.in_path)?;
    let mut output = fifo::open(&args.out_path)?;
    log.line(&format!(
        "picoem-bridge: serving on {} -> {}",
        args.in_path.display(),
        args.out_path.display()
    ));

    let mut served = 0u64;
    loop {
        if let Some(limit) = args.frames {
            if served >= limit {
                log.line(&format!("picoem-bridge: {served} frames answered, exiting"));
                return Ok(ExitCode::SUCCESS);
            }
        }

        let mut buf = [0u8; frame::LEN];
        match input.read_exact(&mut buf) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => {
                log.line(&format!("picoem-bridge: peer closed after {served} frames"));
                return Ok(ExitCode::SUCCESS);
            }
            Err(e) => return Err(format!("reading {}: {e}", args.in_path.display()).into()),
        }

        let reply = match Request::decode(&buf) {
            Ok(req) => handle(chip, &req, log),
            Err(why) => {
                log.line(&format!("picoem-bridge: bad request ({why}) -- resync"));
                Reply::status_only(ST_BAD_REQUEST, 0)
            }
        };
        output.write_all(&reply.encode())?;
        output.flush()?;
        served += 1;
    }
}

/// One frame, one bus transaction. The log line is the MAME-side evidence: the
/// byte the Z80 drove in, the byte the firmware drove back out, and the
/// heartbeat that says the firmware handled it rather than the line being idle.
fn handle(chip: &mut Chip, req: &Request, log: &mut Log) -> Reply {
    if !chip.firmware_running() {
        log.line(&format!(
            "picoem-bridge: seq {} refused -- pc={:#010x} is not firmware",
            req.seq,
            chip.pc()
        ));
        return Reply::status_only(ST_NO_FIRMWARE, req.seq);
    }

    if req.op == frame::OP_HELLO {
        return Reply {
            status: ST_OK,
            data: 0,
            hb: 0,
            flags: 0,
            addr: req.addr,
            seq: req.seq,
            pc: chip.pc(),
            cycles: chip.cycles() as u32,
        };
    }

    // Only I/O cycles are modelled: the smoke firmware watches /IORQ, /RD and
    // /WR. A memory cycle would need the address bus, which v1 of this frame
    // carries but the bridge does not yet drive -- so it is refused rather than
    // answered wrongly. (The ROM window is memory-mapped and is what #179's
    // growth will need.)
    if req.flags & frame::FLAG_SPACE_MEM != 0 {
        log.line(&format!(
            "picoem-bridge: seq {} refused -- memory cycles are not modelled yet",
            req.seq
        ));
        return Reply::status_only(ST_BAD_REQUEST, req.seq);
    }

    let tx = if req.op == frame::OP_BUS_WRITE {
        chip.bus_write(req.data, req.cycles as u64)
    } else {
        chip.bus_read(req.cycles as u64)
    };

    let tx = match tx {
        Ok(tx) => tx,
        Err(e) => {
            log.line(&format!("picoem-bridge: seq {} emulator error: {e}", req.seq));
            return Reply::status_only(ST_NO_FIRMWARE, req.seq);
        }
    };

    log.line(&format!(
        "picoem-bridge: seq {:<4} {:<5} port {:02X} {:>9} -> chip drove {:02X}  hb={} {}{}{}",
        req.seq,
        if req.op == frame::OP_BUS_WRITE { "WRITE" } else { "READ" },
        req.port,
        if req.op == frame::OP_BUS_WRITE {
            format!("wrote {:02X}", req.data)
        } else {
            "read".to_string()
        },
        tx.data,
        tx.hb,
        if tx.flags & frame::REPLY_DATA_OE != 0 { "OE " } else { "-- " },
        if tx.flags & frame::REPLY_DRIVEN != 0 { "DRV " } else { "--- " },
        if tx.flags & frame::REPLY_HEARTBEAT != 0 { "HB" } else { "--" },
    ));

    Reply {
        status: ST_OK,
        data: tx.data,
        hb: tx.hb,
        flags: tx.flags,
        addr: req.addr,
        seq: req.seq,
        pc: tx.pc,
        cycles: tx.cycles as u32,
    }
}

/// stdout plus, optionally, a file. Both are flushed line by line: this process
/// blocks on a FIFO, and a log that only appears when the process exits is no
/// log at all.
struct Log {
    file: Option<File>,
}

impl Log {
    fn new(path: Option<&Path>) -> io::Result<Log> {
        Ok(Log { file: path.map(File::create).transpose()? })
    }

    fn line(&mut self, s: &str) {
        println!("{s}");
        if let Some(f) = &mut self.file {
            let _ = writeln!(f, "{s}");
            let _ = f.flush();
        }
    }
}

fn parse_args() -> Result<Option<Args>, Box<dyn std::error::Error>> {
    let mut flash: Option<PathBuf> = None;
    let mut bootrom: Option<PathBuf> = None;
    let mut in_path = std::env::var_os("O1_PICOEM_IN")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_IN));
    let mut out_path = std::env::var_os("O1_PICOEM_OUT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_OUT));
    let mut cycles = DEFAULT_CYCLES;
    let mut settle = DEFAULT_SETTLE;
    let mut frames = None;
    let mut log = None;
    let mut self_test = false;
    let mut entry = chip::Entry::Image;
    let mut trace_fault = false;

    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--flash" => flash = Some(PathBuf::from(next_value(&mut it, "--flash")?)),
            "--bootrom" => bootrom = Some(PathBuf::from(next_value(&mut it, "--bootrom")?)),
            "--in" => in_path = PathBuf::from(next_value(&mut it, "--in")?),
            "--out" => out_path = PathBuf::from(next_value(&mut it, "--out")?),
            "--cycles" => cycles = next_value(&mut it, "--cycles")?.parse()?,
            "--settle" => settle = next_value(&mut it, "--settle")?.parse()?,
            "--frames" => frames = Some(next_value(&mut it, "--frames")?.parse()?),
            "--log" => log = Some(PathBuf::from(next_value(&mut it, "--log")?)),
            "--self-test" => self_test = true,
            "--via-bootrom" => entry = chip::Entry::Bootrom,
            "--trace-fault" => trace_fault = true,
            "-h" | "--help" => return Ok(None),
            other => return Err(format!("unknown argument {other}\n\n{USAGE}").into()),
        }
    }

    let flash = flash.ok_or("--flash is required (try --help)")?;
    let bootrom = match bootrom {
        Some(p) => p,
        None => std::env::var_os("PICOEM_BOOTROM").map(PathBuf::from).ok_or(
            "--bootrom is required (or set PICOEM_BOOTROM): picoem's \
             roms/rp2350/bootrom-combined.bin",
        )?,
    };

    Ok(Some(Args {
        flash,
        bootrom,
        in_path,
        out_path,
        cycles,
        settle,
        frames,
        log,
        self_test,
        entry,
        trace_fault,
    }))
}

fn next_value(
    it: &mut impl Iterator<Item = String>,
    name: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    it.next().ok_or_else(|| format!("{name} needs a value").into())
}
