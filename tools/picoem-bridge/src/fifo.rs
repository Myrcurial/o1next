//! The channel: a pair of FIFOs (#286, part of #192).
//!
//! # Why a FIFO and not a socket
//!
//! #192's option 3 says "a socket/pipe protocol between a MAME device and a
//! picoem process". A socket is not available on the MAME side, and that is a
//! measurement, not a preference:
//!
//!   - MAME's Lua has no socket library. `src/frontend/mame/luaengine.cpp`
//!     preloads exactly four modules -- `zlib`, `lfs`, `linenoise`,
//!     `lsqlite3` -- and `3rdparty/` has no luasocket at all. Measured on
//!     MAME 0.289, the tree this project patches.
//!   - The alternatives are both changes to MAME: vendor luasocket into it
//!     (a change to its Lua surface, and the one thing most likely to get the
//!     `osborne1nx` patch refused upstream), or write a C++ device that opens
//!     a real socket (a second patch to the same tree, and a rebuild).
//!
//! A FIFO costs neither. Lua's `io` can open a path, and a FIFO opened
//! `O_RDWR` by both ends is a blocking byte stream with no open-order
//! deadlock -- the same semantics a socket would have given us, without the
//! socket. And blocking is not a compromise here: the ACB-4000 personality
//! needs the Z80's I/O cycle *answered before it continues*, which is exactly
//! what a blocking request/response gives, and a frame-quantised socket would
//! not have.
//!
//! # The one hazard, stated
//!
//! A blocking read on a FIFO never returns if the peer dies. The bridge holds
//! both ends open for the life of the run, so a MAME that exits frees the
//! bridge rather than hanging it, and a bridge that exits leaves MAME blocked
//! in `io.read` until it is killed. `picoem-check.sh` kills both on every exit
//! path, and `--frames N` gives the bridge a way to finish on its own.

use std::fs::{File, OpenOptions};
use std::io;
use std::os::unix::fs::FileTypeExt;
use std::path::Path;

/// Create the FIFO if it is not there. A plain file at that path is an error:
/// it means somebody else's protocol is living there.
pub fn create_if_missing(path: &Path) -> io::Result<()> {
    if let Some(dir) = path.parent() {
        if !dir.as_os_str().is_empty() {
            std::fs::create_dir_all(dir)?;
        }
    }

    if let Ok(meta) = std::fs::symlink_metadata(path) {
        if !meta.file_type().is_fifo() {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                format!("{} exists and is not a FIFO", path.display()),
            ));
        }
        return Ok(());
    }

    let c_path = std::ffi::CString::new(path.as_os_str().as_encoded_bytes()).map_err(|_| {
        io::Error::new(io::ErrorKind::InvalidInput, "path contains a NUL byte")
    })?;
    // SAFETY: a valid NUL-terminated path; mkfifo does not retain the pointer.
    let rc = unsafe { libc::mkfifo(c_path.as_ptr(), 0o600) };
    if rc != 0 {
        let err = io::Error::last_os_error();
        // A race with the other end creating it is not an error.
        if err.raw_os_error() != Some(libc::EEXIST) {
            return Err(err);
        }
    }
    Ok(())
}

/// Open a FIFO for reading *and* writing, which is what makes the open
/// non-blocking and order-independent: `open(2)` on a FIFO with `O_RDWR`
/// succeeds immediately whether or not the peer is there yet.
pub fn open(path: &Path) -> io::Result<File> {
    OpenOptions::new().read(true).write(true).open(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::{Reply, Request, LEN, OP_BUS_WRITE, ST_OK};
    use std::io::{Read, Write};
    use std::path::PathBuf;

    /// One scratch directory **per test**.
    ///
    /// The first version named it by pid alone, and cargo runs tests in
    /// parallel threads of one process -- so three tests shared one directory
    /// and raced on creating and removing it. On macOS the loser of that race
    /// gets `EINVAL` out of `mkfifo`, which reads like a bug in `mkfifo` and is
    /// a bug in the test.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir()
            .join(format!("picoem-bridge-test-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("mkdir");
        dir
    }

    #[test]
    fn a_fifo_round_trips_a_frame() {
        let dir = scratch("round-trip");
        let path = dir.join("fifo");
        create_if_missing(&path).expect("mkfifo");

        let mut a = open(&path).expect("open A");
        let mut b = open(&path).expect("open B");
        a.write_all(b"O1B1").expect("write");
        let mut buf = [0u8; 4];
        b.read_exact(&mut buf).expect("read");
        assert_eq!(&buf, b"O1B1");

        let _ = std::fs::remove_dir_all(&dir);
    }

    /// The whole wire, over real FIFOs: build a request the way the MAME side
    /// does, read it the way the bridge does, and answer it the way the MAME
    /// side parses it. This is the closest thing to the other copy of the
    /// contract that a test can be -- `o1next-picoem.lua` builds the same bytes
    /// in Lua, and this is what pins the two to the same layout.
    #[test]
    fn a_request_and_reply_round_trip_through_a_fifo() {
        let dir = scratch("wire");
        let in_path = dir.join("in");
        let out_path = dir.join("out");
        create_if_missing(&in_path).expect("mkfifo in");
        create_if_missing(&out_path).expect("mkfifo out");

        // Two FIFOs, two ends each -- and every open is O_RDWR, so none of them
        // blocks. A first version of this test wrote the request to `in` and
        // read it from `out`, which is not a wire and does not return.
        let mut in_write = open(&in_path).expect("open in (write)");
        let mut in_read = open(&in_path).expect("open in (read)");
        let mut out_write = open(&out_path).expect("open out (write)");
        let mut out_read = open(&out_path).expect("open out (read)");

        let req = Request {
            op: OP_BUS_WRITE,
            flags: 0,
            port: 0x30,
            data: 0xA5,
            addr: 0,
            seq: 1,
            cycles: 0,
        };
        in_write.write_all(&req.encode()).expect("write request");

        let mut buf = [0u8; LEN];
        in_read.read_exact(&mut buf).expect("read request");
        assert_eq!(Request::decode(&buf), Ok(req), "the bridge's view of the request");

        let reply = Reply {
            status: ST_OK,
            data: 0xA5,
            hb: 1,
            flags: 0x07,
            addr: 0,
            seq: 1,
            pc: 0x1000_029e,
            cycles: 40_000_000,
        };
        out_write.write_all(&reply.encode()).expect("write reply");

        let mut buf = [0u8; LEN];
        out_read.read_exact(&mut buf).expect("read reply");
        assert_eq!(Reply::decode(&buf), Ok(reply), "the MAME side's view of the reply");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_regular_file_at_the_path_is_refused() {
        let dir = scratch("not-a-fifo");
        let path = dir.join("not-a-fifo");
        std::fs::write(&path, b"").expect("write");
        assert!(create_if_missing(&path).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
