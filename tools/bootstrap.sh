#!/bin/bash
# bootstrap.sh — bring a host up to what REQUIREMENTS.md requires, and say
# plainly what still needs a human.
#
# This repo is worked on from more than one machine, and REQUIREMENTS.md is the
# only list of what a machine has to provide.  A machine swap used to mean
# re-deriving that list by hand, which is how a host ends up six tools short
# without anyone noticing until a build fails.  This script *is* that list,
# executable: every row of REQUIREMENTS.md §Required is probed, the missing ones
# are installed, and the leftovers that only `sudo` can clear are reported
# rather than attempted.
#
# It checks that a tool *runs*, not merely that it is on PATH.  `command -v gs`
# is happy to return a 2013 Intel binary on a host with no Rosetta — a corpse
# that looks present until something calls it.  Those are reported DEAD, which
# is the distinction that matters after a migration.
#
# Usage:
#   tools/bootstrap.sh              install what is missing (Homebrew + .venv)
#   tools/bootstrap.sh --check      report only, change nothing; exit 1 if short
#   tools/bootstrap.sh --all        install, then clear the dead /usr/local tools
#   tools/bootstrap.sh --legacy     only clear the dead /usr/local tools (sudo)
#   tools/bootstrap.sh --dry-run    say what would happen, do nothing
#   tools/bootstrap.sh --yes        never prompt — --legacy prints its rm block
#                                   instead of asking for a password
#
# Exit status: 0 — everything required is present and runnable; 1 — something
# is missing, dead, or was left for the user.
set -eo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/.venv"

MODE=install
LEGACY=no
DRY=no
YES=no

usage() {
    cat <<'USAGE'
tools/bootstrap.sh — bring a host up to what REQUIREMENTS.md requires.

  --check      report every required row as ok / MISSING / DEAD and exit
               non-zero if short.  Change nothing.  Run this on any machine.
  --install    install what is missing: Homebrew formulae, and the repo .venv
               holding fontTools + brotli.  This is the default.
  --legacy     remove the dead pre-Rosetta tools in /usr/local (needs sudo).
               Opt-in, because it needs a password; --dry-run prints the list.
  --all        --install then --legacy.
  --dry-run    print what would be done and do none of it.
  --yes        never prompt: --legacy prints its rm block instead of asking for
               a password, which is what CI and an agent need.
  -h, --help   this text.

The venv exists because Python packaging is per-machine pain: Homebrew's Python
is PEP 668 externally-managed and refuses `pip3 install fonttools brotli`
outright, so the documented one-liner stopped working the moment `python3`
became a Homebrew Python.  A venv in the repo works on any machine, for anyone.
USAGE
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)      MODE=check ;;
        --install)    MODE=install ;;
        --legacy)     MODE=legacy; LEGACY=yes ;;
        --all)        MODE=install; LEGACY=yes ;;
        --dry-run|-n) DRY=yes ;;
        --yes|-y)     YES=yes ;;
        -h|--help)    usage 0 ;;
        *) echo "bootstrap.sh: unknown option: $1" >&2; usage 2 ;;
    esac
    shift
done

say()  { printf '%s\n' "$*"; }
rule() { printf '\n== %s\n' "$*"; }

# ---------------------------------------------------------------- host ------

ARCH="$(uname -m)"
OSVER="$(sw_vers -productVersion 2>/dev/null || echo '?')"
OSBUILD="$(sw_vers -buildVersion 2>/dev/null || echo '?')"

BREW="$(command -v brew 2>/dev/null || true)"
BREW_PREFIX=""
[ -n "$BREW" ] && BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"

# Rosetta is what decides whether a carried-over Intel binary is a tool or a
# corpse.  `arch -x86_64` on a universal system binary is the honest probe:
# `sysctl.proc_translated` only describes the process asking.
HAVE_ROSETTA=no
arch -x86_64 /usr/bin/true >/dev/null 2>&1 && HAVE_ROSETTA=yes

have()     { command -v "$1" >/dev/null 2>&1; }
which_of() { command -v "$1" 2>/dev/null || true; }

