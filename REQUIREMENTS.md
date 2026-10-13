# Requirements — what has to be on the machine

The host tooling this repository needs, what needs it, and how to install it.
`tools/` is **Python stdlib only**, so almost everything here is *build-time* or
*verification* tooling rather than a runtime dependency of the shipped pipeline.

Two rules this file serves:

- **A missing tool is a question, not an obstacle course.** Ask for it —
  `brew install …`, `pip3 install …` — rather than hand-rolling a replacement.
  AGENTS.md has the worked examples, including the hour that went into a
  hand-written BMP reader and PNG writer because ImageMagick was never asked for.
- **Host tooling is exempt from the stdlib-only rule.** That rule is about what
  `tools/` *ships*; it says nothing about what the machine has.

Add a row here in the same PR that installs something new.

**The list is executable.** `tools/bootstrap.sh --check` probes every row below
and reports `ok` / `MISSING` / `DEAD`, exiting non-zero if anything is short;
`tools/bootstrap.sh` installs what is missing.  That is the answer to "is this
machine set up?" — there is more than one machine, and prose describing one of
them goes stale on every other one.

## Required

| Tool | Install | Needed by |
|---|---|---|
| `git` | Xcode CLT (system) | everything; commits must be GPG-signed (AGENTS.md) |
| `gh` | `brew install gh` | issues, PRs, merges — GitHub only |
| `gpg`, `pinentry-mac` | `brew install gnupg pinentry-mac` | commit signing; the keyring work is #160 |
| `python3` | Xcode CLT (system) | every tool in `tools/` — **stdlib only**, no pip deps |
| `pandoc` | `brew install pandoc` | `tools/build_book.py` |
| `typst` | `brew install typst` | `tools/build_book.py`, the PDF — `tectonic` or a LaTeX also work, and without any of them the pages are still written |
| `fonttools` + `brotli` | `tools/bootstrap.sh` — the repo `.venv` | `tools/romfont.py` (build-time; CI installs both) |
| KiCad ≥ 7 (`kicad-cli`) | KiCad app | `tools/check_schematics.py` |
| poppler | `brew install poppler` | `schematic_render.sh`, `schematic_atlas.sh`, `ocr_pdf.sh` — `pdftoppm`, `pdfinfo`, `pdfimages`, `pdftotext` |
| `tesseract` | `brew install tesseract` | `tools/ocr_pdf.sh` |
| `mame` | `brew install mame` | `tools/check_o1_map.sh`, `tools/research/*.lua`; the ROMs are in-repo (`tools/emulator-setup/roms/`) |
| `cpmtools` + `libdsk` | `brew install cpmtools` | `cpmls`/`cpmcp`/`mkfs.cpm`; the Drive C blob round trip |
| `z80dasm` | `brew install z80dasm` | the disassemblies under `research/*/disasm/` |
| `z80asm` | `brew install z80asm` | **writing** ROM code — a `HCBOOT` body, a ROM 2.0 build (#83). Installed 2026-10-13. **It does not assemble `rom144.asm` as it stands**: that source uses the Osborne/ACT assembler's own syntax — equates written `NAME = expr`, and the macros `LK`, `STO`, `LDK`, `JZ`, `JRZ`, `CMP`, `MSG`, `ECHO`, `DC`, `PROC` plus the `*SET`/`*[n]` directives. Measured, `z80asm -o out.bin rom144.asm` stops on the first equate and writes a **0-byte** output. **Corrected 2026-10-13: that makes `z80asm` the wrong tool for the ROM source — it is not a blocker on it.** `rom144.asm` is an ACT job, and the vendor's own assembler is in the local archive (`ACT80.COM`, SORCIM 3.0 and 3.2), so there is nothing to port and nothing to hunt for; the reassembly is tracked on #203 and in `docs/o1-rom-source.md`. `z80asm` stays what it is: the tool for **writing** new code, which is what #83's `HCBOOT` body and a ROM 2.0 build need. |
| **SORCIM ACT 3.5E** (`ACT80.COM` ver 3.5E) | **not obtained — ask** | the ROM 1.3 build (#205). The 1.3 source (`research/source-code/ROM-13-source/`) uses the `DBE`/`DCE` pseudo-ops, which **only 3.5E has**: every `ACT80.COM` in the local archive is 3.0 or 3.2 (nine copies, plus the schorn.ch `act.dsk` = 3.2 and ACT II 8086 3.4), none carries `DBE`/`DCE` in its mnemonic table, and the rev-B listing on `OCCROM.IMD` names the version it was built with (`SORCIM 808x Assembler ver  3.5E`). The bytes those pseudo-ops emit are recovered and `tools/research/actdbe.py` rewrites them into `DB` so 3.0 can assemble the same bytes, but the resulting image is **not certified** — the rev-B control build does not reproduce the shipped `OCCROM0B.COM` byte for byte. With 3.5E the translation is unnecessary and the question disappears. See `docs/rom-13-reconstruction.md`. |
| `shellcheck` | `brew install shellcheck` | every shell script in `tools/`, `tools/research/`, `tools/emulator-setup/` and `firmware/` — the shell half of the pipeline, held to the same bar as the Python half. `shellcheck -S warning tools/*.sh tools/research/*.sh tools/emulator-setup/mame-osborne1ng/apply.sh firmware/rom-ident/run_tests.sh firmware/acb4000-scsi/run_tests.sh` is the invocation; the few sites where word splitting is deliberate carry a `# shellcheck disable=` with the reason |
| `pkg-config` | `brew install pkg-config` | the MAME **source** build's SDL OSD — it is how MAME finds `sdl3` (`/opt/homebrew/lib/pkgconfig/sdl3.pc`). Without it the build cannot find `<SDL3/SDL.h>` and the only OSD left is `OSD=mac`, which creates a window whatever `-video` says (`docs/mame-emulation.md` §6) |
| `disk-analyse` | Disk-Utilities, built from source | IMD ↔ raw, IMD ↔ HFE |
| `unar` | `brew install unar` | the FOG library pipeline (`tools/research/fog_*.py`, #207). It is the only available reader that handles **both** layers of that archive — ARC *and* the CP/M LBR container — and it handles ARC method 8 (crunched, dynamic LZW). Two cautions, both measured: its ARC **recogniser** rejects an archive whose compressed size exceeds its uncompressed size, which 10 of the 219 FOG archives legitimately do by as little as 32 bytes (`fog_extract.py` raises the field in a throwaway copy and verifies with the ARC's own CRC-16 instead); and it writes `NAME 2` rather than overwriting on a name collision **even with `-f`**, so any driver of it must clear its output directory first |
| `lbrate` | built from source — ibiblio, `utils/compress/lbrate-1.1.tar.gz` | the **second decompressor**, for validation rather than extraction (#207). It is the only non-CP/M program that decompresses all three CP/M member schemes (Q, Z, Y). It recovered `FOG105/TYPELZ13.Z80` cleanly where unar's LZW decoder produced a bad checksum, which is how the two unrecoverable members were told apart from the one tool bug. **Not in Homebrew.** |
| `node` + `npm` | `brew install node` | `tools/render_mermaid.py` — mermaid-cli is a Node package, so this is the site's build-time toolchain, not a runtime one |
| `mermaid-cli` (`mmdc`) | `npm install @mermaid-js/mermaid-cli` | `tools/render_mermaid.py` — renders `site/assets/diagrams/*.mmd` to the PNGs the posts embed. A Mermaid code fence in a post does **not** render (see the note below) |
| **Google Chrome** | the app — `/Applications/Google Chrome.app` | puppeteer's driver for `mmdc`; `CHROME_PATH` overrides. `mmdc`'s own browser is not downloaded here |
| the diagram face | `cp site/assets/fonts/osborne1-80.ttf ~/Library/Fonts/` | `tools/render_mermaid.py` — the diagrams are set in the machine's own character generator, and Chrome has to be able to see the face **by family name**. User-scoped and reversible |
| `ghostscript` (`gs`) | `brew install ghostscript` | no repo script calls it; PDF inspection and rasterising |

### Notes that have bitten us

- **`cpmtools` needs `-T raw`.** libdsk 1.4.2's IMD driver aborts autodetection
  on a raw CP/M image, so `cpmls`/`cpmcp` fail with a bogus *"No such file or
  directory"* on a file that is plainly there. `-T raw` names the driver the
  probe was supposed to pick. Fixed in libdsk 1.5.x; Homebrew still ships 1.4.2.
  Full story in `tools/README.md` and #157.
- **A Mermaid code fence in a post does not render, and it fails silently.** Mermaid's
  `startOnLoad` looks for elements with class `mermaid`; kramdown turns a
  ```` ```mermaid ```` fence into `<pre><code class="language-mermaid">`, which it never
  matches. So the page ships the diagram as a code block and *looks* like a rendering
  problem rather than a wiring one. Two consequences, both learned the hard way:
  - **`tools/render_mermaid.py` is how a diagram gets onto a page**, rendering
    `site/assets/diagrams/*.mmd` to PNGs the post embeds. That is also what keeps the
    page no-script, and it survives RSS and printing.
  - **The compendium chapter pages keep their fences** (they are generated, so they
    cannot be hand-edited) and rely on the shim in `_layouts/default.html`, which
    rewrites the fences into the elements Mermaid wants. The shim is unverified
    locally — see below.
- **`mmdc` needs `-p` pointing at a real Chrome, or the diagrams come out in the
  wrong face.** Without a puppeteer config, `mmdc` takes a path where the embedded
  `@font-face` is not applied and every glyph renders in a serif fallback — while
  looking perfectly fine otherwise. And with the face not *installed*, Chrome
  half-loads it and draws tofu boxes with the right metrics. `render_mermaid.py`
  checks both and refuses to render rather than producing either.
- **`kicad-cli` is not on `PATH` here.** It lives inside the app bundle
  (`/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`).
  `check_schematics.py` finds it; `KICAD_CLI` or `--kicad-cli` overrides.
- **`typst` and `tectonic` are alternatives, not both needed.** Whichever is
  present lets `build_book.py` write the PDF — and the committed PDF is **not**
  covered by `--check`, so it has to be regenerated by hand when `docs/` changes
  (`site/README.md`).

## Built from source (not in Homebrew)

| Tool | Used by | Notes |
|---|---|---|
| **MAME source tree** | `tools/emulator-setup/mame-osborne1ng/apply.sh` — the `osborne1ng` machine (#191) | `brew install mame` gives a *binary*; a machine that is not upstream needs a source tree to patch and rebuild. GNU make, a C++20 compiler (Xcode CLT) and **`pkg-config`** (so the tree's default SDL3 OSD can be found) are all it wants. The OSD is left at the tree's default — `sdl3` on macOS — so the repo's documented headless recipe applies unchanged. |
| **`chdman`** | the same MAME source tree — *not* a separate install | the drive image the `osborne1ng` card talks to (`-hard /tmp/md10/hd.chd`, #191). `make SUBTARGET=chdman` does not work (there is no `scripts/target/mame/chdman.lua`); the tools are generated with **`TOOLS=1`** and then built on their own: `make OSD=mac TOOLS=1 SOURCES=src/mame/osborne SUBTARGET=osborne1ng` (generates `chdman.make`), then `make -C build/projects/mac/mameosborne1ng/gmake-osx-clang -j18 config=release64 chdman`. `brew install mame` also provides a `chdman` if the tree is not to hand. |
| **SAMdisk 4** (Simon Owen) | `tools/extract_all.sh` — the TD0 → EDSK leg | cmake on macOS; decodes TeleDisk including advanced compression. **Not installed by `bootstrap.sh`** — the archive is already extracted, so this only matters if the pipeline has to be re-run. `brew install cmake`, then build from source. |
| **disk-analyse** (Keir Fraser, Disk-Utilities) | IMD ↔ raw, IMD ↔ HFE | built from source, not in Homebrew; `bootstrap.sh` checks for it but cannot install it |

## macOS built-ins the tools rely on

No install needed: `sips` and `qlmanage` (`tools/o1art.py`), plus `dd`, `cmp`,
`shasum`, `file`, `jq`.

## Deliberately not needed

- **ImageMagick** — nothing in the repo calls it, and `o1art.py` uses `sips` and
  `qlmanage` instead. Its absence is what produced the hand-written BMP/PNG code
  AGENTS.md records.
- **Node / npm** — the grep hits are the word "node" in `check_schematics.py`'s
  tree walker, not the runtime.
- **Homebrew's `fonttools` formula** — it looks like the fix for the row above,
  and it is not. It is a `Language::Python::Virtualenv` formula, so it installs
  into its own `libexec/venv` behind `ttx`/`pyftsubset` wrappers and `import
  fontTools` still fails — against a *different* Python than the one `python3`
  resolves to. The repo `.venv` is the portable answer.

## Not installed yet (tracked)

- **Ruby + Jekyll** for `site/` — **#106**. macOS's `/usr/bin/ruby` is too old
  for current Jekyll, and `site/` has no `Gemfile` yet, so that issue is partly
  *writing* the manifest rather than only resolving it.

## Bringing a machine up

There is more than one machine, so this file describes the *requirement* rather
than a particular host — the §Required table above is the whole of it, and
`tools/bootstrap.sh` is that table, executable.

```sh
tools/bootstrap.sh --check     # report every row: ok / MISSING / DEAD
tools/bootstrap.sh             # install what is missing (Homebrew + repo .venv)
tools/bootstrap.sh --all       # ...then clear the dead /usr/local relics (sudo)
tools/bootstrap.sh --dry-run   # print the plan, change nothing
```

`--check` exits non-zero when anything is short, so it is also the first thing to
run when a build misbehaves on a host you have not used before.

Two steps it deliberately leaves to a person, because both need something the
script cannot supply:

1. **`--legacy` needs `sudo`** — the relics it removes are root-owned, and it
   removes only paths it names, skipping anything native or under the Homebrew
   prefix. Without a terminal it prints the exact `rm` block rather than hanging
   on a password prompt.
2. **The first signed commit needs a passphrase.** `pinentry-mac` can keep it in
   the login keychain, in which case that is a one-time dialog.

**`DEAD` is the state to watch for.** `command -v gs` is happy to return a 2013
Intel binary on a host with no Rosetta: it looks installed, it is not, and it
fails only when something calls it (`Bad CPU type in executable`). Telling those
two states apart is the whole reason the check is a script and not a loop over
`command -v`.

## Checking it

```sh
tools/bootstrap.sh --check
```
