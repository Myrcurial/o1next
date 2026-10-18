//! The frame format the MAME side and the bridge speak (#286, part of #192).
//!
//! **This file is one of the two copies of the contract.** The other is
//! `tools/emulator-setup/mame-osborne1nx/o1next-picoem.lua`, which builds and
//! parses the same 24 bytes in Lua. `docs/picoem-bridge.md` is the prose
//! version; if the three disagree, this one and the tests below are right.
//!
//! The channel is a pair of FIFOs (see `fifo.rs`), so the transport is a byte
//! stream with no message boundaries. The frame is therefore **fixed length**
//! with a **magic** and a **checksum**: a reader that has drifted out of step
//! cannot silently resynchronise onto a wrong boundary, it sees a bad magic or
//! a bad sum.
//!
//! Request -- MAME to bridge, 24 bytes:
//!
//! ```text
//!   off  size  field
//!    0    4    magic  "O1B1"
//!    4    1    op     0 = HELLO, 1 = BUS_WRITE, 2 = BUS_READ
//!    5    1    flags  bit0: 0 = the cycle is an I/O cycle, 1 = a memory cycle
//!    6    1    port   the Z80's I/O port, 0 for a memory cycle
//!    7    1    data   the byte the Z80 drove (op 1); 0 for a read
//!    8    2    addr   u16 little-endian; the address of a memory cycle
//!   10    2    seq    u16 little-endian; echoed back, so a reply can be matched
//!   12    4    cycles u32 little-endian; cycles to run for this transaction,
//!                    0 = the bridge's default (--cycles)
//!   16    4    (reserved, 0)
//!   20    2    checksum u16 little-endian, sum of bytes 0..19
//!   22    2    (reserved, 0)
//! ```
//!
//! Reply -- bridge to MAME, 24 bytes:
//!
//! ```text
//!   off  size  field
//!    0    4    magic  "O1B1"
//!    4    1    status 0 = OK, 1 = no firmware running, 2 = bad request
//!    5    1    data   the byte the chip drove on GP0-GP7 at the end of the
//!                     transaction -- the answer, on a read
//!    6    1    hb     the number of GP37 edges seen during the transaction;
//!                     1 means the firmware handled the cycle
//!    7    1    flags  bit0 the GP37 level after the transaction
//!                     bit1 GP24 (DATA_OE) asserted after the transaction
//!                     bit2 GP0-GP7 were driven by the chip after the
//!                          transaction
//!    8    2    addr   echo of the request
//!   10    2    seq    echo of the request
//!   12    4    pc     u32 little-endian; the firmware's PC after the transaction
//!   16    4    cycles u32 little-endian; the emulated chip's total cycle count
//!   20    2    checksum
//!   22    2    (reserved, 0)
//! ```
//!
//! Why `pc` and `cycles` are in every reply rather than in a HELLO exchange
//! only: "the firmware is running" is the first thing that goes wrong and the
//! hardest thing to see from the MAME side, and two fields cost nothing.

pub const MAGIC: [u8; 4] = *b"O1B1";
/// Fixed frame length, both directions.
pub const LEN: usize = 24;

pub const OP_HELLO: u8 = 0x00;
pub const OP_BUS_WRITE: u8 = 0x01;
pub const OP_BUS_READ: u8 = 0x02;

pub const ST_OK: u8 = 0x00;
pub const ST_NO_FIRMWARE: u8 = 0x01;
pub const ST_BAD_REQUEST: u8 = 0x02;

/// Request flag: the cycle is a memory cycle rather than an I/O cycle.
pub const FLAG_SPACE_MEM: u8 = 0x01;