# A command that resolves but cannot execute: an Intel-only Mach-O binary on a
# host with no Rosetta.  Prints the offending path if so, nothing otherwise.
unrunnable() {
    local p t
    p="$(which_of "$1")"
    [ -n "$p" ] && [ -e "$p" ] || return 1
    t="$(file -b "$p" 2>/dev/null || true)"
    case "$t" in
        *Mach-O*) ;;                 # scripts and non-Mach-O are fine
        *) return 1 ;;
    esac
    case "$t" in
        *arm64*) return 1 ;;         # has a native slice
    esac
    [ "$HAVE_ROSETTA" = yes ] && return 1
    printf '%s' "$p"
}

# -------------------------------------------------------------- results -----

MISSING_LIST=""
DEAD_LIST=""
BROKEN=0
FORMULAE=""

add_formula() { FORMULAE="$FORMULAE $*"; }

ok_row()   { printf '  %-7s %-15s %s\n' ok      "$1" "$2"; }
miss_row() { printf '  %-7s %-15s %s\n' MISSING "$1" "$2"
             MISSING_LIST="$MISSING_LIST $1"; BROKEN=1; }
dead_row() { printf '  %-7s %-15s %s\n' DEAD    "$1" "$2"
             DEAD_LIST="$DEAD_LIST $1"; BROKEN=1; }

# --------------------------------------------------------------- checks -----

check_host() {
    rule "host"
    printf '  %-7s %-15s %s\n' machine "$ARCH" "macOS $OSVER ($OSBUILD)"
    printf '  %-7s %-15s %s\n' brew "${BREW_PREFIX:-none}" \
        "$([ -n "$BREW" ] && brew --version 2>/dev/null | head -1 || echo 'not installed')"
    printf '  %-7s %-15s %s\n' rosetta "$HAVE_ROSETTA" \
        "x86_64 binaries $([ "$HAVE_ROSETTA" = yes ] && echo can || echo cannot) run here"
    printf '  %-7s %-15s %s\n' bash "$BASH_VERSION" "$(which_of bash)"
}

