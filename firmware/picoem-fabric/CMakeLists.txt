# firmware/picoem-fabric -- the interposer's shift fabric, driven (#304, part of #192).
#
# A Pico SDK project, built exactly like `firmware/picoem-smoke/`: the *same* board
# header (one board, one header), the same three bootrom switches, and the same reasons.
# `firmware/picoem-smoke/CMakeLists.txt` carries the long version of each and this file
# deliberately does not repeat it:
#
#   PICO_RUNTIME_SKIP_INIT_BOOTROM_RESET / _PER_CORE_BOOTROM_RESET /
#   _BOOTROM_LOCKING_ENABLE  -- the mask ROM's boot path does not complete in picoem, and
#                               the bridge starts the core at the image's own vector
#                               table instead (tools/picoem-bridge/src/chip.rs).
#   no stdio                 -- UART and USB are stubs in picoem.
#
# The GPIO coprocessor and the alarm pool are *not* switched off: the picoem bugs that
# needed those switches are fixed (tools/emulator-setup/picoem/), so this firmware uses
# the fast path the interposer will ship.

cmake_minimum_required(VERSION 3.13)

if (NOT PICO_SDK_PATH AND DEFINED ENV{PICO_SDK_PATH})
    set(PICO_SDK_PATH "$ENV{PICO_SDK_PATH}")
endif()
if (NOT PICO_SDK_PATH)
    message(FATAL_ERROR
        "PICO_SDK_PATH is not set.\n"
        "  Set it in the environment, or pass -DPICO_SDK_PATH=<path>.\n"
        "  See REQUIREMENTS.md; firmware/picoem-smoke/build.sh does the discovery.")
endif()

# The board header is the smoke firmware's: one board, one header, and a second copy
# would be a second thing to keep in step.
set(PICO_BOARD_HEADER_DIRS "${CMAKE_CURRENT_LIST_DIR}/../picoem-smoke/board"
    CACHE STRING "board header directories" FORCE)
set(PICO_BOARD o1next_interposer CACHE STRING "board" FORCE)

include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(picoem-fabric C CXX ASM)

pico_sdk_init()

add_executable(picoem-fabric fabric.c)
target_link_libraries(picoem-fabric pico_stdlib)

target_compile_definitions(picoem-fabric PRIVATE
    PICO_RUNTIME_SKIP_INIT_BOOTROM_RESET=1
    PICO_RUNTIME_SKIP_INIT_PER_CORE_BOOTROM_RESET=1
    PICO_RUNTIME_SKIP_INIT_BOOTROM_LOCKING_ENABLE=1)

pico_enable_stdio_uart(picoem-fabric 0)
pico_enable_stdio_usb(picoem-fabric 0)

pico_add_extra_outputs(picoem-fabric)
