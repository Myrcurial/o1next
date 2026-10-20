/*
   bench-bridge.ino -- the emulator's 6850 on a real wire, with the real modem on
   the other end (#342, part of #334).

   WHAT THIS IS

   A second ESP32-S2 wired as a three-wire null modem to the WiFi COMM PAC, so the
   emulated Osborne's MODEM port can be plugged into the real modem -- a virtual to
   real serial port, with no Osborne on the bench.  The modem's command interface
   is on its O1 side (UART1), and a board on a bench has no machine on the other end
   of it: `AT` cannot be typed at anything.  This board is that machine, as far as
   the modem can tell.

   It lives in the o1next repository rather than in the Zimodem fork, and that is a
   rule rather than a preference: **the device under test must not be modified by
   the rig that tests it.**

   IT IS NOT A CABLE, AND THAT IS THE POINT

   A CP2102 would prove the same wire today and could only ever be a wire.  This
   board is a counterparty: the same part can later drive the AW9523B handshake
   lines and the +12 V rail monitor (#322), and can stand in for the RP2354B's
   serial side once #323 exists.  What is on it now is the four things that make it
   more than a cable --

     * the RELAY -- UART1 <-> a host, byte-transparent;
     * the TRACE -- timestamped, both directions, so a failure is a record rather
                    than a memory;
     * the PACE  -- emit at a chosen rate (300/650/1200/2600/9600), which is the
                    part the emulator cannot do and what #319 needs;
     * and a CONSOLE that answers the same probe the modem's does, so
       `tools/identify-o1next.py` identifies both boards with one tool.

   THE TWO DOORS, AND WHY THE CONSOLE IS ONE OF THEM

   The relay has two host ends -- the USB CDC and a TCP listener -- because the
   Stage 1 emulator attaches over TCP (MAME's bitbanger, or a host relay), while
   Stage 0 is a person with a terminal.  The TCP door is ALWAYS a pure pipe and has
   no console at all.

   The USB CDC cannot be a pure pipe, because it must answer the probe: the board
   identifies itself by answering a bare CR with a prompt and `status`, and a
   `status` that went down the wire to the modem would be a different board's
   answer.  So the CDC has two states and the default is the CONSOLE:

     boot     -> console.  `o1next> `, and `status` names the role and the MAC.
     `relay`  -> the CDC becomes the relay's host end.  Byte-transparent.
     `+++`    -> back to the console (see the escape, below).

   The escape is Hayes' own, with a guard: one second of silence, then three pluses.
   A `+++` in the middle of a file transfer is the one thing that would look like an
   escape, and one second of silence mid-transfer is exactly when you want out -- so
   the guard is the whole of the safety argument.  **`relay raw` turns the escape
   off**, and that is what to use when the modem must see the `+++` itself: the
   modem's own parser hangs a connection up on `+++`, and a bridge that ate it would
   make that impossible.

   THE WIRE (three wires, crossed, 3.3 V, no level shifting)

     COMM PAC  GPIO15 UART1 TX  ->  bridge GPIO18 (UART1 RX)
     COMM PAC  GPIO16 UART1 RX  <-  bridge GPIO17 (UART1 TX)
     COMM PAC  GND              --  bridge GND

   GPIO17/18 are UART1's own IO-MUX default on the S2, which is why they are the
   natural pair on the bridge side; on the modem side the map puts UART1 on 15/16
   instead, to keep the two DACs free (`hardware/wifi-comm-pac/pinmap.md`).  **No
   power wire between the boards**: each is powered from its own USB port.  Nothing
   on the modem's P1 level stage is in this path -- the rig lands on the module's
   UART1 pins, at 3.3 V.

   THE TRACE FORMAT

   Defined in README.md beside this file, and shared rather than invented twice: the
   envelope is `#o1next-trace <version> <source> <unit>` then `<t> <kind> <payload>`,
   so `firmware/bus-analyzer/` and `tools/trace-analyzer/` can carry the same reader
   with a different payload.  It is deliberately line-oriented text: a trace you
   cannot read with `grep` is a trace you will not read.
*/

#include <WiFi.h>
#include <Preferences.h>
#include <esp_mac.h>
#include <soc/rtc_cntl_reg.h>
#include <soc/soc.h>
#include <ctype.h>
#include <stdarg.h>
#include <string.h>

/* ------------------------------------------------------------------- the wire --
 *
 * Overridable with `-D`, because the *bridge* end of the wire has to follow
 * whatever the parts-bin board actually brings out to its header.  The defaults are
 * UART1's IO-MUX pair, which is also what this rig is wired to (2026-10-20).
 */
#ifndef BRIDGE_RXD
#define BRIDGE_RXD              18
#endif
#ifndef BRIDGE_TXD
#define BRIDGE_TXD              17
#endif

/* The bridge board's own BOOT strap.  It is the one thing on any ESP32 that is the
 * same pin everywhere, and `bootloader` drives it low on the way to the ROM. */
#ifndef BRIDGE_BOOT_STRAP
#define BRIDGE_BOOT_STRAP       0
#endif

/* ------------------------------------------------ the HOST door, and its rate --
 *
 * This is the difference between the two boards this rig has been built on, and it
 * is worth stating because it is the one thing that is NOT the same shape.
 *
 *   ESP32-S2 (the modem's part, and our own PCB): the host door is the NATIVE USB
 *   CDC.  `Serial` is a USB endpoint, there is no wire, and the baud rate is a
 *   decoration -- the host cannot get it wrong.
 *
 *   Classic ESP32 (a 38-pin devkit, which is what the rig is on now): the host door
 *   is UART0 through a CP2102.  **There IS a wire, and the host's baud has to match
 *   this number.**  macOS gives a fresh CP2102 port 9600 by default, so a host that
 *   opens the port and says nothing is at 9600 -- which is why `identify-o1next.py`
 *   needs `--baud 115200` to reach this console, and why 115200 (the ESP32's own
 *   default, and the ROM's log rate) is the value chosen here rather than a slower
 *   one that would have needed no flag: the host door also carries the relay, and
 *   9600 would cap the whole rig at the fastest rate the machine side can run.
 */