# Every row of REQUIREMENTS.md §Required, in that order.  A row is ok when the
# tool resolves *and* runs; DEAD when it resolves to something that cannot.
check_required() {
    local p kicad pyfonts
    local heading="${1:-required (REQUIREMENTS.md)}"

    rule "$heading"

    if have git; then
        ok_row git "$(which_of git) — $(git --version 2>/dev/null)"
    else
        miss_row git "Xcode CLT: xcode-select --install"
    fi

    if have gh; then
        ok_row gh "$(which_of gh) — $(gh --version 2>/dev/null | head -1)"
    else
        miss_row gh 'brew install gh'
        add_formula gh
    fi

    if have gpg && have pinentry-mac; then
        ok_row gpg "$(which_of gpg) + $(which_of pinentry-mac)"
    else
        miss_row gpg 'brew install gnupg pinentry-mac'
        add_formula gnupg pinentry-mac
    fi

    if have python3; then
        ok_row python3 "$(which_of python3) — $(python3 --version 2>&1)"
    else
        miss_row python3 'Xcode CLT: xcode-select --install'
    fi

    p="$(unrunnable pandoc || true)"
    if [ -n "$p" ]; then
        dead_row pandoc "$p — no arm64 slice, no Rosetta"
        add_formula pandoc
    elif have pandoc; then
        ok_row pandoc "$(which_of pandoc) — $(pandoc --version 2>/dev/null | head -1)"
    else
        miss_row pandoc 'brew install pandoc'
        add_formula pandoc
    fi

    # typst and tectonic are alternatives, not both needed.
    if have typst || have tectonic; then
        ok_row 'typst|tectonic' "$(which_of typst || which_of tectonic)"
    else
        miss_row 'typst|tectonic' 'brew install typst'
        add_formula typst
    fi

    # Homebrew's own fonttools formula does not help: it is a
    # Language::Python::Virtualenv formula, so it lands in its own libexec venv
    # and `import fontTools` still fails.  The repo venv is the answer.
    pyfonts=""
    if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import fontTools, brotli' >/dev/null 2>&1; then
        pyfonts="$VENV/bin/python"
    elif python3 -c 'import fontTools, brotli' >/dev/null 2>&1; then
        pyfonts="$(which_of python3)"
    fi
    if [ -n "$pyfonts" ]; then
        ok_row fonttools "$pyfonts — fontTools $("$pyfonts" -c 'import fontTools; print(fontTools.version)')"
    else
        miss_row fonttools '.venv (tools/bootstrap.sh) — pip install fonttools brotli'
    fi

    # kicad-cli is not on PATH: it lives inside the app bundle.
    kicad=""
    if have kicad-cli; then
        kicad="$(which_of kicad-cli)"
    else
        for p in /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli \
                 /Applications/KiCad*/KiCad.app/Contents/MacOS/kicad-cli; do
            [ -x "$p" ] && { kicad="$p"; break; }
        done
    fi
    if [ -n "$kicad" ]; then
        ok_row kicad-cli "$kicad — $("$kicad" version 2>/dev/null | head -1)"
    else
        miss_row kicad-cli 'brew install --cask kicad'
    fi

    if have pdftoppm && have pdfinfo; then
        ok_row poppler "$(which_of pdftoppm) — pdftoppm, pdfinfo, pdfimages, pdftotext"
    else
        miss_row poppler 'brew install poppler'
        add_formula poppler
    fi

    if have tesseract; then
        ok_row tesseract "$(which_of tesseract) — $(tesseract --version 2>&1 | head -1)"
    else
        miss_row tesseract 'brew install tesseract'
        add_formula tesseract
    fi

    if have mame; then
        ok_row mame "$(which_of mame) — $(mame -version 2>/dev/null | head -1)"
    else
        miss_row mame 'brew install mame'
        add_formula mame
    fi

    if have cpmls && have cpmcp && have mkfs.cpm; then
        ok_row cpmtools "$(which_of cpmls) — cpmls, cpmcp, mkfs.cpm (remember -T raw)"
    else
        miss_row cpmtools 'brew install cpmtools (pulls libdsk)'
        add_formula cpmtools
    fi

    if have z80dasm; then
        ok_row z80dasm "$(which_of z80dasm)"
    else
        miss_row z80dasm 'brew install z80dasm'
        add_formula z80dasm
    fi

    if have shellcheck; then
        ok_row shellcheck "$(which_of shellcheck) — $(shellcheck --version 2>/dev/null | awk '/version:/ {print $2}')"
    else
        miss_row shellcheck 'brew install shellcheck'
        add_formula shellcheck
    fi

    if have disk-analyse; then
        ok_row disk-analyse "$(which_of disk-analyse) — built from source, not in Homebrew"
    else
        miss_row disk-analyse 'Disk-Utilities, built from source — see REQUIREMENTS.md'
    fi

    if have unar; then
        ok_row unar "$(which_of unar) — $(unar -v 2>&1 | head -1 | cut -d, -f1)"
    else
        miss_row unar 'brew install unar'
        add_formula unar
    fi

    # lbrate is not in Homebrew, so this can only report, not install.
    if have lbrate; then
        ok_row lbrate "$(which_of lbrate) — built from source, not in Homebrew"
    else
        miss_row lbrate 'ibiblio utils/compress/lbrate-1.1.tar.gz — built from source, see REQUIREMENTS.md'
    fi

    # The corpse: a 2013 Ghostscript that `command -v gs` will hand you.
    p="$(unrunnable gs || true)"
    if [ -n "$p" ]; then
        dead_row ghostscript "$p — no arm64 slice, no Rosetta"
        add_formula ghostscript
    elif have gs; then
        ok_row ghostscript "$(which_of gs) — $("$(which_of gs)" --version 2>/dev/null | head -1)"
    else
        miss_row ghostscript 'brew install ghostscript'
        add_formula ghostscript
    fi
}

