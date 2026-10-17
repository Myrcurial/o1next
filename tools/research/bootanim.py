#!/usr/bin/env python3
"""The boot animation's container: read it, validate it, take a frame out of it.

`firmware/rom-service/boot-animation.bin` is the boot screen as a *sequence*
(#247's W5): a 32-byte `O1SPLASH` header and then the frames back to back, each
already sealed.  The container is `tools/bootsplash/README.md`'s; this is the reader
that makes it checkable and usable.

WHY IT EXISTS
  Two jobs, and both of them used to be somebody else's file.

  **The ROM-side acceptance is "the asset is valid".**  The animation is not the
  ROM's to draw -- the RP2354B DMA-blits it in -- so nothing on the ROM side has any
  business looking at the animation's *content*.  What it must be able to say is
  that the asset is well-formed: the container's own sum, its declared geometry and
  flags, the frame count the body length implies, and **each frame's own trailer**,
  because a frame that fails its own test is a frame the machine cannot draw.  That
  is `--check`, and it is the whole of the ROM's interest.

  **The frame the ROM *does* ask for comes out of it.**  `PRESENT(1)` and
  `PRESENT(2)` serve "the frame" -- two 4096-byte halves, characters then attributes
  -- and the separate `firmware/rom-service/frame.bin` that used to be that frame
  was **retired on 2026-10-16**.  The frame the hardware would serve is the one the
  animation *rests* on, which is the last frame of a `once` animation (frame 89 of
  90 here), so `--resting` writes exactly the 8192-byte asset the retired file was
  -- and `romservice-check.sh`, `bootscreen-check.sh` and `stage.sh` mount that
  rather than a committed copy that can drift from the animation it came from.

CONTAINER (`tools/bootsplash/README.md`, `docs/rom-pico-protocol.md` 5.1)

    0   8  O1SPLASH          the magic
    8   1  version           1
    9   1  flags             bit 0 LOOP, bit 1 PINGPONG; the rest must be zero
    10  2  width             u16 LE, 128
    12  2  height            u16 LE, 32
    14  2  fps               u16 LE, non-zero
    16  4  frames            u32 LE, non-zero
    20  4  body              u32 LE = frames x 8192
    24  2  header sum        u16 LE over bytes 0-23
    26  6  reserved          zero

  Each frame is 8192 bytes: a 4096-byte character half then a 4096-byte attribute
  half, and **each half carries its own trailer** at its own 0FF8h -- six bytes of
  `O1NEXT` and a 16-bit sum of the 4088 bytes before them -- so either half
  validates without the other (docs/rom-pico-protocol.md 5).

Usage:
    tools/research/bootanim.py --check [FILE]        # validate; exit 1 if it is not
    tools/research/bootanim.py --info [FILE]         # the header, and the mode
    tools/research/bootanim.py --resting -o OUT.bin  # the frame it rests on
    tools/research/bootanim.py --frame N -o OUT.bin  # frame N, 0-based

FILE defaults to firmware/rom-service/boot-animation.bin.  Standard library only.
"""
import argparse
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
DEFAULT = REPO / "firmware" / "rom-service" / "boot-animation.bin"

HEADER = 32
MAGIC = b"O1SPLASH"
VERSION = 1
HALF = 4096
FRAME = HALF * 2
TRAILER_AT = 0x0FF8          # the magic, six bytes, and the sum at 0x0FFE
TRAILER = b"O1NEXT"
FLAG_LOOP = 0x01
FLAG_PINGPONG = 0x02
KNOWN_FLAGS = FLAG_LOOP | FLAG_PINGPONG
WIDTH, HEIGHT = 128, 32


def mode_name(flags):
    if flags & FLAG_PINGPONG:
        return "ping-pong repeat" if flags & FLAG_LOOP else "ping-pong once"
    return "loop" if flags & FLAG_LOOP else "once"


def half_ok(half):
    """A half validates on its own: its magic, and the sum of the 4088 before it."""
    if len(half) != HALF:
        return "is %d bytes, not %d" % (len(half), HALF)
    if half[TRAILER_AT:TRAILER_AT + 6] != TRAILER:
        return "its trailer at 0FF8h is not %s" % TRAILER.decode()
    want = struct.unpack_from("<H", half, 0x0FFE)[0]
    got = sum(half[:0x0FF8]) & 0xFFFF
    if got != want:
        return "its sum is %04X, the bytes sum to %04X" % (want, got)
    return None


def parse(path):
    """(header dict, complaints).  Complaints are the container's own."""
    data = path.read_bytes()
    bad = []
    if len(data) < HEADER:
        return None, ["%s is %d bytes: shorter than the %d-byte header"
                      % (path, len(data), HEADER)]
    if data[0:8] != MAGIC:
        bad.append("the magic is %r, not %r" % (data[0:8], MAGIC))
    version, flags = data[8], data[9]
    width, height, fps = struct.unpack_from("<HHH", data, 10)
    frames, body = struct.unpack_from("<II", data, 16)
    hsum = struct.unpack_from("<H", data, 24)[0]
    reserved = data[26:32]
    if version != VERSION:
        bad.append("version is %d, not %d" % (version, VERSION))
    if flags & ~KNOWN_FLAGS:
        bad.append("flags is %02Xh: bits outside LOOP|PINGPONG are set" % flags)
    if (width, height) != (WIDTH, HEIGHT):
        bad.append("geometry is %dx%d, not %dx%d" % (width, height, WIDTH, HEIGHT))
    if fps == 0:
        bad.append("fps is 0")
    if frames == 0:
        bad.append("frames is 0")
    if body != frames * FRAME:
        bad.append("body is %d, but %d frames of %d is %d"
                   % (body, frames, FRAME, frames * FRAME))
    if len(data) != HEADER + body:
        bad.append("the file is %d bytes, but %d header + %d body is %d"
                   % (len(data), HEADER, body, HEADER + body))
    if reserved != b"\x00" * 6:
        bad.append("the six reserved bytes are not zero: %r" % reserved)
    got = sum(data[0:24]) & 0xFFFF
    if got != hsum:
        bad.append("the header sum is %04Xh, the bytes sum to %04Xh" % (hsum, got))
    hdr = {"version": version, "flags": flags, "width": width, "height": height,
           "fps": fps, "frames": frames, "body": body, "sum": hsum}
    return hdr, bad


