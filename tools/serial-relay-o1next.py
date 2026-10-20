#!/usr/bin/env python3
"""pty <-> TCP: the host end of the bench rig's second door (#342, part of #334).

    tools/serial-relay-o1next.py --pty /dev/ttys012 --host 192.168.2.50
    tools/serial-relay-o1next.py --pty /dev/ttys012 --serial /dev/cu.usbmodem2144201
    tools/serial-relay-o1next.py --make-pty --host 192.168.2.50
    tools/serial-relay-o1next.py --pty /dev/ttys012 --host 192.168.2.50 --verbose

TWO FAR ENDS, AND WHY THE USB ONE EXISTS

  --host    the rig's TCP relay door.  A pure pipe, and the door the rig's issue names.
  --serial  the rig's own USB port.  **No network in the path at all**, which matters on
            this host: macOS's Local Network privacy gates *outbound* LAN connections
            per binary, and a Python process gets `Errno 65 No route to host` reaching a
            device on the local network while `ping`/`nc`/`curl` reach it fine.  The USB
            door cannot be refused that way, so it is the door that always works.  Put
            the rig in `relay` first -- its USB console is the console until you do.

WHY A RELAY EXISTS AT ALL, when the bridge already listens on TCP

Because MAME's `-rs232 pty` gives a **host-local pseudo terminal**, not a socket.  The
pty device calls `openpty()` and logs the slave's name:

    Starting Pseudo Terminal ':rs232:pty'
    ...
    Pseudo Terminal '/dev/ttys012'

...and that path is the only way in.  A pty is host-local by construction, so something
has to sit between it and the network.  That is this: 8 KB of select() loop, and it is
stdlib only because everything in `tools/` is (tools/README.md).

    MAME's ACIA  <->  /dev/ttys012  <->  this  <->  tcp <bridge>:2323  <->  bridge UART1
                                                                              |
                                                                        the real modem

TWO MODES, AND WHICH ONE YOU WANT

  --pty PATH    attach to a pty somebody else made.  **This is the MAME one**: start
                MAME with `-rs232 pty`, read the slave's path out of its log, pass it
                here.  MAME holds the master; this holds the slave.
  --make-pty    make the pty yourself and print the slave's path, then relay it.  For
                anything that can be told to open a serial path -- a second terminal,
                a test script, a program that only speaks to a tty.

The bridge's relay door is a **pure pipe** and is never inspected, which is what makes
this safe for binary protocols: XMODEM, ZMODEM and the modem's own `+++` hangup all pass
through untouched.  (The bridge's *USB* door has a Hayes escape; this door does not, and
that is deliberate.)

The counters on exit are the useful part of a session that did not work: `pty -> tcp`
zero means MAME never wrote, and `tcp -> pty` zero means the modem never answered.  The
difference between those two is the whole diagnosis.
"""
import argparse
import os
import select
import signal
import socket
import sys
import termios
import time
import tty

CHUNK = 8192


def note(fmt, *args):
    sys.stderr.write(fmt % args if args else fmt)
    sys.stderr.write("\n")
    sys.stderr.flush()


def open_pty_slave(path):
    """Attach to a pty somebody else owns.  Raw, non-blocking, no controlling tty."""
    try:
        fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError as exc:
        raise SystemExit("serial-relay-o1next: cannot open %s: %s" % (path, exc))
    tty.setraw(fd)
    termios.tcsetattr(fd, termios.TCSANOW, termios.tcgetattr(fd))
    return fd, None


def make_pty():
    """Make one, and hand back (master, slave-path).

    The MASTER is ours and the path is what somebody else opens -- the opposite of
    `--pty`, and worth stating because getting it backwards produces a relay that is
    connected to nothing and reports no error at all.
    """
    master, slave = os.openpty()
    tty.setraw(master)
    tty.setraw(slave)
    os.set_blocking(master, False)
    os.set_blocking(slave, False)
    return master, os.ttyname(slave)


def open_serial(path, baud):
    """The rig's USB door, opened raw -- no pyserial, because tools/ is stdlib only.

    This is the same open the probe does, and it is here for a host-level reason: macOS's
    Local Network privacy gates *outbound* LAN connections **per binary**, and a Python
    process gets `Errno 65 No route to host` reaching a device on the local network while
    `ping`/`nc`/`curl` reach it fine.  A USB door has no network in the path, so the rig
    can be driven through it whatever the host's privacy settings say.
    """
    try:
        fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError as exc:
        raise SystemExit("serial-relay-o1next: cannot open %s: %s" % (path, exc))
    tty.setraw(fd)
    attrs = termios.tcgetattr(fd)
    attrs[4] = attrs[5] = baud
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    return fd


