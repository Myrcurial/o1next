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

## `date:` is the merge timestamp

**Every post carries an explicit `date:`**, set to the moment its pull request
was merged to `main` — the merge commit's committer date, written
`YYYY-MM-DD HH:MM:SS ±HHMM` with the timezone it was committed in.

It is the *merge* time, not the time the file was first written. A post is
authored on a branch and published when its PR lands, so the date records
publication. The date in the filename is the best guess at the publish day and
is what the file is named by; the front-matter `date:` is the exact moment.

`site/_config.yml` permalinks on `/:year/:month/:day/:title/`, so `date:` also
decides the post's URL — and a front-matter `date:` **wins over the date in the
filename**. The two only agree when a post merged on its filename's day. When
they disagree, `date:` is the truth and the URL follows it.

To recover a post's merge timestamp:

```
git log --first-parent --diff-filter=A --format='%ci' main -- site/_posts/<file>
```

Planned posts are listed in `../README.md` and tracked in the GitHub
issue filed for the blog rollout (#59).