#ifndef BRIDGE_HOST_BAUD
#define BRIDGE_HOST_BAUD        115200
#endif

/* The O1-side rate at boot.  1200, because that is the modem's own
 * DEFAULT_BAUD_RATE -- so `AT` works out of the box, with nothing typed first, and
 * the ladder is walked from a rate both ends already agree on. */
#ifndef BRIDGE_RATE
#define BRIDGE_RATE             1200
#endif

/* The three TCP doors.  Distinct ports rather than one multiplexed port, because
 * they carry three different things and a reader should not have to demultiplex to
 * find out which. */
#ifndef BRIDGE_RELAY_PORT
#define BRIDGE_RELAY_PORT       2323
#endif
#ifndef BRIDGE_TRACE_PORT
#define BRIDGE_TRACE_PORT       2324
#endif
#ifndef BRIDGE_CONSOLE_PORT
#define BRIDGE_CONSOLE_PORT     2325
#endif

/* ------------------------------------------------------------- the trace ring --
 *
 * A record is a RUN of bytes in one direction, not one byte: at 9600 baud a
 * byte-per-record trace is 960 lines a second, which is unreadable and unbounded.
 * A run is emitted when the line goes quiet (BRIDGE_TRACE_IDLE_MS) or when it fills
 * (BRIDGE_TRACE_RUN), and the timestamp is the FIRST byte's -- so a run is "these
 * bytes arrived together", which is what a serial trace is for.
 *
 * 256 x 70 bytes is ~18 KB of a 320 KB SRAM, and it is a ring: the newest evidence
 * is what survives, and `trace dump` is what reads it back.
 */
#ifndef BRIDGE_TRACE_RUN
#define BRIDGE_TRACE_RUN        64
#endif
#ifndef BRIDGE_TRACE_DEPTH
#define BRIDGE_TRACE_DEPTH      256
#endif
#ifndef BRIDGE_TRACE_IDLE_MS
#define BRIDGE_TRACE_IDLE_MS    3
#endif

/* --------------------------------------------------------------- the console -- */
#ifndef BRIDGE_LINE_MAX
#define BRIDGE_LINE_MAX         64
#endif
#ifndef BRIDGE_ESCAPE_GUARD_MS
#define BRIDGE_ESCAPE_GUARD_MS  1000
#endif

/* A run of bytes at the current rate is a *paced* write, so it blocks the loop for
 * its whole duration -- 4096 bytes at 300 baud is over two minutes.  The cap is
 * what keeps a typo from looking like a hung board. */
#ifndef BRIDGE_PACE_MAX
#define BRIDGE_PACE_MAX         4096
#endif

#define BRIDGE_TRACE_VERSION    "1"
#define BRIDGE_TRACE_SOURCE     "bench-bridge"

/* ------------------------------------------------------------------- state ---- */

struct BridgeLine {
    char   buf[BRIDGE_LINE_MAX];
    size_t len;
    bool   overflow;
    char   lastTerm;
};

struct BridgeRun {
    uint32_t t;                      /* the first byte's millis() */
    char     dir;                    /* '>' toward the machine, '<' from it */
    uint8_t  n;
    uint8_t  b[BRIDGE_TRACE_RUN];
};

static BridgeRun bridgeTrace[BRIDGE_TRACE_DEPTH];
static uint16_t  bridgeTraceHead;     /* next slot to write */
static uint16_t  bridgeTraceCount;    /* records held, <= BRIDGE_TRACE_DEPTH */
static bool      bridgeTraceOn = true;
static BridgeRun bridgePending[2];    /* one per direction, awaiting the idle flush */
static uint32_t  bridgePendingLast[2];/* when the last byte of that run arrived */

static uint32_t bridgeHostToMachine;  /* bytes relayed toward the machine */
static uint32_t bridgeMachineToHost;  /* bytes relayed from it */
static uint32_t bridgeDropped;        /* machine bytes with nowhere to go */
static uint32_t bridgeEscapes;        /* escapes taken, for the counters line */

/* The relay's host end.  `bridgeRelayActive` is the USB CDC; `bridgeRelayClient` is
 * the TCP door.  At most one at a time, deliberately: two host ends on one UART is
 * interleaving, not a feature. */
static bool       bridgeRelayActive;
static bool       bridgeRelayRaw;     /* escape disabled -- see the header */
static WiFiClient bridgeRelayClient;
static WiFiClient bridgeConsoleClient;
static WiFiClient bridgeTraceClient;

static WiFiServer bridgeRelayServer(BRIDGE_RELAY_PORT);
static WiFiServer bridgeTraceServer(BRIDGE_TRACE_PORT);
static WiFiServer bridgeConsoleServer(BRIDGE_CONSOLE_PORT);

static BridgeLine bridgeUsbLine;
static BridgeLine bridgeTcpLine;

static Preferences bridgePrefs;

static uint32_t bridgeHostLastMs;     /* last byte from the relay's host end */
static uint8_t  bridgeEscapeRun;      /* '+' held, awaiting the third */
static uint32_t bridgeEscapeAtMs;

static bool     bridgeWifiUp;
static char     bridgeSsid[33];
static char     bridgePass[65];
static uint32_t bridgeWifiRetryAt;

/* The O1-side rate, and the one place that changes it.  `updateBaudRate` is what
 * keeps the UART's FIFO rather than reopening it, so a rate change does not drop a
 * byte that is already in flight. */
static uint32_t bridgeRate = BRIDGE_RATE;

static void bridgeSetRate(uint32_t rate)
{
    bridgeRate = rate;
    Serial1.updateBaudRate(rate);
}

/* ------------------------------------------------------------------ helpers --- */

