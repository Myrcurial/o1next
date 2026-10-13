# _posts/

Blog entries, one file per post: `YYYY-MM-DD-slug.md` with front matter:

```markdown
---
layout: post
title: "My first computer"
date: 2026-10-10 12:58:01 -0400
author: Jamie Arlen
---

Post body in Markdown.
```

## `date:` is stamped at merge time — 15 minutes is close enough

**Every post carries an explicit `date:`**, written `YYYY-MM-DD HH:MM:SS ±HHMM`
with the timezone it was committed in. It records *publication*: a post is
published when its pull request merges, so the date is stamped at the merge
rather than when the file was written.

**The exact merge timestamp cannot exist before the merge.** GitHub sets the
merge commit's date, and its API does not accept one you supply — so an exact
minute would mean merging and then pushing a second commit to correct the file,
which costs more than it is worth. The rule is therefore a tolerance, not an
equality:

> **Make `date:` the last change before you merge, and merge promptly. Within 15
> minutes of the merge is close enough.**

In practice the stamp lands a few seconds *before* the merge, which is the right
direction — the post is dated as of going live. The last commit on the branch
should be the one that settles `date:`; nothing after it touches the file. The
date in the filename remains the best guess at the publish day; the front-matter
`date:` is the finer value.

`site/_config.yml` permalinks on `/:year/:month/:day/:title/`, so `date:` also
decides the post's URL — and a front-matter `date:` **wins over the date in the
filename**. The two only agree when a post merged on its filename's day. When
they disagree, `date:` is the truth and the URL follows it.

To see how close a post's stamp landed, compare it with its merge commit:

```
git log --first-parent --diff-filter=A --format='%ci' main -- site/_posts/<file>
```

Planned posts are listed in `../README.md` and tracked in the GitHub
issue filed for the blog rollout (#59).
