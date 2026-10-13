#!/bin/sh
# schematic_atlas.sh - build a browsable, native-resolution atlas of a scanned
# schematic PDF.
#
# Why: these scans are ~6500 x 5100 px.  A viewer that fits the whole sheet on
# screen throws away 5x of the resolution, and the sheets are dense enough that
# no amount of scrolling makes a full-page view readable.  The workable reading
# order is: look at an overview to find the block, then read that block at
# native resolution.  This tool produces both, as files you can open in any
# image viewer, plus an index that says what pixel box each tile covers - so a
# region you find once can be re-rendered later with
# `tools/schematic_render.sh PDF OUT --sheet N --dpi D --crop X Y W H`.
#
#   tools/schematic_atlas.sh PDF [OUTDIR] [options]
#
#   OUTDIR           where to write (default: build/atlas).  build/ is
#                    gitignored: the atlas is regenerable, the coordinates are
#                    the durable part.
#   --sheet N        one page only (default: all pages)
#   --dpi D          tile resolution (default: 600, the scan's native res)
#   --cols N         tile columns per sheet (default: 3)
#   --rows N         tile rows per sheet (default: 3)
#   --overlap PX     tile overlap in pixels at D (default: 140)
#
# Output layout:
#   OUTDIR/index.md          tile map: page -> tile -> pixel box
#   OUTDIR/sheet-NN/overview.png   whole sheet, small, for finding blocks
#   OUTDIR/sheet-NN/rRcC.png       tile at row R, column C, native res
#
# index.md is rewritten on every run, so a --sheet run leaves an index covering
# only that sheet.  Run without --sheet for the whole-document map.
#
# Requires poppler (pdftoppm, pdfinfo) - same dependency as
# tools/schematic_render.sh and tools/ocr_pdf.sh.
#
# See docs/o1-mainboard-schematic.md for the sheet index (which page is which
# drawing) and the regions already read this way.
set -eu

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-1}"
}

[ $# -ge 1 ] || usage
PDF="$1"; shift

OUTDIR="build/atlas"
DPI=600
COLS=3
ROWS=3
OVERLAP=140
SHEET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dpi)     DPI="$2"; shift 2 ;;
        --cols)    COLS="$2"; shift 2 ;;
        --rows)    ROWS="$2"; shift 2 ;;
        --overlap) OVERLAP="$2"; shift 2 ;;
        --sheet)   SHEET="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*)        echo "unknown option: $1" >&2; usage ;;
        *)         OUTDIR="$1"; shift ;;
    esac
done

[ -f "$PDF" ] || { echo "no such file: $PDF" >&2; exit 1; }

PAGES=$(pdfinfo "$PDF" | awk '/^Pages:/ { print $2 }')
FIRST=${SHEET:-1}
LAST=${SHEET:-$PAGES}
mkdir -p "$OUTDIR"

# Page size in points -> render size in pixels at $DPI.  Note this is the size
# pdftoppm produces, which is not always the embedded raster's size: the scan is
# placed on a fixed-size page, so a 6582 px source renders at 6543 px.  All
# coordinates in the atlas are in *rendered* pixels.
page_px() {
    pdfinfo -f "$1" -l "$1" "$PDF" |
        awk -v dpi="$DPI" '/size:/ { printf "%d %d\n", $4 / 72 * dpi + 0.5, $6 / 72 * dpi + 0.5 }'
}

# ceil(a/b) for positive integers
ceil_div() { echo $(( ($1 + $2 - 1) / $2 )); }

{
    printf '# Schematic atlas - %s\n\n' "$(basename "$PDF")"
    printf 'Tiles are %s dpi (native), %s columns x %s rows per sheet, %s px overlap.\n' \
        "$DPI" "$COLS" "$ROWS" "$OVERLAP"
    printf 'Coordinates are X Y W H in rendered pixels at %s dpi, for\n' "$DPI"
    printf '`tools/schematic_render.sh PDF OUT --sheet N --dpi %s --crop X Y W H`.\n\n' "$DPI"
    printf 'Sheet titles are in `docs/o1-mainboard-schematic.md` section 2.\n'
} > "$OUTDIR/index.md"

p=$FIRST
while [ "$p" -le "$LAST" ]; do
    dir=$(printf '%s/sheet-%02d' "$OUTDIR" "$p")
    mkdir -p "$dir"
    # page_px prints "W H" and both are wanted as separate positional parameters,
    # so the word split is deliberate.
    # shellcheck disable=SC2046
    set -- $(page_px "$p")
    W=$1; H=$2

    # Overview: whole sheet, long side 1400 px.  Enough to see the block
    # layout and read the title block, not enough to read a pin number.
    pdftoppm -r 96 -gray -png -scale-to 1400 -f "$p" -l "$p" "$PDF" "$dir/overview"
    for f in "$dir"/overview-*.png; do mv "$f" "$dir/overview.png"; done

    printf '## Sheet %s (page %s of %s)\n\n' "$p" "$p" "$PAGES" >> "$OUTDIR/index.md"
    printf '![sheet %s overview](sheet-%02d/overview.png)\n\n' "$p" "$p" >> "$OUTDIR/index.md"
    printf '| tile | file | X | Y | W | H |\n|---|---|---|---|---|---|\n' >> "$OUTDIR/index.md"

    step_x=$(ceil_div "$W" "$COLS")
    step_y=$(ceil_div "$H" "$ROWS")
    tw=$(( step_x + OVERLAP )); [ "$tw" -le "$W" ] || tw=$W
    th=$(( step_y + OVERLAP )); [ "$th" -le "$H" ] || th=$H

    r=0
    while [ "$r" -lt "$ROWS" ]; do
        c=0
        while [ "$c" -lt "$COLS" ]; do
            x=$(( c * step_x )); [ $(( x + tw )) -le "$W" ] || x=$(( W - tw ))
            y=$(( r * step_y )); [ $(( y + th )) -le "$H" ] || y=$(( H - th ))
            pdftoppm -r "$DPI" -gray -png -f "$p" -l "$p" \
                -x "$x" -y "$y" -W "$tw" -H "$th" "$PDF" "$dir/r${r}c${c}"
            for f in "$dir"/r${r}c${c}-*.png; do mv "$f" "$dir/r${r}c${c}.png"; done
            printf '| r%sc%s | [r%sc%s.png](sheet-%02d/r%sc%s.png) | %s | %s | %s | %s |\n' \
                "$r" "$c" "$r" "$c" "$p" "$r" "$c" "$x" "$y" "$tw" "$th" >> "$OUTDIR/index.md"
            c=$(( c + 1 ))
        done
        r=$(( r + 1 ))
    done
    printf '\n' >> "$OUTDIR/index.md"
    echo "sheet $p: ${W}x${H} px at ${DPI} dpi -> $dir ($((COLS * ROWS)) tiles)"
    p=$(( p + 1 ))
done

echo "wrote $OUTDIR/index.md"
