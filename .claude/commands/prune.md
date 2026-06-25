---
description: Delete a branch locally and on origin via a plain bash script
---

Run `review/prune.sh` to delete a branch both locally and on `origin` for the branch described in `$ARGUMENTS`.

- Run: `review/prune.sh --branch "$ARGUMENTS"`.
- If the user's arguments include a base branch (e.g. "base: develop" or "--base develop"), pass it through as `--base <branch>` and strip it from the branch name; otherwise omit it and let the script default to `main`.
- If no branch name is given, use the current branch (`git rev-parse --abbrev-ref HEAD`) as `--branch`.
- Run the command with Bash and report back the result printed at the end.
