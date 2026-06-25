---
description: Create and check out a new feature branch via a plain bash script
---

Run `review/feature.sh` to create and check out a new feature branch for the task described in `$ARGUMENTS`.

- Run: `review/feature.sh --task "$ARGUMENTS"`.
- If the user's arguments include a base branch (e.g. "base: develop" or "--base develop"), pass it through as `--base <branch>`; otherwise omit it and let the script default to `main`.
- Run the command with Bash and report back the branch name printed at the end.