static void bridgeMac(char *out, size_t outlen)
{
    uint8_t mac[6] = { 0, 0, 0, 0, 0, 0 };

    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) != ESP_OK)
        snprintf(out, outlen, "unreadable");
    else
        snprintf(out, outlen, "%02x:%02x:%02x:%02x:%02x:%02x",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

/* Console text goes to the USB CDC and to the TCP console client if one is
 * attached.  **Nothing is written to the USB CDC while the relay owns it** -- a
 * stray `o1next> ` in the middle of a file transfer is the exact failure this rig
 * exists to make impossible. */
static void bridgePrintf(const char *fmt, ...)
{
    char    line[256];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);

    if (!bridgeRelayActive)
        Serial.print(line);
    if (bridgeConsoleClient)
        bridgeConsoleClient.print(line);
}

static void bridgePrompt(void)
{
    bridgePrintf("o1next> ");
}

/* One record, formatted.  The reader on the trace door and `trace dump` on the
 * console emit the SAME line -- the format is the format, wherever it is read. */
static size_t bridgeTraceFormat(const BridgeRun &run, char *out, size_t outlen)
{
    int      used;
    unsigned i;

    used = snprintf(out, outlen, "%lu %c", (unsigned long)run.t, run.dir);
    for (i = 0; i < run.n && used > 0 && (size_t)used < outlen - 4; i++)
        used += snprintf(out + used, outlen - used, " %02x", run.b[i]);
    snprintf(out + used, outlen - used, "\r\n");
    return (size_t)used;
}

static void bridgeTraceRecord(const BridgeRun &run)
{
    char line[BRIDGE_TRACE_RUN * 3 + 32];

    if (!bridgeTraceClient)
        return;

    bridgeTraceFormat(run, line, sizeof(line));
    bridgeTraceClient.print(line);
}

/* --------------------------------------------------------------- the trace ---- */

static void bridgeTracePut(const BridgeRun &run)
{
    if (!bridgeTraceOn || run.n == 0)
        return;

    bridgeTrace[bridgeTraceHead] = run;
    bridgeTraceHead = (uint16_t)((bridgeTraceHead + 1) % BRIDGE_TRACE_DEPTH);
    if (bridgeTraceCount < BRIDGE_TRACE_DEPTH)
        bridgeTraceCount++;

    bridgeTraceRecord(run);
}

/* Add bytes to the pending run for a direction, emitting when it fills.  `slot` is
 * 0 for toward-the-machine and 1 for from-it, so the two directions never merge
 * into one record: the interleaving is the evidence. */
static void bridgeTraceAdd(uint8_t slot, char dir, const uint8_t *bytes, size_t n)
{
    BridgeRun &run = bridgePending[slot];

    while (n > 0) {
        if (run.n == 0) {
            run.t   = millis();
            run.dir = dir;
        }
        size_t room = BRIDGE_TRACE_RUN - run.n;
        size_t take = (n < room) ? n : room;

        memcpy(run.b + run.n, bytes, take);
        run.n = (uint8_t)(run.n + take);
        bytes += take;
        n     -= take;
        bridgePendingLast[slot] = millis();

        if (run.n == BRIDGE_TRACE_RUN) {
            bridgeTracePut(run);
            run.n = 0;
        }
    }
}

/* The idle flush.  A run is "bytes that arrived together", so it ends when the line
 * goes quiet rather than when a record is full -- at 1200 baud that is one or two
 * bytes per record, which is what makes a trace readable byte by byte.
 *
 * The clock is the LAST byte's, not the first's: a run that kept being appended to
 * would otherwise never look idle, and a record whose timestamp is minutes stale is
 * worse than no record. */
static void bridgeTraceFlush(void)
{
    for (uint8_t slot = 0; slot < 2; slot++) {
        BridgeRun &run = bridgePending[slot];

        if (run.n > 0 && (millis() - bridgePendingLast[slot]) >= BRIDGE_TRACE_IDLE_MS) {
            bridgeTracePut(run);
            run.n = 0;
        }
    }
}

static void bridgeTraceHeader(void)
{
    if (bridgeTraceClient)
        bridgeTraceClient.printf("#o1next-trace %s %s ms\r\n",
                                 BRIDGE_TRACE_VERSION, BRIDGE_TRACE_SOURCE);
}

/* ---------------------------------------------------------------- the machine -- */

static void bridgeToMachine(const uint8_t *bytes, size_t n)
{
    if (n == 0)
        return;

    Serial1.write(bytes, n);              /* paced by the UART's own baud rate */
    bridgeHostToMachine += n;
    bridgeTraceAdd(0, '>', bytes, n);
}

/* UART1 -> the relay's host end.  The sink is the USB CDC while the relay owns it,
 * else the single TCP relay client.  **With no sink the bytes are dropped and
 * COUNTED rather than buffered**: a bench rig that silently grows a queue is a rig
 * that lies about the past, and the counter is on the `status` line so a drop is
 * visible rather than inferred. */
static void bridgeFromMachine(const uint8_t *bytes, size_t n)
{
    if (n == 0)
        return;

    bridgeTraceAdd(1, '<', bytes, n);

    if (bridgeRelayActive)
        Serial.write(bytes, n);
    else if (bridgeRelayClient)
        bridgeRelayClient.write(bytes, n);
    else {
        bridgeDropped += n;
        return;
    }

    bridgeMachineToHost += n;
}

/* -------------------------------------------------------------- the escaping --
 *
 * Hayes' escape, with the pre-guard it needs: one second of silence, then `+` `+`
 * `+`.  The three pluses are HELD rather than forwarded, because forwarding the
 * first two and then escaping would put two stray bytes on the wire -- and a partial
 * run is flushed the moment a non-plus arrives, or when the hold times out, so the
 * only thing this can lose is three pluses after a second of silence, which is the
 * escape by definition.
 *
 * `relay raw` skips all of this.  It is what to use for XMODEM/ZMODEM and for the
 * modem's own `+++` hangup.
 */
