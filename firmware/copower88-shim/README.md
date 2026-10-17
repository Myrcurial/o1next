# copower88-shim — virtual CoPower-88, 8088 emulation (RP2354B)

Virtual CoPower-88: an 8088 emulation shim plus the host↔CPU mailbox
protocol, so original SWP software (CP/M-86 / MS-DOS) runs on machines
without the rare physical board. The hardest interposer personality —
sequence **last**, after the bus engine and simpler personalities are
proven.

Tracks: #23; protocol work in #3–#5 (`docs/copower88-protocol.md`,
`docs/copower88-schematics.md`); driver side is
`software/copower88-driver/` (#26).

## Definition

- Software 8088 core on RP2354B (interpreted; investigate existing
  embeddable 8086 cores before writing one).
- Mailbox/doorbell interface per the Kaypro↔Zorba driver-diff
  inference (#36); monitor ROM dump deferred (#46, research-gaps #4) —
  build against the inferred protocol, revisit doorbell/IRQ semantics
  only if a dump ever happens.
- RAM for the virtual 8088 from RP2354B SRAM (+PSRAM if needed).
- Target acceptance: boot Kaypro CoPower-88 CP/M and MS-DOS images
  (`research/copower88/kaypro/`) via the Osborne driver.

## Risks

- 8088 emulation throughput vs. RP2354B budget — prototype the core
  standalone first.
- Protocol ambiguity without the monitor ROM dump.

## Deliverables

- 8088 core + mailbox personality
- Conformance notes vs. Kaypro/Zorba behavior