def relay(pty_fd, far_fd, verbose):
    """Pump both ways until one end closes.  Returns (pty->far, far->pty) byte counts.

    Both ends are plain fds -- a pty and a socket are both just fds -- so there is one
    read path and one write path rather than two of each.  Nothing is buffered beyond one
    read: a relay with a queue in it is a relay with a latency number you cannot explain,
    and the two ends here are already paced by their own hardware.
    """
    to_far = 0
    to_pty = 0
    stop = {"now": False}

    def on_signal(_signum, _frame):
        stop["now"] = True

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    while not stop["now"]:
        try:
            ready, _, _ = select.select([pty_fd, far_fd], [], [], 0.25)
        except (OSError, ValueError):
            break

        for fd in ready:
            try:
                data = os.read(fd, CHUNK)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                data = b""

            if not data:
                note("-- %s closed", "the pty" if fd == pty_fd else "the far end")
                return to_far, to_pty

            try:
                if fd == pty_fd:
                    os.write(far_fd, data)
                    to_far += len(data)
                    if verbose:
                        note("pty -> far  %4d  %s", len(data), _preview(data))
                else:
                    os.write(pty_fd, data)
                    to_pty += len(data)
                    if verbose:
                        note("far -> pty  %4d  %s", len(data), _preview(data))
            except OSError as exc:
                note("-- write failed (%s) -- closing", exc)
                return to_far, to_pty

    return to_far, to_pty


def _preview(data):
    """A printable, truncated view of a chunk -- `repr` would quote the CRLF noise out
    of existence, and the CRLF is most of what a serial session is."""
    text = "".join(chr(b) if 32 <= b < 127 else "." for b in data[:48])
    return text + ("..." if len(data) > 48 else "")


def main():
    parser = argparse.ArgumentParser(
        description="relay a pty to the bench rig (#342)")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pty", metavar="PATH",
                        help="a pty somebody else made -- MAME's `-rs232 pty` slave, "
                             "from its log")
    source.add_argument("--make-pty", action="store_true",
                        help="make a pty and print its slave path, then relay it")
    far = parser.add_mutually_exclusive_group(required=True)
    far.add_argument("--host", metavar="HOST",
                     help="the rig's address, for its TCP relay door")
    far.add_argument("--serial", metavar="PATH",
                     help="the rig's USB port instead of the network -- no LAN in the "
                          "path, so macOS's Local Network privacy cannot refuse it")
    parser.add_argument("--port", type=int, default=2323,
                        help="the rig's relay door (default: 2323)")
    parser.add_argument("--baud", type=int, default=115200,
                        help="the rig's host-door baud, for --serial (default: 115200)")
    parser.add_argument("--verbose", action="store_true",
                        help="one line per chunk, both directions")
    args = parser.parse_args()

    if args.make_pty:
        pty_fd, path = make_pty()
        note("pty:  %s  (hand this to whatever should talk to the modem)", path)
    else:
        pty_fd, _ = open_pty_slave(args.pty)
        note("pty:  %s", args.pty)

    if args.serial:
        far_fd = open_serial(args.serial, args.baud)
        note("usb:  %s at %d bps (the rig's own door -- put it in `relay` first)",
             args.serial, args.baud)
    else:
        try:
            sock = socket.create_connection((args.host, args.port), timeout=10)
        except OSError as exc:
            raise SystemExit("serial-relay-o1next: cannot reach %s:%d -- %s"
                             % (args.host, args.port, exc))
        sock.setblocking(False)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        far_fd = sock.fileno()
        note("tcp:  %s:%d (the rig's relay door -- a pure pipe)", args.host, args.port)

    started = time.time()
    to_far, to_pty = relay(pty_fd, far_fd, args.verbose)

    if not args.serial:
        sock.close()
    else:
        os.close(far_fd)
    os.close(pty_fd)

    note("")
    note("relay done: pty -> rig %d bytes, rig -> pty %d bytes, %.1f s",
         to_far, to_pty, time.time() - started)
    if to_far == 0:
        note("            nothing came from the pty -- whatever was on the other end "
             "never wrote, or is not attached")
    if to_pty == 0:
        note("            nothing came from the rig -- the modem never answered, or "
             "the wire is not the one you think")
    return 0


if __name__ == "__main__":
    sys.exit(main())