def frames_ok(data, hdr, limit=5):
    """Each frame's two halves, validated by their own trailers."""
    bad = []
    for n in range(hdr["frames"]):
        at = HEADER + n * FRAME
        for which, name in ((0, "characters"), (1, "attributes")):
            why = half_ok(data[at + which * HALF:at + (which + 1) * HALF])
            if why:
                bad.append("frame %d's %s half: %s" % (n, name, why))
                if len(bad) >= limit:
                    bad.append("... stopping after %d" % limit)
                    return bad
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Read the boot animation's container (#247's W5).")
    ap.add_argument("file", nargs="?", default=str(DEFAULT),
                    help="the animation (default: firmware/rom-service/boot-animation.bin)")
    ap.add_argument("--check", action="store_true",
                    help="validate the container and every frame; exit 1 if it is not")
    ap.add_argument("--info", action="store_true", help="print the header and the mode")
    ap.add_argument("--frame", type=int, metavar="N", help="write frame N (0-based)")
    ap.add_argument("--resting", action="store_true",
                    help="write the frame the animation rests on -- the last one, "
                         "which is what a `once` animation stops on")
    ap.add_argument("-o", "--out", metavar="OUT.bin", help="where to write a frame")
    args = ap.parse_args(argv)

    path = Path(args.file)
    if not path.exists():
        print("bootanim.py: no such file: %s" % path, file=sys.stderr)
        return 1
    hdr, bad = parse(path)
    if hdr is None:
        print("\n".join("bootanim.py: " + b for b in bad), file=sys.stderr)
        return 1

    if args.check:
        print("  ok   %s: %s, %d frames, %d fps, %dx%d"
              % (path, mode_name(hdr["flags"]), hdr["frames"], hdr["fps"],
                 hdr["width"], hdr["height"]))
        print("  ok   the header's own sum (%04Xh over bytes 0-23)" % hdr["sum"])
        if bad:
            for b in bad:
                print("  BAD  the container: " + b, file=sys.stderr)
        data = path.read_bytes()
        fbad = frames_ok(data, hdr) if not bad else []
        if fbad:
            for b in fbad:
                print("  BAD  " + b, file=sys.stderr)
        if bad or fbad:
            print("bootanim.py: the animation is not the asset it says it is",
                  file=sys.stderr)
            return 1
        print("  ok   every frame's two halves carry their own %s and their own sum"
              % TRAILER.decode())
        return 0

    if args.info:
        print("%s" % path)
        print("  magic      %s, version %d" % (MAGIC.decode(), hdr["version"]))
        print("  flags      %02Xh -- %s (LOOP %s, PINGPONG %s)"
              % (hdr["flags"], mode_name(hdr["flags"]),
                 "set" if hdr["flags"] & FLAG_LOOP else "clear",
                 "set" if hdr["flags"] & FLAG_PINGPONG else "clear"))
        print("  geometry   %d x %d" % (hdr["width"], hdr["height"]))
        print("  pacing     %d fps" % hdr["fps"])
        print("  frames     %d x %d = %d bytes of body" % (hdr["frames"], FRAME, hdr["body"]))
        print("  sum        %04Xh over bytes 0-23" % hdr["sum"])
        print("  resting    frame %d (0-based)" % (hdr["frames"] - 1))
        for b in bad:
            print("  BAD        " + b, file=sys.stderr)
        return 1 if bad else 0

    if args.frame is None and not args.resting:
        ap.error("give one of --check, --info, --frame N or --resting")

    n = hdr["frames"] - 1 if args.resting else args.frame
    if not 0 <= n < hdr["frames"]:
        print("bootanim.py: frame %d is not in 0..%d" % (n, hdr["frames"] - 1),
              file=sys.stderr)
        return 1
    if not args.out:
        ap.error("--frame/--resting need -o OUT.bin")
    if bad:
        print("bootanim.py: the container is not valid, so its frames are not either",
              file=sys.stderr)
        for b in bad:
            print("  " + b, file=sys.stderr)
        return 1
    data = path.read_bytes()
    at = HEADER + n * FRAME
    out = data[at:at + FRAME]
    fbad = []
    for which, name in ((0, "characters"), (1, "attributes")):
        why = half_ok(out[which * HALF:(which + 1) * HALF])
        if why:
            fbad.append("frame %d's %s half: %s" % (n, name, why))
    if fbad:
        for b in fbad:
            print("bootanim.py: " + b, file=sys.stderr)
        return 1
    Path(args.out).write_bytes(out)
    print("bootanim.py: frame %d of %d -> %s (%d bytes, both halves sealed)"
          % (n, hdr["frames"], args.out, len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
