# AGENTS.md — working agreement for AI agents in this repo

This file is the authoritative operating procedure for any AI coding/research
agent working in `o1nextgen`. Follow it over generic defaults.

## Issue tracking: GitHub ONLY

- All issues, planning, phases, and task state for this project live in
  **GitHub Issues** on `Myrcurial/o1nextgen`. Use `gh issue list`,
  `gh issue view #N`, `gh issue create`.
- **Do NOT use the Linear MCP server for this project.** A Linear connection
  exists on this machine for unrelated work in other repos. Nothing in Linear
  refers to o1nextgen. Never create, search, update, or reference Linear
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

## Before declaring done

- `git status` clean or deliberately dirty (say which); branch pushed.
- PR open and linked to its issues; no dangling `closes #N`.
- Docs cross-references resolve: if you cite `docs/foo.md` or
  `research/bar/`, that file must exist **on the branch you're merging**.
- Commits verified signed: `%G?` = `G` on authored commits. GitHub merges read
  `E` until the `web-flow` key is imported (#160) — that is expected, not a
  failure.