static void bridgeRelayHostByte(uint8_t c)
{
    uint32_t now    = millis();
    bool     guarded = (now - bridgeHostLastMs) >= BRIDGE_ESCAPE_GUARD_MS;

    if (bridgeRelayRaw) {
        bridgeToMachine(&c, 1);
        bridgeHostLastMs = now;
        return;
    }

    if (bridgeEscapeRun > 0) {
        if (c == '+') {
            bridgeEscapeRun++;
            bridgeHostLastMs = now;
            if (bridgeEscapeRun >= 3) {
                bridgeEscapeRun = 0;
                bridgeEscapes++;
                bridgeRelayActive = false;
                bridgePrintf("\r\n-- escaped to the console (%lu bytes in, %lu out, "
                             "%lu dropped)\r\n",
                             (unsigned long)bridgeHostToMachine,
                             (unsigned long)bridgeMachineToHost,
                             (unsigned long)bridgeDropped);
                bridgePrompt();
            }
            return;
        }
        for (uint8_t i = 0; i < bridgeEscapeRun; i++) {
            uint8_t plus = '+';
            bridgeToMachine(&plus, 1);
        }
        bridgeEscapeRun = 0;
    }

    if (guarded && c == '+') {
        bridgeEscapeRun  = 1;
        bridgeEscapeAtMs = now;
        bridgeHostLastMs = now;
        return;
    }

    bridgeToMachine(&c, 1);
    bridgeHostLastMs = now;
}

/* A held '+' that is never completed must still reach the machine, or a stray plus
 * would vanish.  This is the timeout half of the escape. */
static void bridgeEscapeTimeout(void)
{
    if (bridgeEscapeRun == 0)
        return;
    if ((millis() - bridgeEscapeAtMs) < BRIDGE_ESCAPE_GUARD_MS)
        return;

    for (uint8_t i = 0; i < bridgeEscapeRun; i++) {
        uint8_t plus = '+';
        bridgeToMachine(&plus, 1);
    }
    bridgeEscapeRun = 0;
}

/* ------------------------------------------------------------------ commands --- */

static void bridgeHelp(void)
{
    bridgePrintf(
        "\r\ncommands:\r\n"
        "  status      role, MAC, pins, rate, the doors, and the byte counters\r\n"
        "  relay       the USB CDC becomes the relay: byte-transparent to UART1.\r\n"
        "              `+++` after a second of silence comes back here.\r\n"
        "  relay raw   the same, with the escape OFF -- for XMODEM/ZMODEM and for\r\n"
        "              the modem's own `+++` hangup.\r\n"
        "  relay off   stop relaying (reachable from the TCP console, or the escape)\r\n"
        "  rate [bps]  the O1-side rate: report it, or set it.  300/650/1200/2600/\r\n"
        "              9600 are the O1's own; anything 50..2000000 is accepted\r\n"
        "  send <text> write <text> and a CR to UART1 at the current rate\r\n"
        "  pace <n> [hh]  emit <n> bytes (default 0x55) at the current rate -- the\r\n"
        "              paced source #319 measures against.  It BLOCKS until done\r\n"
        "  trace [on|off|clear|dump]  the record: toggling, emptying, or reading it\r\n"
        "              back.  A reader attaches on TCP %d and gets it live\r\n"
        "  wifi        report the network; `wifi <ssid> <password>` joins and saves;\r\n"
        "              `wifi off` leaves.  2.4 GHz only -- that is the radio\r\n"
        "  reboot      esp_restart() -- back into the application\r\n"
        "  bootloader  force the ROM's download mode and reset -- no button.  On a\r\n"
        "              board with no auto-reset circuit this is the only way back\r\n"
        "              to a flash tool\r\n"
        "  help        this\r\n"
        "\r\n"
        "  The TCP doors are the RELAY on %d, the TRACE on %d and this CONSOLE on\r\n"
        "  %d.  The relay door is always a pure pipe.\r\n",
        BRIDGE_TRACE_PORT, BRIDGE_RELAY_PORT, BRIDGE_TRACE_PORT, BRIDGE_CONSOLE_PORT);
}

static void bridgeStatus(void)
{
    char mac[24];

    bridgeMac(mac, sizeof(mac));

    bridgePrintf("\r\nbench-bridge -- the o1next bench rig (built %s %s)\r\n",
                 __DATE__, __TIME__);
    /* The part is READ, not assumed.  The rig builds for three families and this line
     * said "ESP32-S2" on all of them until the C3 session noticed -- which is exactly
     * the kind of lie a `status` exists to prevent. */
    bridgePrintf("board    %s rev %u, %u core(s), flash %u bytes, MAC %s\r\n",
                 ESP.getChipModel(), (unsigned)ESP.getChipRevision(),
                 (unsigned)ESP.getChipCores(),
                 (unsigned)ESP.getFlashChipSize(), mac);
    bridgePrintf("role     bridge -- the wire's host end; the machine end is the modem\r\n");
    bridgePrintf("serial   O1 side is UART1: RXD %d, TXD %d, %lu bps\r\n",
                 BRIDGE_RXD, BRIDGE_TXD, (unsigned long)bridgeRate);
    bridgePrintf("link     relay %s%s\r\n",
                 bridgeRelayActive ? "USB CDC" : "idle",
                 bridgeRelayActive && bridgeRelayRaw ? " (raw, no escape)" : "");
    /* The DOORS are a separate line from the CLIENTS, and it is not cosmetic: a board
     * can be on the network, answering ping, with every port closed because the
     * listeners were never begun.  That happened here on 2026-10-20, and nothing in
     * `status` said so -- the line below is what would have. */
    bridgePrintf("doors    %s -- relay :%d, trace :%d, console :%d\r\n",
                 bridgeWifiUp ? "OPEN" : "closed (no wifi)",
                 BRIDGE_RELAY_PORT, BRIDGE_TRACE_PORT, BRIDGE_CONSOLE_PORT);
    bridgePrintf("clients  tcp relay %s, console %s, trace reader %s\r\n",
                 bridgeRelayClient ? "attached" : "free",
                 bridgeConsoleClient ? "attached" : "free",
                 bridgeTraceClient ? "attached" : "free");
    bridgePrintf("counters in %lu, out %lu, dropped %lu, escapes %lu\r\n",
                 (unsigned long)bridgeHostToMachine,
                 (unsigned long)bridgeMachineToHost,
                 (unsigned long)bridgeDropped,
                 (unsigned long)bridgeEscapes);
    bridgePrintf("trace    %s, %u of %d records\r\n",
                 bridgeTraceOn ? "recording" : "off",
                 (unsigned)bridgeTraceCount, BRIDGE_TRACE_DEPTH);

    if (bridgeWifiUp)
        bridgePrintf("wifi     %s, %s\r\n", bridgeSsid, WiFi.localIP().toString().c_str());
    else
        bridgePrintf("wifi     not connected -- the TCP doors are closed\r\n");

    bridgePrintf("uptime   %lu.%01lu s\r\n",
                 millis() / 1000UL, (millis() % 1000UL) / 100UL);
}

