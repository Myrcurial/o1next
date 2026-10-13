#!/bin/bash
# extract_all.sh - batch-convert every research disk image and extract
# its CP/M filesystem into <dir>/extracted/.
#
# Pipeline:
#   .td0 -> SAMdisk -> .dsk (EDSK) -> edsk2raw.py -> .raw -> cpmfs.py
#   .imd -> disk-analyse -> .raw (img) -> cpmfs.py
#
# Usage: tools/extract_all.sh [SAMDISK_PATH]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAMDISK="${1:-/tmp/samdisk/build/samdisk}"
WORK=$(mktemp -d)

# image_path format outdir
do_td0() {
  local src="$1" fmt="$2" out="$3"
  "$SAMDISK" copy "$src" "$WORK/t.dsk" >/dev/null 2>&1
  python3 "$ROOT/tools/edsk2raw.py" "$WORK/t.dsk" "$WORK/t.raw"
  python3 "$ROOT/tools/cpmfs.py" "$WORK/t.raw" "$fmt" getall "$out"
}
do_td0_pad() {
  local src="$1" fmt="$2" out="$3"
  "$SAMDISK" copy "$src" "$WORK/t.dsk" >/dev/null 2>&1
  python3 "$ROOT/tools/edsk2raw.py" "$WORK/t.dsk" "$WORK/t.raw" --pad 10,256
  python3 "$ROOT/tools/cpmfs.py" "$WORK/t.raw" "$fmt" getall "$out"
}
do_imd() {
  local src="$1" fmt="$2" out="$3"
  disk-analyse "$src" "$WORK/t.raw" >/dev/null 2>&1
  python3 "$ROOT/tools/cpmfs.py" "$WORK/t.raw" "$fmt" getall "$out"
}

echo "== copower88/kaypro/copwrcpm (kp2x)";  do_td0 "$ROOT/research/copower88/kaypro/copwrcpm.td0" kp2x "$ROOT/research/copower88/kaypro/extracted_cpm"
echo "== rtc RT-60A (osb1sssd)";             do_td0_pad "$ROOT/research/rtc/RT-60A.TD0" osb1sssd "$ROOT/research/rtc/extracted"
echo "== drive_c (osb1sssd)";                do_imd "$ROOT/research/drive_c/DRIVE_C.IMD" osb1sssd "$ROOT/research/drive_c/extracted"
echo "== occ1 harddisk (osb1sssd)";          do_imd "$ROOT/research/harddisk/OCC1_HARDDISK.IMD" osb1sssd "$ROOT/research/harddisk/extracted"
echo 'done'