check_optional() {
    local t missing

    rule "optional (not required — see REQUIREMENTS.md)"

    if have cmake; then
        printf '  %-7s %-15s %s\n' ok cmake "$(which_of cmake) — to build SAMdisk 4"
    else
        printf '  %-7s %-15s %s\n' absent cmake 'brew install cmake — only to build SAMdisk 4'
    fi

    if have samdisk || [ -x /tmp/samdisk/build/samdisk ]; then
        printf '  %-7s %-15s %s\n' ok samdisk 'only needed to re-run the TD0 leg of extract_all.sh'
    else
        printf '  %-7s %-15s %s\n' absent samdisk 'the archive is already extracted; see REQUIREMENTS.md'
    fi

    if have jekyll; then
        printf '  %-7s %-15s %s\n' ok jekyll "$(which_of jekyll)"
    else
        printf '  %-7s %-15s %s\n' absent jekyll \
            "$(ruby --version 2>/dev/null | cut -d' ' -f1-2) is too old for Jekyll — #106; tools/site_preview.py previews without it"
    fi

    missing=""
    for t in sips qlmanage dd cmp shasum file jq; do
        have "$t" || missing="$missing $t"
    done
    if [ -z "$missing" ]; then
        printf '  %-7s %-15s %s\n' ok 'macOS built-ins' 'sips qlmanage dd cmp shasum file jq'
    else
        printf '  %-7s %-15s %s\n' warn 'macOS built-ins' "missing:$missing"
    fi
}

# The commands that answer `command -v` but fail when called.  This is the
# check that would have caught the corpse in one second instead of an hour.
check_shadows() {
    local c p found=0

    rule "in PATH but unrunnable"

    for c in gs pandoc gpg node wget git-lfs github ollama; do
        p="$(unrunnable "$c" || true)"
        if [ -n "$p" ]; then
            printf '  %-7s %-15s %s\n' DEAD "$c" "$p"
            found=1
        fi
    done

    if [ "$found" = 0 ]; then
        say "  none — everything PATH resolves has a runnable slice"
    fi
}

# -------------------------------------------------------------- actions -----

do_install() {
    rule "install"

    if [ -z "$FORMULAE" ]; then
        say "  nothing missing from Homebrew"
    elif [ -z "$BREW" ]; then
        say "  no Homebrew on this host; install it from https://brew.sh, then re-run"
    elif [ "$DRY" = yes ]; then
        say "  would run: brew install$FORMULAE"
    else
        say "  brew install$FORMULAE"
        # FORMULAE is a space-separated list, so the word splitting is the point
        # rather than an accident -- which is exactly the case SC2086 warns about
        # and cannot tell apart from a bug.
        # shellcheck disable=SC2086
        brew install $FORMULAE
    fi

    ensure_venv
}

# The venv is the answer to the Python dependency, because there is no
# per-machine one that works: Homebrew's python is PEP 668 externally-managed
# and refuses `pip3 install fonttools brotli` outright, and which interpreter
# `python3` is depends on the host.  A venv in the repo is the same on all of
# them, and it means a fresh clone works for someone who has never seen this
# machine.
ensure_venv() {
    if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import fontTools, brotli' >/dev/null 2>&1; then
        say "  venv ok: $VENV"
        return 0
    fi

    if [ "$DRY" = yes ]; then
        say "  would create $VENV and pip install fonttools brotli"
        return 0
    fi

    if ! have python3; then
        say "  cannot build $VENV: no python3"
        return 0
    fi

    say "  creating $VENV (fontTools + brotli)"
    python3 -m venv "$VENV"
    "$VENV/bin/python" -m pip install --quiet --upgrade pip
    "$VENV/bin/python" -m pip install --quiet fonttools brotli
    say "  done — run the tools as $VENV/bin/python tools/romfont.py --check"
}

# A pre-Rosetta /usr/local/bin leaves relics behind, and on a host with no
# Rosetta they are corpses rather than tools.  The list is explicit — this never
# guesses — and every path is skipped if it is native or lives under the
# Homebrew prefix, so it cannot take out a tool that works.
LEGACY_FILES="
/usr/local/bin/gs
/usr/local/bin/gs-X11
/usr/local/bin/gs-noX11
/usr/local/bin/gsbj
/usr/local/bin/gsdj
/usr/local/bin/gsdj500
/usr/local/bin/gslj
/usr/local/bin/gslp
/usr/local/bin/gsnd
/usr/local/bin/dvipdf
/usr/local/bin/eps2eps
/usr/local/bin/font2c
/usr/local/bin/pdf2dsc
/usr/local/bin/pdf2ps
/usr/local/bin/pf2afm
/usr/local/bin/pfbtopfa
/usr/local/bin/pphs
/usr/local/bin/printafm
/usr/local/bin/ps2ascii
/usr/local/bin/ps2epsi
/usr/local/bin/ps2pdf
/usr/local/bin/ps2pdf12
/usr/local/bin/ps2pdf13
/usr/local/bin/ps2pdf14
/usr/local/bin/ps2pdfwr
/usr/local/bin/ps2ps
/usr/local/bin/ps2ps2
/usr/local/bin/wftopfa
/usr/local/bin/lprsetup.sh
/usr/local/bin/unix-lpr.sh
/usr/local/bin/pandoc
/usr/local/bin/pandoc-citeproc
"
LEGACY_DIRS="
/usr/local/share/ghostscript
"