/* ---------------------------------------------------------------- rate, send -- */

static void bridgeSend(const char *text)
{
    if (text == NULL) {
        bridgePrintf("send needs something to send: send AT\r\n");
        return;
    }

    size_t n = strlen(text);

    /* The CR is added here rather than expected in the line, because a line has no
     * way to carry one -- and every Hayes command needs it. */
    uint8_t buf[BRIDGE_LINE_MAX + 1];
    if (n > BRIDGE_LINE_MAX)
        n = BRIDGE_LINE_MAX;
    memcpy(buf, text, n);
    buf[n] = '\r';
    bridgeToMachine(buf, n + 1);

    bridgePrintf("sent %u bytes at %lu bps\r\n", (unsigned)(n + 1),
                 (unsigned long)bridgeRate);
}

/* The paced source.  This is the part the emulator cannot do and #319 needs: the
 * UART hardware paces the bytes, so the waveform is the rate, exactly -- and 0x55
 * is the default byte because 0101... is a square wave at half the baud rate, which
 * is what a period-measuring front end wants to see.
 *
 * It blocks the loop for the whole run, and says so in `help`: 4096 bytes at 300
 * baud is over two minutes.  `delay(1)` between chunks is what keeps the task
 * watchdog fed while the FIFO drains. */
static void bridgePace(long count, int byte)
{
    uint8_t buf[32];

    if (count <= 0) {
        bridgePrintf("pace needs a byte count: pace 1024 [55]\r\n");
        return;
    }
    if (count > BRIDGE_PACE_MAX) {
        bridgePrintf("pace is capped at %d bytes; %ld would block this console for "
                     "minutes\r\n", BRIDGE_PACE_MAX, count);
        return;
    }

    memset(buf, (uint8_t)byte, sizeof(buf));

    bridgePrintf("pacing %ld bytes of 0x%02x at %lu bps -- %.1f s of wire\r\n",
                 count, (unsigned)byte, (unsigned long)bridgeRate,
                 (double)count * 10.0 / (double)bridgeRate);

    while (count > 0) {
        size_t chunk = (count > (long)sizeof(buf)) ? sizeof(buf) : (size_t)count;
        bridgeToMachine(buf, chunk);
        count -= (long)chunk;
        delay(1);                       /* the idle task feeds the watchdog */
    }

    bridgePrintf("done\r\n");
}

/* ------------------------------------------------------------------- the trace -- */

static void bridgeTraceDump(void)
{
    char     line[BRIDGE_TRACE_RUN * 3 + 32];
    uint16_t start;

    if (bridgeTraceCount == 0) {
        bridgePrintf("trace is empty\r\n");
        return;
    }

    start = (bridgeTraceCount < BRIDGE_TRACE_DEPTH) ? 0 : bridgeTraceHead;

    /* The header goes out with the dump too, so a saved dump is self-describing --
     * the same reason the live reader gets one on attach. */
    bridgePrintf("#o1next-trace %s %s ms\r\n", BRIDGE_TRACE_VERSION, BRIDGE_TRACE_SOURCE);
    for (uint16_t i = 0; i < bridgeTraceCount; i++) {
        const BridgeRun &run = bridgeTrace[(start + i) % BRIDGE_TRACE_DEPTH];
        bridgeTraceFormat(run, line, sizeof(line));
        bridgePrintf("%s", line);
    }
    bridgePrintf("-- %u records\r\n", (unsigned)bridgeTraceCount);
}

static void bridgeTraceCommand(const char *arg)
{
    if (arg == NULL || !strcmp(arg, "on")) {
        bridgeTraceOn = true;
        bridgePrintf("trace recording\r\n");
    } else if (!strcmp(arg, "off")) {
        bridgeTraceOn = false;
        bridgePrintf("trace off (the %u records already held are still dumpable)\r\n",
                     (unsigned)bridgeTraceCount);
    } else if (!strcmp(arg, "clear")) {
        bridgeTraceHead  = 0;
        bridgeTraceCount = 0;
        bridgePending[0].n = 0;
        bridgePending[1].n = 0;
        bridgePrintf("trace cleared\r\n");
    } else if (!strcmp(arg, "dump")) {
        bridgeTraceDump();
    } else {
        bridgePrintf("trace takes on, off, clear or dump\r\n");
    }
}

/* --------------------------------------------------------------------- wifi ---- */

static void bridgeWifiLoad(void)
{
    bridgePrefs.begin("bench-bridge", true);
    String ssid = bridgePrefs.getString("ssid", "");
    String pass = bridgePrefs.getString("pass", "");
    bridgePrefs.end();

    snprintf(bridgeSsid, sizeof(bridgeSsid), "%s", ssid.c_str());
    snprintf(bridgePass, sizeof(bridgePass), "%s", pass.c_str());
}

static void bridgeWifiSave(const char *ssid, const char *pass)
{
    bridgePrefs.begin("bench-bridge", false);
    bridgePrefs.putString("ssid", ssid);
    bridgePrefs.putString("pass", pass);
    bridgePrefs.end();

    snprintf(bridgeSsid, sizeof(bridgeSsid), "%s", ssid);
    snprintf(bridgePass, sizeof(bridgePass), "%s", pass);
}

