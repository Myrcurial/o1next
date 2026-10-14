# AGENTS.md — working agreement for AI agents in this repo

This file is the authoritative operating procedure for any AI coding/research
agent working in `o1next`. Follow it over generic defaults.

## Issue tracking: GitHub ONLY

- All issues, planning, phases, and task state for this project live in
  **GitHub Issues** on `Myrcurial/o1next`. Use `gh issue list`,
  `gh issue view #N`, `gh issue create`.
- **Do NOT use the Linear MCP server for this project.** A Linear connection
  exists on this machine for unrelated work in other repos. Nothing in Linear
  refers to o1next. Never create, search, update, or reference Linear
  issues here — if the Linear MCP responds with issues about other products,
  that is expected; ignore it entirely.
- Same for PRs: GitHub only, via `gh pr ...`.

## Git workflow

1. **Branch from `main`** for every unit of work. Branch names are
   `<area>/<slug>`, where area matches the work type:
   `feature/`, `research/`, `docs/`, `tools/`.
   (e.g. `research/o1-memory-io-map`, `docs/research-archive-readme-video`)
2. **Commit frequently** — small, self-contained commits that each compile
   into a coherent state. Don't hold a day's work uncommitted.
3. **Every commit must be GPG-signed.** `commit.gpgsign=true` and
   `user.signingkey=A69B4405637BD55D` come from the **global** `~/.gitconfig`;
   the repo sets neither. `A69B4405637BD55D` is the signing subkey of primary
   `9AA02DEEAFA4F425`.
   - If signing fails (key locked, agent can't reach pinentry, etc.),
     **stop and tell the user** — never bypass with `--no-gpg-sign` or by
     flipping the config.
   - Verify with `git log --format='%h %G? %s'`. **Authored commits show `G`.**
     `E` is *a signature that cannot be checked here* — GitHub-created merges
     (the `web-flow` key is not imported) and commits from a session whose key is
     not in this keyring. `N` is unsigned; `B` is a bad signature. `E` is not a
     signing failure, and it is not a reason to stop: **#160** is the keyring work
     that turns those into `G`.
4. **Commit message format:** `<area>: <imperative summary> (#issue)`
   - Areas in use: `docs:`, `research:`, `tools:` (plus merge commits).
   - Reference the driving issue in every commit: `(#9)`,
     `(#3 #4, part of #5)`.
   - `closes #N` only when the commit/PR fully completes the issue;
     `part of #N` for partial progress. Never claim `closes` prematurely —
     issue #40 sat open while its "closes #40" commit was stranded on an
     unmerged branch.
   - **And the keyword fires wherever it appears, including inside a sentence
     that denies it.** GitHub's closing keywords are `close`/`closes`/`closed`,
     `fix`/`fixes`/`fixed` and `resolve`/`resolves`/`resolved`, and a PR body
     reading *"**This does not close #179**"* **closes #179** on merge. That is
     not hypothetical: it happened on 2026-10-13 and #179 had to be reopened.
     If you need to say an issue is *not* finished, say `part of #N` and stop —
     do not use the closing verb at all, not even to negate it.
5. **Push the branch, then open a PR** (`gh pr create`) with a title
   mirroring the commit message and a body linking the issues.
6. **Merge through the GitHub PR**, not local merges pushed to `main`. A merge
   commit created locally bypasses the PR's own record and its issue auto-close,
   and the history shows it: **16 merges into `main` were made that way on
   2026-10-09**, six of them bare `Merge feature/X` with no PR reference at all.
   Nothing since 2026-10-10 11:32 has been. Prefer `gh pr merge` or the web
   button; delete the local branch after merge.
   - **Stacked PRs: retarget before you delete.** If PR *B* is based on branch
     *A*, merging *A* with `--delete-branch` **auto-closes *B*** — GitHub deletes
     *B*'s base out from under it. Merge *A* without deleting, retarget *B* at
     `main`, then delete *A*'s branch. The other order means recreating the
     deleted base branch by hand.
7. Never commit directly to `main`; never force-push `main`.

## Concurrent sessions — more than one agent in this repo

More than one Cline session is run against this repository at the same time, on
purpose, so that one long wait does not idle the project. The rule that makes that
safe is **one worktree per session**. The shared working tree is the first hazard;
the second is any sync client that touches `.git`.

### The repository is outside iCloud — moved there 2026-10-14

The clone lives at **`~/GitHub/o1next`**, which is outside `~/Documents` and
therefore outside iCloud Drive's scope. It was `~/Documents/GitHub/o1nextgen`
until 2026-10-14, and **that move is the fix for the whole problem below** — so
the history is kept, because this section got the diagnosis wrong twice and the
next agent will reach for the same evidence. The directory itself was renamed
`o1nextgen` → `o1next` on the same day, in step 5 of #228, so the two names above
are now only the before and after of one move.

1. **The symlink is the mechanism, not the counter-evidence.**
   `~/Library/Mobile Documents/com~apple~CloudDocs/Documents` is a symlink to
   `/Volumes/4TB/Users/jarlen/Documents`, and that was read as proof the repo was
   *not* synced. It is the opposite: it is macOS's own Desktop & Documents
   redirection, and therefore the mechanism *of* sync. Both machines keep Desktop
   & Documents in iCloud on one account, so `~/Documents/GitHub/` was the same
   synced folder served from two local paths.
2. **No `.icloud` placeholders means nothing was *evicted*.** It says nothing
   about whether anything was *synced*.

**Why out is the right place.** iCloud is a *file provider*, not a filesystem: it
can evict a file to a dataless placeholder and re-materialize it later, it does
not understand `.git`, and when two writers disagree it resolves the difference by
leaving a conflict copy rather than by refusing. `.git/index.lock` is not a lock
across two machines. One `mv` ends all of it:

- no eviction, no conflict copies, no sync client writing under `.git`;
- **no sync cost** — a worktree was ~213 MB of iCloud upload each, and `research/`
  alone is 194 MB of it (`.git` is 701 MB and is *shared* between worktrees, so
  worktrees never duplicated it);
- **the two machines stop sharing one `.git`**, which was the sharpest edge here.

**What the move changes.** Each machine now has its **own** clone and its own
worktrees, and **GitHub is the only transport between them** — which it always
should have been, since a sync client and `origin` are two uncoordinated
transports for the same bytes. So:

- a session's work reaches the other machine by *pushing a branch*, never by
  waiting for a folder to appear;
- worktrees are per-machine, so `o1next-wt-<issue>-<slug>` is unique on its own
  and the `-<machine>` suffix is no longer needed for correctness — keep it only
  when two machines deliberately work the same issue, for clarity.

**What it does not change.** One worktree per session, the main clone stays on
`main` and is not worked in, and session identity stays machine-local (below).

### Naming, and where worktrees go

Worktrees are siblings of the main clone, named **`o1next-wt-<issue>-<slug>`**:

```sh
cd ~/GitHub/o1next
git fetch origin
git worktree add ../o1next-wt-228-rename -b docs/rename-o1next origin/main
```

The name comes from the **issue**, never the machine, so the same name is right
whichever machine spawned it. Append `-<machine>` (lowercased
`scutil --get ComputerName`) only when a second session deliberately takes the
same issue on the other machine.

Siblings-of-the-clone is now a free choice rather than a compromise: `~/GitHub/`
is outside iCloud, so a worktree costs disk and nothing else.

### Session identity lives outside the repo

Which machine, which worktree, which issue, what state: that is machine-local and
must not sync, so it lives in `$HOME`, which is not under `~/Documents`.

| what | where | read by |
|---|---|---|
| routing rule + machine identity | `~/.cline/rules/10-o1next-sessions.md` | Cline, as a **global rule** — documented global locations are macOS `~/Documents/Cline/Rules`, and Cline also searches `~/.cline/rules` |
| the same rule, cross-tool | `~/.agents/AGENTS.md` | Cline, as cross-tool global AGENTS instructions |
| the per-session brief | `~/.cline/o1nextgen/<workspace-directory-name>.md` | the session itself, before its first edit |

The brief directory keeps its old name until it is renamed by hand: it is
machine-local and outside this repository, so the sweep does not reach it.

The brief is keyed to the **directory the session was opened on** — a worktree
(`o1next-wt-228-rename`) or the main clone (`o1next`). A brief names the machine,
the worktree, the branch, the owned issue, the paths that session may touch, and
the operations it may not perform. A session whose brief is missing **says so and
stops** rather than inventing a scope — an unclaimed worktree is how two sessions
end up on one branch.

**One known Cline defect, before anyone trusts this too far:** VS Code on macOS
has an open report that global rules in `~/Documents/Cline/Rules`, `~/.clinerules`
and `~/.cline/rules` are not loaded in new sessions (cline/cline#12526, open,
stale). That is why the rule is written in two places — and why **this file stays
the load-bearing instruction**, being the one mechanism that is demonstrably read.

### Ownership

A session declares the issue it owns and the branch it is on: in its brief, and in
the first commit it makes. Two sessions never share a branch, and no session
switches another session's branch.

### What cannot be parallelised

- **Repo-wide sweeps.** #228 (the rename) and #200 (the `docs/` rewrite) touch
  nearly every file, so they conflict with each other and with any session editing
  `docs/`. One sweep at a time, alone — and #200 is deliberately *after* #228.
- **Moving or renaming the clone directory.** Every worktree's `.git` **file**
  holds an absolute path into the main clone's `.git`, so one `mv` breaks them all
  at once. The 2026-10-14 move is the worked example: all sessions stopped, and
  the worktree — which had nothing committed in it — was removed before the move
  and recreated after, rather than repaired. Where a worktree *does* hold work,
  `git worktree repair` (git ≥ 2.30) is the tool. **`.venv` never survives a
  move**: its `bin/` shebangs and `pyvenv.cfg` hold absolute paths, so delete it
  and re-run `tools/bootstrap.sh --install`.
- **Renaming the GitHub repository** changes `origin` for every session. Land it
  when no other session is mid-push.
- `git gc`, `git worktree prune` and `git worktree remove` are not
  concurrent-safe. A session that needs one says so first.

Everything else is the ordinary workflow above: branch from `main`, small signed
commits, one PR per unit of work, merge through the PR. See #234.

## When a tool is missing, ask — do not engineer around it

Host tooling is cheap and usually much better than a workaround. If the shape of
the work is being set by the *absence* of a program, stop and ask about installing
it (`brew install …`, `pip3 install …`, `gem install …`). The answer is usually
yes, and asking costs one message. **`REQUIREMENTS.md` is the running list** of
what the machine has, what needs it, and what is not installed yet — add a row
there in the same PR that installs something new.

Examples from this repo, including the ones that should have been asked earlier:

- `z80dasm` — asked for, approved, and it unblocked the Drive C disassembly (#6).
- `fonttools` + `brotli` — asked for, approved, and it turned the character ROM
  into a real web font in about thirty lines rather than a hand-written TTF
  writer (#44).
- **ImageMagick** — never asked for, so an hour went into hand-writing a BMP
  reader, a PNG writer and a colour sampler because macOS ships no PIL and no
  ImageMagick. A JPEG decoder that `sips` could have handled was also in scope.
- **A newer Ruby / Jekyll** — never asked for, so the site cannot be built
  locally and every layout change is hand-checked instead of rendered.

The stdlib-only rule for `tools/` is about *shipped* tooling. A host-only or
build-time tool is a different question — and it is a question worth asking
rather than engineering around.

## Asking the user — never use the blocking question modal

The interactive question modal (the multiple-choice prompt that blocks the turn)
**times out after five minutes and returns nothing**. The question is lost, the
agent has no answer, and the user loses their place mid-read. It is not a usable
channel.

- **Never use it.** No multiple-choice modals, no other blocking prompt.
- **Ask in plain prose, in the normal reply.** If a choice is genuinely needed,
  state the options as a short numbered list in the text.
- **Never block on an answer.** Do the reversible, in-scope part first, then say
  plainly what is waiting on the user and why.

This is the second kind of "ask" in this file. The section above is about asking
for **host tooling**, and it works because the answer arrives as an ordinary
message. A modal is the opposite: it blocks, it expires, and it produces nothing.

## Repo layout and house rules

- `research/` is an **intentional in-repo archive** of large binaries (PDF
  manuals, TD0/IMD disk images, photos). They are safety copies of
  documentation the project cannot complete without. **Never delete,
  "clean up", or gitignore them.** Provenance is recorded in
  `research/README.md` — when adding an archive file, add its row to the
  matching table there (file, description, source URL).
- `docs/` holds the analysis output: one Markdown doc per peripheral/area
  (`copower88-protocol.md`, `rt60a-analysis.md`, …), cross-referencing issue
  numbers and the `research/` files it derives from. Mermaid diagrams are
  welcome.
- `tools/` is the extraction pipeline (`cpmfs.py`, `edsk2raw.py`,
  `extract_all.sh`) — Python stdlib only, no new dependencies without asking.
- `research/pictures/` photos of the physical boards are **primary sources**,
  taken in-project — never treat them as replaceable stock images.
- Issue labels: `research`, `pre-hardware`, `hardware`, `firmware`,
  `software`, `hardware-gated`, `documentation`, `deliverable`, `misc`. Phase
  flow: Phase 0 research → Phase 1 hardware (KiCad) → Phase 2 Pico 2 W firmware
  → Phase 3 Osborne-side software → Phase 4 on-hardware validation → Phase 5
  modern-parts reproduction → **Phase Ω delivery**. Don't start `hardware-gated`
  work in software sessions.
- **`research` means the work *is* investigation.** It is not for issues whose
  *output* is a consolidation of research already done, a decision record, or
  documentation assembled from it — those are outcomes. The book (#75) is the
  worked example: it is "a consolidation pass, not a research pass", so it
  carries `documentation` alone.
- **Phases 0–5 produce *work*; Phase Ω produces *deliverables*.** A
  **deliverable** is a thing somebody else could build, flash, run or read —
  normally hardware + firmware (+ software). Deliverables carry the
  `deliverable` label and hang off the Phase Ω parent (#133), one per shippable
  artifact, and each declares what "finished" means for it. **Outcomes never sit
  in a research tree**: that is why the book is a deliverable and not Phase 0
  work, and why pulling it out moved Phase 0's bar from 15/23 to 15/22.
- **Assignees mean "the ball is with a person".** An issue whose remaining work
  only the maintainer can do — handling the physical machines, a keyring or
  account action, sending a note to a third party — is **assigned to the
  maintainer** (`Myrcurial`). Everything else stays **unassigned**, and
  unassigned means "still ours to work on" — including work that ends in a
  recommendation the maintainer then decides on.

## The MAME machines, and `boot-o1next.sh`

The emulated machines are this project's fastest feedback loop, and they are used
two ways. **Headless** for reproducible checks — `-video none`,
`SDL_VIDEODRIVER=dummy`, `-nothrottle` — which is every harness in `tools/research/`
and the right default for a test. And **windowed** to actually use the machine,
which no headless run substitutes for.

So: **when an emulated machine reaches a milestone, `boot-o1next.sh` goes in
beside it**, in the machine's own directory (`tools/emulator-setup/<machine>/`).
It is not a test and it is not a harness; it is the thing a person runs to play.
It must:

- boot with **video and sound on, in a window** (`-window`, because MAME's default
  is full screen) and at **normal speed** — no `-nothrottle`;
- take **up to two floppy images as positional arguments**, mounted as `-flop1`
  and `-flop2`, so the invocation is the same for every machine;
- mount everything else — a hard disk, a ROM image, a BIOS — through an
  **environment variable**, so the positional arguments stay stable;
- **never mount an in-repo image in place.** MAME writes back into a floppy image
  as it runs, and `research/` and `tools/` are archives. Copy first, and say so;
- **run MAME from outside the repo**, because MAME writes `cfg/` and `snap/` into
  the current directory;
- find the patched binary itself, or fail with a message that says how to get one.
  `mame` on `PATH` has no `osborne1nx`, and that is the single most confusing way
  to lose half an hour here.

`tools/emulator-setup/mame-osborne1nx/boot-o1next.sh` is the worked example.

**And a staged test machine, for using it away from the repo.** `stage.sh` copies
the binary, the ROM set and the launcher into one directory outside the repo —
`$HOME/Documents/O1NEXT/test-machine-issue-<n>/` by default — which is
self-contained: `cd` into it and `./boot-o1next.sh ../floppies/system-disk.imd`.
`boot-o1next.sh` is **self-locating**, so the same file is both the repo's launcher
and the staged one: it looks for `mame/<machine>` and `roms/` beside itself first,
and only falls back to a build tree if they are not there.

A staged machine is a **build artifact** in the ordinary sense — named for the
issue, regenerable with one command, disposable, and never committed. Two things
make it trustworthy rather than hopeful:

- its `MANIFEST` records what went into it and from where, and the staged ROMs are
  **CRC-checked against the machine's own `ROM_START`**, so a mismatched build tree
  fails loudly instead of booting something subtly wrong;
- the disks it is fed are staged **once and never overwritten**, because MAME
  writes back into a floppy image as it runs and those copies are the user's.

## Before declaring done

- `git status` clean or deliberately dirty (say which); branch pushed.
- PR open and linked to its issues; no dangling `closes #N`.
- Docs cross-references resolve: if you cite `docs/foo.md` or
  `research/bar/`, that file must exist **on the branch you're merging**.
- Commits verified signed: `%G?` = `G` on authored commits. GitHub merges read
  `E` until the `web-flow` key is imported (#160) — that is expected, not a
  failure.
