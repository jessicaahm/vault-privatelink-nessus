---
description: Implement the current branch's change end-to-end and open a PR via the Claude Agent SDK script
---

Run `review/pr-agent.py` to implement the change for the current feature branch, commit, push, and open a PR.

- Use the project's `.venv` interpreter: `.venv/bin/python review/pr-agent.py`.
- If the user's arguments (`$ARGUMENTS`) mention a base branch (e.g. "base: develop" or "--base develop"), pass it through as `--base <branch>`; otherwise omit it and let the script default to `main`.
- This script requires the repo to already be checked out on a feature branch (not the base branch) — if it errors out because you're on the base branch, tell the user to run `/feature` first.
- Run the command with Bash and report back the PR URL and session ID printed at the end.