/* Joining blocks for a bounded time and then says what happened.  A console that hangs
 * on a network that is not there is the same failure as a hang with no message, which is
 * the worst shape a failure can have.
 *
 * **It does not touch `bridgeWifiUp`, and that is a bug it used to have.** That flag
 * means "the doors are open", and only bridgeNetPoll() may set it -- because opening the
 * doors is what it does when it sees the flag go from false to true.  Setting it here as
 * well meant that joining from the *console* (rather than from setup) left the three
 * listeners never begun: the flag was already true, so bridgeNetPoll skipped the branch
 * that calls begin(), and the board sat on the network answering nothing.  Measured on
 * the C3 rig 2026-10-20 -- ping replied, all three ports were closed, and nothing in
 * `status` said why. */
static bool bridgeWifiJoin(const char *ssid, const char *pass, unsigned timeout_s)
{
    WiFi.mode(WIFI_STA);
    WiFi.setSleep(false);               /* latency on a relay, not battery */
    WiFi.begin(ssid, pass);

    for (unsigned i = 0; i < timeout_s * 2; i++) {
        if (WiFi.status() == WL_CONNECTED)
            return true;
        delay(500);
    }
    return false;
}

static void bridgeWifiCommand(const char *arg)
{
    if (arg == NULL) {
        if (bridgeWifiUp)
            bridgePrintf("wifi %s, %s, rssi %d dBm\r\n", bridgeSsid,
                         WiFi.localIP().toString().c_str(), WiFi.RSSI());
        else if (bridgeSsid[0])
            bridgePrintf("wifi saved %s, not connected\r\n", bridgeSsid);
        else
            bridgePrintf("wifi not configured: wifi <ssid> <password>\r\n");
        return;
    }

    if (!strcmp(arg, "off")) {
        WiFi.disconnect(true);
        bridgeWifiUp = false;
        bridgePrintf("wifi disconnected\r\n");
        return;
    }

    /* `wifi <ssid> <password>` -- split on the first space, and the password is
     * everything after it, because a password may contain spaces and an SSID may
     * not contain the one that separates them. */
    char  work[130];
    snprintf(work, sizeof(work), "%s", arg);

    char *pass = strchr(work, ' ');
    if (pass == NULL) {
        bridgePrintf("wifi needs both: wifi <ssid> <password>\r\n");
        return;
    }
    *pass++ = '\0';
    while (*pass == ' ')
        pass++;

    bridgePrintf("joining %s ...\r\n", work);
    if (bridgeWifiJoin(work, pass, 20)) {
        bridgeWifiSave(work, pass);
        bridgePrintf("joined, %s -- saved, so it comes back on its own\r\n",
                     WiFi.localIP().toString().c_str());
    } else {
        bridgePrintf("did not join %s in 20 s.  The radio is 2.4 GHz only; "
                     "`status` still works, and so does the USB relay\r\n", work);
    }
}

/* ------------------------------------------------------- relay, rate, pacing -- */

static void bridgeRelayCommand(const char *arg)
{
    if (arg != NULL && !strcmp(arg, "off")) {
        /* Reachable from the TCP console, or from the escape.  It cannot be reached
         * from the USB console while the relay owns it, which is the point. */
        bridgeRelayActive = false;
        bridgeRelayRaw    = false;
        bridgePrintf("relay stopped -- the USB CDC is the console again\r\n");
        return;
    }

    if (arg != NULL && strcmp(arg, "raw")) {
        bridgePrintf("relay takes raw or off\r\n");
        return;
    }

    if (bridgeRelayClient) {
        bridgePrintf("the TCP relay door already owns UART1 -- one host end at a "
                     "time, or the two interleave\r\n");
        return;
    }

    bool raw = (arg != NULL);

    /* The message goes out BEFORE the flag flips, because once it flips nothing
     * writes to the USB CDC at all. */
    bridgePrintf("\r\n-- relaying.  %s\r\n"
                 "   %lu bps on UART1 (RXD %d, TXD %d).  Nothing else is printed here "
                 "until you leave.\r\n",
                 raw ? "raw: every byte passes, `+++` included"
                     : "`+++` after a second of silence comes back to this console",
                 (unsigned long)bridgeRate, BRIDGE_RXD, BRIDGE_TXD);
    Serial.flush();

    bridgeHostLastMs  = millis();
    bridgeEscapeRun   = 0;
    bridgeRelayRaw    = raw;
    bridgeRelayActive = true;
}

static void bridgeRateCommand(const char *arg)
{
    if (arg == NULL) {
        bridgePrintf("rate %lu bps on UART1\r\n", (unsigned long)bridgeRate);
        return;
    }

    long wanted = atol(arg);
    if (wanted < 50 || wanted > 2000000) {
        bridgePrintf("rate takes 50..2000000 bps; the O1's own are 300, 650, 1200, "
                     "2600 and 9600\r\n");
        return;
    }

    bridgeSetRate((uint32_t)wanted);
    bridgePrintf("rate %lu bps\r\n", (unsigned long)bridgeRate);

    /* The one thing this command cannot do is change the modem's rate: the modem
     * measures (or is told) its own, and a mismatched pair is line noise at both
     * ends.  Saying so here is cheaper than a session spent wondering. */
    if (bridgeRate != BRIDGE_RATE)
        bridgePrintf("         the MODEM must be at this rate too -- `send ATB %lu` "
                     "while both ends still agree\r\n", (unsigned long)bridgeRate);
}

static void bridgePaceCommand(const char *arg)
{
    char  work[48];
    char *second;
    long  count = 0;
    int   byte  = 0x55;

    if (arg == NULL) {
        bridgePrintf("pace <bytes> [hex byte] -- e.g. pace 1024 55\r\n");
        return;
    }

    snprintf(work, sizeof(work), "%s", arg);

    second = strchr(work, ' ');
    if (second != NULL) {
        *second++ = '\0';
        while (*second == ' ')
            second++;
        byte = (int)strtol(second, NULL, 16);
    }
    count = atol(work);

    bridgePace(count, byte & 0xFF);
}

/* ------------------------------------------------------------- the two pumps --- */

/* One line in, one line out -- the same shape as the modem's console, for the same
 * reason: a partially typed line lives in a buffer between calls, and nothing here
 * ever waits.  `echo` is the door the byte came from, so a TCP console client sees
 * its own typing and the USB console is not sprayed with another door's keystrokes. */
