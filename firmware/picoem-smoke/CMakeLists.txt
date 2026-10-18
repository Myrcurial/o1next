# firmware/picoem-smoke -- the picoem bridge's smoke firmware (#286, part of #192).
#
# A Pico SDK project, so it is built the way the real interposer firmware will
# be.  PICO_SDK_PATH comes from the environment or from -DPICO_SDK_PATH=...
# (firmware/picoem-smoke/build.sh does that for you).
#
# The board is our own: the bare RP2354B, not a module.  See board/.
#
# UART, SPI, I2C, DMA and timers are STUBS in picoem, so no stdio driver may be
# registered -- stdio_init_all() would poke a peripheral that is not there.
# pico_enable_stdio_uart/usb(TARGET 0) is the SDK's own way of saying that.

cmake_minimum_required(VERSION 3.13)

if (NOT PICO_SDK_PATH AND DEFINED ENV{PICO_SDK_PATH})
    set(PICO_SDK_PATH "$ENV{PICO_SDK_PATH}")
endif()
if (NOT PICO_SDK_PATH)
    message(FATAL_ERROR
        "PICO_SDK_PATH is not set.\n"
        "  Set it in the environment, or pass -DPICO_SDK_PATH=<path>.\n"
        "  See REQUIREMENTS.md for the pinned SDK and how to clone it;\n"
        "  firmware/picoem-smoke/build.sh does both.")
endif()

set(PICO_BOARD_HEADER_DIRS "${CMAKE_CURRENT_LIST_DIR}/board"
    CACHE STRING "board header directories" FORCE)
set(PICO_BOARD o1next_interposer CACHE STRING "board" FORCE)

include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(picoem-smoke C CXX ASM)

pico_sdk_init()

add_executable(picoem-smoke smoke.c)
target_link_libraries(picoem-smoke pico_stdlib)

# ---------------------------------------------------------------------------
# The three bootrom dependencies in the SDK's runtime init, switched off.
#
# picoem does not complete the mask ROM's boot path at the pinned commit, so
# the bridge starts the core at the image's own reset vector instead (see
# tools/picoem-bridge/src/chip.rs for the measurement).  A firmware started that
# way never ran the bootrom, and these are the SDK's only initializers that
# need it to have run:
#
#   * runtime_init_bootrom_reset / _per_core_  -- call the ROM's `reset`
#     function (ROM code 0x5253), whose first instruction is `mrc2 p7, ...`.
#     With the coprocessors enabled that call succeeds, but the bootrom state
#     it resets was never set, so it has nothing to do here.
#   * runtime_init_bootrom_locking_enable -- polls 0x400E0828 for the bootrom's
#     boot locks and **spins forever** if the bootrom never ran.  Measured:
#     PC pinned at 0x10000e3e for 200 M instructions.
#   * runtime_init_default_alarm_pool -- claims a hardware alarm, and the claim
#     path (`hw_claim_or_assert` -> `next_striped_spin_lock_num`) uses
#     **`ldaexb`/`strexb`**.  picoem implements LDREX/STREX/LDREXB/STREXB but
#     **not the acquire/release forms**, and it *mis-decodes* `ldaexb` as a
#     load/store dual: the encoding carries `Rd = 15`, so the emulator performs
#     an `LDRD` into `{r2, pc}` and the core jumps to the halfword it read out
#     of the spinlock byte.  Measured: PC 0x1000041e -> 0x00000000, then the
#     mask ROM's vector table executed two bytes at a time until a precise
#     BusFault escalated to HardFault.  This firmware uses no alarms, so the
#     pool is switched off -- but *any* firmware that claims a hardware
#     resource (a PIO block, a DMA channel, an alarm) will hit this, and that
#     is a picoem fix, not a firmware one.
#
# The SDK provides the switches, so this is configuration rather than symbol
# overriding -- and it is honest about what it is: a firmware that does not use
# the bootrom, saying so.  Both are #286.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# The GPIO coprocessor, off.  **This is the big one.**
#
# The SDK's GPIO access goes through the chip's CP0 (GPIOC) coprocessor by
# default, and picoem's CP0 encoding table does not match SDK 2.3.1's:
#
#   the SDK emits   mcr p0, #<op>, Rt, c0, c<reg>     (hardware/gpio_coproc.h)
#                   op  0=put 1=xor 2=set 3=clr, and CRm selects the register:
#                   c0 = LO OUT, c1 = HI OUT, c4 = LO OE, c5 = HI OE
#
#   picoem reads    opc1 = the *bank* (OUT/OE/IN), and treats (CRn,CRm) as
#                   "bulk if (0,0), else the pin number (CRn<<4)|CRm"
#
# So the SDK's `gpioc_lo_oe_xor(x)` -- `mcr p0, #1, r, c0, c4` -- arrives as
# "opc1=1, pin 4, op 0", which is a *silent NOP*, and `gpioc_lo_oe_get()` reads
# the wrong register.  Measured, with this switch left at its default: the
# firmware reached its main loop and answered nothing -- `sio_oe = 0` after 40 M
# cycles, because every `gpio_set_dir` was dropped.  Only the `c0,c0` (LO OUT)
# forms work, which is why `gpio_put` half-works and `gpio_set_dir` does not.
#
# Setting this to 0 makes the SDK use the SIO registers directly, which picoem
# models exactly.  It is a workaround, and it is *not* what the interposer will
# ship: on real silicon the coprocessor path is the faster one.  The picoem fix
# is to re-derive `cp0_mcr_mrc_family`'s table from `hardware/gpio_coproc.h`.
# ---------------------------------------------------------------------------
target_compile_definitions(picoem-smoke PRIVATE
    PICO_USE_GPIO_COPROCESSOR=0
    PICO_RUNTIME_SKIP_INIT_BOOTROM_RESET=1
    PICO_RUNTIME_SKIP_INIT_PER_CORE_BOOTROM_RESET=1
    PICO_RUNTIME_SKIP_INIT_BOOTROM_LOCKING_ENABLE=1
    PICO_RUNTIME_SKIP_INIT_DEFAULT_ALARM_POOL=1
    PICO_TIME_DEFAULT_ALARM_POOL_DISABLED=1)

# No stdio: the peripherals behind it are stubs in picoem.
pico_enable_stdio_uart(picoem-smoke 0)
pico_enable_stdio_usb(picoem-smoke 0)

# .bin is the flash image picoem loads; the rest come along for free.
pico_add_extra_outputs(picoem-smoke)
