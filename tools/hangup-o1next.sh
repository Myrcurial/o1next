#!/bin/sh
# hangup-o1next.sh [RIG_HOST] -- hang the modem up and prove it is idle.
#
# WHY THIS EXISTS
#
# A bench session that closes with the modem still in a call poisons the next one.
# The modem keeps the telnet session, so the next `ATDT` does not dial: the
# emulated terminal comes up already *inside* the old BBS session, mid-application,
# and every byte typed goes to the BBS instead of to the modem's command parser.
# That reads as "the terminal is at the wrong prompt", and it is not the terminal's
# fault -- nobody hung up.  Run this before closing the machine.
#
#   tools/hangup-o1next.sh                 # rig at the default address
#   tools/hangup-o1next.sh 192.168.2.3
#
# HOW IT REACHES THE MODEM
#
# Through the rig's TCP relay door, :2323, which is byte-transparent to UART1 and
# **always raw** -- the USB door's `+++` escape would swallow the escape before the
# modem ever saw it.
#
# ONE CLIENT AT A TIME.  The rig is a pipe, not a hub: while the relay is attached
# on the USB door, the modem's answers go *there*, and a TCP client sees nothing.
# So stop `tools/serial-relay-o1next.py` first, or this reports silence and looks
# like a dead modem.
#
# `+++` THEN `ATH`, NOT `ATH0`
#
# `+++` is the Hayes escape: about a second of silence either side and **no
# trailing CR**.  It is only needed if the modem is *in a call*; sending it when the
# modem is already in command mode just passes three pluses down the wire, which is
# harmless here.
#
# The hangup itself is **`ATH`**.  Zimodem (v4.0.3, measured 2026-10-20) accepts
# `ATH` and answers `OK`; **`ATH0` is answered `ERROR`**.  The trailing-0 form is
# Hayes-standard and is what you reach for, so this is worth knowing: an `ERROR`
# here does *not* mean the hangup failed, it means the command was not understood.
#
# The last step is the point of the script: `ATI` answers as a *modem* only when the
# modem is in command mode, so its banner plus `READY.` plus `OK` is the proof that
# nothing is off-hook.  Anything else means the call is still up.
#
# THE PROOF COMES FROM THE TRACE, NOT FROM nc
#
# The rig's console door (:2325) and its trace door (:2324) are independent of the
# relay, so the trace still records UART1 while the relay holds the USB door.  It is
# the only honest witness here, and reading it is what makes "did it hang up" a
# question with an answer rather than a hope.
set -eu
RIG="${1:-192.168.2.3}"
RELAY_PORT=2323
CONSOLE_PORT=2325

command -v nc >/dev/null 2>&1 || { echo 'nc not found' >&2; exit 1; }

console() { (printf '%s\r' "$1"; sleep "${2:-2}") | nc -w 6 "$RIG" "$CONSOLE_PORT" 2>/dev/null; }

echo "hanging up the modem through the rig's raw door, $RIG:$RELAY_PORT"
console 'trace clear' 1 >/dev/null

{
    sleep 1.0
    printf '+++'          # escape, in case a call is up; no CR
    sleep 1.5
    printf 'ATH\r'        # Zimodem's hangup -- ATH0 is an ERROR here
    sleep 2.0
    printf 'ATI\r'        # proof: a modem in command mode answers its banner
    sleep 2.5
} | nc -w 12 "$RIG" "$RELAY_PORT" >/dev/null 2>&1 || true

echo
echo '--- what crossed UART1 (from the rig trace) ---'
console 'trace dump' 3 | grep -E '^[0-9]+ [<>] ' | awk '{printf "%s", $3}' \
  | xxd -r -p 2>/dev/null | tr -d '\000' | sed 's/\r/\n/g' | sed 's/[^[:print:]\n]/./g' \
  | grep -vE '^$' || true

cat <<'NOTE'

Look for the modem's banner, READY., and OK.  Those mean it is in command mode and
nothing is off-hook.

If you got nothing, the rig's relay is probably still attached on its USB door -- the
rig is a pipe, not a hub, so the modem's answers went there.  Stop
tools/serial-relay-o1next.py and run this again.
NOTE