print_legacy_block() {
    local p
    printf '    sudo rm -f'
    for p in $LEGACY_FILES; do printf ' %s' "$p"; done
    printf '\n    sudo rm -rf'
    for p in $LEGACY_DIRS; do printf ' %s' "$p"; done
    printf '\n'
}

legacy_cleanup() {
    local p rc=0

    rule "legacy relics under /usr/local"

    # A password prompt needs both a terminal and a person.  Without both, print
    # the command rather than hang on a prompt nobody is there to answer.
    if [ "$DRY" != yes ] && ! sudo -n true 2>/dev/null; then
        if [ "$YES" = yes ]; then
            say "  --yes: not prompting for sudo.  Run this by hand:"
            print_legacy_block
            return 0
        fi
        if [ ! -t 0 ]; then
            say "  no terminal to prompt on.  Run this by hand:"
            print_legacy_block
            return 0
        fi
    fi

    for p in $LEGACY_FILES $LEGACY_DIRS; do
        [ -e "$p" ] || continue

        case "$p" in
            "$BREW_PREFIX"/*)
                say "  skip, under the Homebrew prefix: $p"
                continue ;;
        esac

        if [ -f "$p" ] && file -b "$p" 2>/dev/null | grep -q arm64; then
            say "  skip, native arm64: $p"
            continue
        fi

        if [ "$DRY" = yes ]; then
            say "  would remove $p"
            continue
        fi

        if sudo rm -rf "$p"; then
            say "  removed $p"
        else
            say "  FAILED to remove $p"
            rc=1
        fi
    done

    return "$rc"
}

report_leftovers() {
    local p found=0

    rule "left alone"

    for p in /usr/local/bin/brew /usr/local/Cellar /usr/local/MacGPG2; do
        if [ -e "$p" ]; then
            printf '  %s\n' "$p"
            found=1
        fi
    done

    if [ "$found" = 1 ]; then
        say "  another machine's Homebrew tree, and a 2014 GPG Suite.  Inert while"
        say "  the Homebrew prefix is first on PATH, and not a cleanup: something"
        say "  you have forgotten may live in them.  If you want them gone:"
        say "    sudo rm -rf /usr/local/Cellar /usr/local/MacGPG2 /usr/local/bin/brew"
    else
        say "  nothing"
    fi
}

summary() {
    rule "summary"

    if [ "$BROKEN" = 0 ]; then
        say "  every required tool is present and runnable"
    else
        if [ -n "$MISSING_LIST" ]; then say "  missing:$MISSING_LIST"; fi
        if [ -n "$DEAD_LIST" ]; then say "  dead (resolves, cannot run):$DEAD_LIST"; fi
        if [ -n "$FORMULAE" ]; then say "  fix: brew install$FORMULAE"; fi
    fi

    if [ "$LEGACY" != yes ] && [ -e /usr/local/bin/gs ]; then
        say "  note: the dead relics under /usr/local are still there —"
        say "        tools/bootstrap.sh --legacy   (asks for your password)"
    fi
}

# ------------------------------------------------------------------ run -----

check_host
check_required
check_optional
check_shadows

if [ "$MODE" = install ]; then
    do_install
fi

if [ "$LEGACY" = yes ]; then
    legacy_cleanup
fi

if [ "$MODE" = install ]; then
    # Re-probe, so the summary describes the host as it is now.
    MISSING_LIST=""
    DEAD_LIST=""
    FORMULAE=""
    BROKEN=0
    check_required "required — after install"
fi

report_leftovers
summary

exit "$BROKEN"