static void bridgeLineFeed(BridgeLine &line, int c, WiFiClient *echo)
{
    if (c == '\r' || c == '\n') {
        /* A terminator that follows a terminator is not a new line -- but a bare CR
         * must still get a prompt, because that is exactly how the probe asks.  So a
         * terminator is swallowed only when it is the OTHER one from the one that
         * just ended a line (CRLF is one line, two Enters are two). */
        if (line.lastTerm != 0 && c != line.lastTerm) {
            line.lastTerm = 0;
            return;
        }
        line.lastTerm = (char)c;

        line.buf[line.len] = '\0';
        if (line.overflow)
            bridgePrintf("line too long -- dropped rather than truncated\r\n");
        else if (line.len > 0)
            bridgeRun(line.buf);
        line.len      = 0;
        line.overflow = false;
        bridgePrompt();
        return;
    }

    line.lastTerm = 0;

    if (line.len + 1 < sizeof(line.buf))
        line.buf[line.len++] = (char)c;
    else
        line.overflow = true;

    if (echo != NULL) {
        if (*echo)
            echo->write((uint8_t)c);
    } else if (!bridgeRelayActive) {
        Serial.write((uint8_t)c);
    }
}

/* Every host-side read.  In relay mode the USB CDC is the relay's host end and its
 * bytes go straight to the machine; otherwise it is the console.  The TCP relay door
 * is ALWAYS a pure pipe and is never inspected -- that is what makes it the door to
 * use when the modem must see `+++`, and what makes a byte count there mean what it
 * says. */
static void bridgeHostPump(void)
{
    while (Serial.available() > 0) {
        int c = Serial.read();
        if (c < 0)
            break;
        if (bridgeRelayActive)
            bridgeRelayHostByte((uint8_t)c);
        else
            bridgeLineFeed(bridgeUsbLine, c, NULL);
    }

    if (bridgeRelayClient) {
        uint8_t buf[128];
        while (bridgeRelayClient.available() > 0) {
            size_t n = bridgeRelayClient.read(buf, sizeof(buf));
            if (n == 0)
                break;
            bridgeToMachine(buf, n);
            bridgeHostLastMs = millis();
        }
    }

    if (bridgeConsoleClient) {
        while (bridgeConsoleClient.available() > 0) {
            int c = bridgeConsoleClient.read();
            if (c < 0)
                break;
            bridgeLineFeed(bridgeTcpLine, c, &bridgeConsoleClient);
        }
    }
}

static void bridgeUartPump(void)
{
    uint8_t buf[128];

    while (Serial1.available() > 0) {
        size_t n = Serial1.read(buf, sizeof(buf));
        if (n == 0)
            break;
        bridgeFromMachine(buf, n);
    }
}

/* ------------------------------------------------------- reboot, bootloader ---- */


static void bridgeReboot(void)
{
    bridgePrintf("rebooting into the application\r\n");
    if (!bridgeRelayActive)
        Serial.flush();
    delay(50);
    esp_restart();
}

/* The BOOT strap is the half of this that is the same on every ESP32: GPIO0, pulled
 * low.  The other half is not, and the difference is worth writing down because it
 * is the one place a rig built on a classic part behaves differently from one built
 * on the S2.
 *
 *   S2 / S3: RTC_CNTL_OPTION1_REG has a FORCE_DOWNLOAD_BOOT bit.  It lives in the
 *   RTC domain, so it survives a software reset, and the ROM honours it on the way
 *   back up -- which is the mechanism the Arduino core itself uses
 *   (cores/esp32/esp32-hal-tinyusb.c, usb_persist_restart).  This is what makes a
 *   native-USB board with no auto-reset circuit flashable without a finger.
 *
 *   Classic ESP32: **there is no such bit.**  RTC_CNTL_OPTION1_REG does not exist in
 *   its register map (checked against the core's own soc/esp32 headers, 2026-10-20),
 *   and the only RTC reset it has is SW_SYS_RST, which is what esp_restart() already
 *   does.  So the strap has to be sampled by a HARDWARE reset, and this command's
 *   job is to hold the strap low and say so rather than to pretend.
 *
 * Either way GPIO0 is driven low, and either way the note about the SW reset stands:
 * an SW system reset does NOT re-sample the BOOT strap -- measured on the modem's
 * board 2026-10-19, where driving GPIO0 low and resetting came back into the
 * application, banner and all. */
static void bridgeBootloader(void)
{
    bridgePrintf("asking the ROM for download mode\r\n");
    if (!bridgeRelayActive)
        Serial.flush();

    pinMode(BRIDGE_BOOT_STRAP, OUTPUT);
    digitalWrite(BRIDGE_BOOT_STRAP, LOW);

#if defined(CONFIG_IDF_TARGET_ESP32S2) || defined(CONFIG_IDF_TARGET_ESP32S3) || \
    defined(CONFIG_IDF_TARGET_ESP32C3)
    SET_PERI_REG_MASK(RTC_CNTL_OPTION1_REG, RTC_CNTL_FORCE_DOWNLOAD_BOOT);
    delay(50);
    esp_restart();
#else
    bridgePrintf("GPIO%d is held LOW.  This part has no RTC force-download bit, so the\r\n"
                 "reset has to be a hardware one: pulse EN/RST -- or let esptool do it,\r\n"
                 "which a CP2102 board allows, because it has the DTR/RTS an auto-reset\r\n"
                 "circuit needs.  Nothing was reset by this command.\r\n",
                 BRIDGE_BOOT_STRAP);
#endif
}

/* ------------------------------------------------------------------ dispatch --- */

