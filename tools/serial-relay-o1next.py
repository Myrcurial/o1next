#!/usr/bin/env python3
"""pty <-> TCP: the host end of the bench rig's second door (#342, part of #334).

    tools/serial-relay-o1next.py --pty /dev/ttys012 --host 192.168.2.50
    tools/serial-relay-o1next.py --make-pty --host 192.168.2.50
    tools/serial-relay-o1next.py --pty /dev/ttys012 --host 192.168.2.50 --verbose

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


def relay(pty_fd, sock, verbose):
    """Pump both ways until one end closes.  Returns (pty->tcp, tcp->pty) byte counts.

    Nothing is buffered beyond one read: a relay with a queue in it is a relay with a
    latency number you cannot explain, and the two ends here are already paced by their
    own hardware.
    """
    to_tcp = 0
    to_pty = 0
    stop = {"now": False}

    def on_signal(_signum, _frame):
        stop["now"] = True

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    while not stop["now"]:
        try:
            ready, _, _ = select.select([pty_fd, sock], [], [], 0.25)
        except (OSError, ValueError):
            break

        if not ready:
            continue

        for fd in ready:
            try:
                data = os.read(fd, CHUNK) if fd == pty_fd else sock.recv(CHUNK)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                data = b""

            if not data:
                note("-- %s closed", "the pty" if fd == pty_fd else "the bridge")
                return to_tcp, to_pty

            try:
                if fd == pty_fd:
                    sock.sendall(data)
                    to_tcp += len(data)
                    if verbose:
                        note("pty -> tcp  %4d  %s", len(data), _preview(data))
                else:
                    os.write(pty_fd, data)
                    to_pty += len(data)
                    if verbose:
                        note("tcp -> pty  %4d  %s", len(data), _preview(data))
            except OSError as exc:
                note("-- write failed (%s) -- closing", exc)
                return to_tcp, to_pty

    return to_tcp, to_pty


def _preview(data):
    """A printable, truncated view of a chunk -- `repr` would quote the CRLF noise out
    of existence, and the CRLF is most of what a serial session is."""
    text = "".join(chr(b) if 32 <= b < 127 else "." for b in data[:48])
    return text + ("..." if len(data) > 48 else "")


def main():
    parser = argparse.ArgumentParser(
        description="relay a pty to the bench rig's TCP relay door (#342)")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pty", metavar="PATH",
                        help="a pty somebody else made -- MAME's `-rs232 pty` slave, "
                             "from its log")
    source.add_argument("--make-pty", action="store_true",
                        help="make a pty and print its slave path, then relay it")
    parser.add_argument("--host", required=True,
                        help="the bridge's address on the network")
    parser.add_argument("--port", type=int, default=2323,
                        help="the bridge's relay door (default: 2323)")
    parser.add_argument("--verbose", action="store_true",
                        help="one line per chunk, both directions")
    args = parser.parse_args()

    if args.make_pty:
        pty_fd, path = make_pty()
        note("pty:  %s  (hand this to whatever should talk to the modem)", path)
    else:
        pty_fd, _ = open_pty_slave(args.pty)
        note("pty:  %s", args.pty)

    try:
        sock = socket.create_connection((args.host, args.port), timeout=10)
    except OSError as exc:
        raise SystemExit("serial-relay-o1next: cannot reach %s:%d -- %s"
                         % (args.host, args.port, exc))

    sock.settimeout(None)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    note("tcp:  %s:%d (the bridge's relay door -- a pure pipe)", args.host, args.port)

    started = time.time()
    to_tcp, to_pty = relay(pty_fd, sock, args.verbose)

    sock.close()
    os.close(pty_fd)

    note("")
    note("relay done: pty -> tcp %d bytes, tcp -> pty %d bytes, %.1f s",
         to_tcp, to_pty, time.time() - started)
    if to_tcp == 0:
        note("           nothing came from the pty -- whatever was on the other end "
             "never wrote, or is not attached")
    if to_pty == 0:
        note("           nothing came from the bridge -- the modem never answered, or "
             "the wire is not the one you think")
    return 0


if __name__ == "__main__":
    sys.exit(main())
