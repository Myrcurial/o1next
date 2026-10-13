#!/bin/sh
# schematic_render.sh - render sheets, or a zoomed region of one sheet, from a
# scanned schematic PDF.
#
# The archive schematics are 600 dpi bilevel scans.  A whole sheet scaled to fit
# a screen is unreadable, and the PDF's own text layer is a 1990s OCR pass full
# of garbage ("J'U~ I 'IIS IO/OO-tOOnl"), so read them the way a person reads
# paper: one region at a time, at native resolution.
#
#   tools/schematic_render.sh PDF --info [--dpi D]
#       Print the page count and each sheet's size in pixels at D dpi, so you
#       know what coordinates to crop.
#
#   tools/schematic_render.sh PDF OUTDIR [--sheet N] [--dpi D] [--crop X Y W H]
#       Render to OUTDIR/sheet-NN.png.  --sheet picks one page; --crop pulls a
#       region (X Y W H in pixels at D dpi, origin top-left).
#
# Examples:
#   # all 12 sheets at 300 dpi
#   tools/schematic_render.sh research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf /tmp/sheets
#   # sheet 12 (DISC CONTROLLER) at native 600 dpi
#   tools/schematic_render.sh research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf /tmp/s --sheet 12 --dpi 600
#   # zoom the Z80 symbol on sheet 6
#   tools/schematic_render.sh research/osborne1/OCC1_1A2011-00_Schem_RevE.pdf /tmp/s --sheet 6 --dpi 600 --crop 2600 1250 1450 1050
#
# Requires poppler (pdftoppm, pdfinfo) - macOS: brew install poppler.
# See docs/o1-mainboard-schematic.md for the sheet index and the regions that
# were read this way.
set -eu

usage() {
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-1}"
}

[ $# -ge 1 ] || usage
PDF="$1"; shift

DPI=300
SHEET=""
CROP=""
OUTDIR=""
INFO=no

while [ $# -gt 0 ]; do
    case "$1" in
        --info)  INFO=yes; shift ;;
        --dpi)   DPI="$2"; shift 2 ;;
        --sheet) SHEET="$2"; shift 2 ;;
        --crop)  [ $# -ge 5 ] || { echo "--crop needs X Y W H" >&2; exit 1; }
                 CROP="-x $2 -y $3 -W $4 -H $5"; shift 5 ;;
        -h|--help) usage 0 ;;
        -*)      echo "unknown option: $1" >&2; usage ;;
        *)       OUTDIR="$1"; shift ;;
    esac
done

[ -f "$PDF" ] || { echo "no such file: $PDF" >&2; exit 1; }

if [ "$INFO" = yes ]; then
    pdfinfo "$PDF" | awk -v dpi="$DPI" '
        /^Pages:/     { print "pages: " $2 }
        /^Page size:/ { w = $3; h = $5
                        printf "sheet size: %d x %d px at %s dpi (%.2f x %.2f pt)\n",
                               int(w / 72 * dpi + 0.5), int(h / 72 * dpi + 0.5), dpi, w, h }
    '
    echo "crop coordinates are in px at the --dpi you render with; use"
    echo "--info --dpi N to match."
    exit 0
fi

[ -n "$OUTDIR" ] || { echo "need an output directory (or --info)" >&2; usage; }
mkdir -p "$OUTDIR"

# pdftoppm zero-pads its suffix to the page count, so a --sheet render of a
# 12-page PDF lands as sheet-12.png, same as a full run would.
set -- -r "$DPI" -gray -png
[ -n "$SHEET" ] && set -- "$@" -f "$SHEET" -l "$SHEET"
# CROP is "X Y W H" and each is a separate argument, so the split is deliberate.
# shellcheck disable=SC2086
[ -n "$CROP" ] && set -- "$@" $CROP
pdftoppm "$@" "$PDF" "$OUTDIR/sheet"

for f in "$OUTDIR"/sheet-*.png; do
    [ -e "$f" ] || { echo "nothing rendered" >&2; exit 1; }
    echo "$f"
done