/// Reply flag: the GP37 heartbeat level after the transaction.
pub const REPLY_HEARTBEAT: u8 = 0x01;
/// Reply flag: GP24 (DATA_OE) is asserted after the transaction.
pub const REPLY_DATA_OE: u8 = 0x02;
/// Reply flag: the chip is driving GP0-GP7 after the transaction.
pub const REPLY_DRIVEN: u8 = 0x04;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Request {
    pub op: u8,
    pub flags: u8,
    pub port: u8,
    pub data: u8,
    pub addr: u16,
    pub seq: u16,
    pub cycles: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Reply {
    pub status: u8,
    pub data: u8,
    pub hb: u8,
    pub flags: u8,
    pub addr: u16,
    pub seq: u16,
    pub pc: u32,
    pub cycles: u32,
}

impl Reply {
    /// A reply that says only "this is what went wrong".
    pub fn status_only(status: u8, seq: u16) -> Reply {
        Reply { status, data: 0, hb: 0, flags: 0, addr: 0, seq, pc: 0, cycles: 0 }
    }
}

/// Sum of the bytes, mod 65536. Not a cryptographic check: it catches a torn or
/// misaligned frame, which is the failure the channel can actually produce.
pub fn checksum(bytes: &[u8]) -> u16 {
    bytes.iter().fold(0u16, |acc, &b| acc.wrapping_add(b as u16))
}

impl Request {
    /// The MAME side builds requests; this binary only reads them. It lives here
    /// -- and is tested -- because the frame is a contract with two copies, and
    /// a contract you can only decode is not one.
    #[allow(dead_code)]
    pub fn encode(&self) -> [u8; LEN] {
        let mut b = [0u8; LEN];
        b[0..4].copy_from_slice(&MAGIC);
        b[4] = self.op;
        b[5] = self.flags;
        b[6] = self.port;
        b[7] = self.data;
        b[8..10].copy_from_slice(&self.addr.to_le_bytes());
        b[10..12].copy_from_slice(&self.seq.to_le_bytes());
        b[12..16].copy_from_slice(&self.cycles.to_le_bytes());
        let sum = checksum(&b[0..20]);
        b[20..22].copy_from_slice(&sum.to_le_bytes());
        b
    }

    pub fn decode(buf: &[u8; LEN]) -> Result<Request, &'static str> {
        if buf[0..4] != MAGIC {
            return Err("bad magic");
        }
        let sum = u16::from_le_bytes([buf[20], buf[21]]);
        if sum != checksum(&buf[0..20]) {
            return Err("bad checksum");
        }
        let req = Request {
            op: buf[4],
            flags: buf[5],
            port: buf[6],
            data: buf[7],
            addr: u16::from_le_bytes([buf[8], buf[9]]),
            seq: u16::from_le_bytes([buf[10], buf[11]]),
            cycles: u32::from_le_bytes([buf[12], buf[13], buf[14], buf[15]]),
        };
        match req.op {
            OP_HELLO | OP_BUS_WRITE | OP_BUS_READ => Ok(req),
            _ => Err("unknown op"),
        }
    }
}

impl Reply {
    pub fn encode(&self) -> [u8; LEN] {
        let mut b = [0u8; LEN];
        b[0..4].copy_from_slice(&MAGIC);
        b[4] = self.status;
        b[5] = self.data;
        b[6] = self.hb;
        b[7] = self.flags;
        b[8..10].copy_from_slice(&self.addr.to_le_bytes());
        b[10..12].copy_from_slice(&self.seq.to_le_bytes());
        b[12..16].copy_from_slice(&self.pc.to_le_bytes());
        b[16..20].copy_from_slice(&self.cycles.to_le_bytes());
        let sum = checksum(&b[0..20]);
        b[20..22].copy_from_slice(&sum.to_le_bytes());
        b
    }

    /// The MAME side parses replies; this binary only writes them. Same reason
    /// as `Request::encode` above.
    #[allow(dead_code)]
    pub fn decode(buf: &[u8; LEN]) -> Result<Reply, &'static str> {
        if buf[0..4] != MAGIC {
            return Err("bad magic");
        }
        let sum = u16::from_le_bytes([buf[20], buf[21]]);
        if sum != checksum(&buf[0..20]) {
            return Err("bad checksum");
        }
        Ok(Reply {
            status: buf[4],
            data: buf[5],
            hb: buf[6],
            flags: buf[7],
            addr: u16::from_le_bytes([buf[8], buf[9]]),
            seq: u16::from_le_bytes([buf[10], buf[11]]),
            pc: u32::from_le_bytes([buf[12], buf[13], buf[14], buf[15]]),
            cycles: u32::from_le_bytes([buf[16], buf[17], buf[18], buf[19]]),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn req(op: u8, port: u8, data: u8, seq: u16) -> Request {
        Request { op, flags: 0, port, data, addr: 0, seq, cycles: 20000 }
    }

    #[test]
    fn request_round_trips() {
        let r = req(OP_BUS_WRITE, 0x30, 0xA5, 7);
        assert_eq!(Request::decode(&r.encode()), Ok(r));
    }

    #[test]
    fn reply_round_trips() {
        let reply = Reply {
            status: ST_OK,
            data: 0xA5,
            hb: 1,
            flags: REPLY_HEARTBEAT | REPLY_DRIVEN,
            addr: 0,
            seq: 7,
            pc: 0x1000_0234,
            cycles: 3_000_000,
        };
        assert_eq!(Reply::decode(&reply.encode()), Ok(reply));
    }

    /// The frame length is the contract, so it gets a test of its own: both
    /// sides read exactly this many bytes off a stream with no boundaries.
    #[test]
    fn frame_is_24_bytes() {
        assert_eq!(LEN, 24);
        assert_eq!(req(OP_HELLO, 0, 0, 0).encode().len(), LEN);
    }

    #[test]
    fn a_torn_frame_is_rejected() {
        let mut bytes = req(OP_BUS_WRITE, 0x31, 0x5A, 1).encode();
        bytes[7] ^= 0x01; // one flipped bit in the payload
        assert_eq!(Request::decode(&bytes), Err("bad checksum"));
    }

    #[test]
    fn a_misaligned_frame_is_rejected() {
        let mut bytes = req(OP_BUS_READ, 0x32, 0, 2).encode();
        bytes.rotate_left(3); // what one lost byte does to the stream
        assert_eq!(Request::decode(&bytes), Err("bad magic"));
    }

    #[test]
    fn an_unknown_op_is_rejected() {
        assert_eq!(Request::decode(&req(0x7F, 0, 0, 0).encode()), Err("unknown op"));
    }
}