static void bridgeRun(char *line)
{
    char *cmd = line;
    char *arg = NULL;

    while (*cmd == ' ' || *cmd == '\t')
        cmd++;

    /* Split the argument off FIRST, then fold the case of the command word only --
     * the command should not fail on shift, but a wifi password must arrive exactly
     * as typed.  Same split as the modem's console, for the same measured reason. */
    for (char *p = cmd; *p != '\0'; p++) {
        if (*p == ' ' || *p == '\t') {
            *p  = '\0';
            arg = p + 1;
            while (*arg == ' ' || *arg == '\t')
                arg++;
            if (*arg == '\0')
                arg = NULL;
            break;
        }
    }

    for (char *p = cmd; *p != '\0'; p++)
        *p = (char)tolower((unsigned char)*p);

    if (*cmd == '\0')
        return;
    else if (!strcmp(cmd, "status"))
        bridgeStatus();
    else if (!strcmp(cmd, "relay"))
        bridgeRelayCommand(arg);
    else if (!strcmp(cmd, "rate"))
        bridgeRateCommand(arg);
    else if (!strcmp(cmd, "send"))
        bridgeSend(arg);
    else if (!strcmp(cmd, "pace"))
        bridgePaceCommand(arg);
    else if (!strcmp(cmd, "trace"))
        bridgeTraceCommand(arg);
    else if (!strcmp(cmd, "wifi"))
        bridgeWifiCommand(arg);
    else if (!strcmp(cmd, "reboot"))
        bridgeReboot();
    else if (!strcmp(cmd, "bootloader"))
        bridgeBootloader();
    else if (!strcmp(cmd, "help") || !strcmp(cmd, "?"))
        bridgeHelp();
    else
        bridgePrintf("unknown command: %s -- try help\r\n", cmd);
}

/* ---------------------------------------------------------------- the network -- */

static void bridgeNetPoll(void)
{
    bool up = (WiFi.status() == WL_CONNECTED);

    if (up && !bridgeWifiUp) {
        bridgeWifiUp = true;
        bridgeRelayServer.begin();   bridgeRelayServer.setNoDelay(true);
        bridgeTraceServer.begin();   bridgeTraceServer.setNoDelay(true);
        bridgeConsoleServer.begin(); bridgeConsoleServer.setNoDelay(true);
        bridgePrintf("-- wifi up: %s at %s.  relay :%d, trace :%d, console :%d\r\n",
                     bridgeSsid, WiFi.localIP().toString().c_str(),
                     BRIDGE_RELAY_PORT, BRIDGE_TRACE_PORT, BRIDGE_CONSOLE_PORT);
        bridgePrompt();
    } else if (!up && bridgeWifiUp) {
        bridgeWifiUp = false;
        bridgeRelayClient.stop();
        bridgeConsoleClient.stop();
        bridgeTraceClient.stop();
        bridgePrintf("-- wifi down.  The USB relay and this console are unaffected\r\n");
        bridgePrompt();
    }

    if (!up) {
        /* A saved network is retried on a timer rather than in a loop: the USB door
         * is the one that always works, and it must not be held up by a network that
         * is not there. */
        if (bridgeSsid[0] && (int32_t)(millis() - bridgeWifiRetryAt) >= 0) {
            bridgeWifiRetryAt = millis() + 30000;
            bridgeWifiJoin(bridgeSsid, bridgePass, 5);
        }
        return;
    }

    if (!bridgeRelayClient) {
        WiFiClient c = bridgeRelayServer.available();
        if (c) {
            c.setNoDelay(true);
            bridgeRelayClient = c;
            bridgePrintf("-- tcp relay attached from %s\r\n",
                         c.remoteIP().toString().c_str());
        }
    }
    if (!bridgeConsoleClient) {
        WiFiClient c = bridgeConsoleServer.available();
        if (c) {
            c.setNoDelay(true);
            bridgeConsoleClient = c;
            bridgeConsoleClient.print("\r\nbench-bridge console, over TCP\r\n");
            bridgePrompt();
        }
    }
    if (!bridgeTraceClient) {
        WiFiClient c = bridgeTraceServer.available();
        if (c) {
            c.setNoDelay(true);
            bridgeTraceClient = c;
            bridgeTraceHeader();
        }
    }

    if (bridgeRelayClient && !bridgeRelayClient.connected()) {
        bridgeRelayClient.stop();
        bridgePrintf("-- tcp relay detached\r\n");
    }
    if (bridgeConsoleClient && !bridgeConsoleClient.connected())
        bridgeConsoleClient.stop();
    if (bridgeTraceClient && !bridgeTraceClient.connected())
        bridgeTraceClient.stop();
}

/* --------------------------------------------------------------- setup, loop --- */

void setup()
{
    /* The RX buffers are set BEFORE begin(), which is the only order the core
     * honours -- and the machine-side one is the bigger of the two, because that is
     * where a burst arrives while the host is being slow. */
    Serial.setRxBufferSize(512);
    Serial.begin(BRIDGE_HOST_BAUD);

    Serial1.setRxBufferSize(2048);
    Serial1.begin(bridgeRate, SERIAL_8N1, BRIDGE_RXD, BRIDGE_TXD);

    delay(50);                     /* the UART settles before the first line */

    bridgePrintf("\r\nbench-bridge -- the o1next bench rig (#342, part of #334)\r\n");
    bridgePrintf("host door     UART0 at %d bps\r\n", BRIDGE_HOST_BAUD);
    bridgePrintf("machine door  UART1: RXD %d, TXD %d, %lu bps\r\n",
                 BRIDGE_RXD, BRIDGE_TXD, (unsigned long)bridgeRate);
    bridgePrintf("type help for the commands\r\n");
    bridgePrompt();

    bridgeWifiLoad();
    if (bridgeSsid[0]) {
        bridgePrintf("wifi: joining %s ...\r\n", bridgeSsid);
        if (bridgeWifiJoin(bridgeSsid, bridgePass, 15))
            bridgePrintf("wifi: up -- the TCP doors are about to open\r\n");
        else
            bridgePrintf("wifi: not up in 15 s.  The TCP doors stay closed; the USB "
                         "relay does not\r\n");
        bridgePrompt();
    }
}

void loop()
{
    bridgeNetPoll();
    bridgeHostPump();
    bridgeUartPump();
    bridgeTraceFlush();
    bridgeEscapeTimeout();
}
