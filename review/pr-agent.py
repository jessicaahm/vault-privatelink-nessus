import argparse
import asyncio
import subprocess

from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, ResultMessage


def parse_args():
    parser = argparse.ArgumentParser(description="Make a code change and open a PR for it.")
    parser.add_argument(
        "--base",
        default="main",
        help="Base branch to branch from and target with the PR (default: main)",
    )
    return parser.parse_args()


def current_branch() -> str:
    return subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def task_from_branch(branch: str) -> str:
    return branch.replace("-", " ").replace("_", " ").strip()


def diff_against_base(base: str) -> str:
    merge_base = subprocess.run(
        ["git", "merge-base", "HEAD", f"origin/{base}"],
        capture_output=True,
        text=True,
    )
    ref = merge_base.stdout.strip() if merge_base.returncode == 0 else base
    diff = subprocess.run(
        ["git", "diff", ref, "--stat"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return diff or "(no committed diff yet — working tree may have uncommitted changes only)"


def status_summary() -> str:
    return subprocess.run(
        ["git", "status", "--short"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip() or "(clean working tree)"


def recent_log(base: str) -> str:
    return subprocess.run(
        ["git", "log", f"origin/{base}..HEAD", "--oneline"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip() or "(no commits ahead of base yet)"


def build_prompt(task: str, base: str, branch: str) -> str:
    diff_stat = diff_against_base(base)
    status = status_summary()
    log = recent_log(base)
    return f"""You are working in a git repository, already checked out on the feature
branch `{branch}` this change belongs on (not `{base}`).

Context gathered up front (no need to re-run these checks):
- Diff stat vs `{base}`:
{diff_stat}
- Working tree status (`git status --short`):
{status}
- Commits ahead of `{base}` (`git log origin/{base}..HEAD --oneline`):
{log}

Do the following end to end:

1. Make the following change: {task}
2. Run any relevant tests/linters if they exist and fix failures you introduced.
3. Stage and commit ALL changes in the working tree relevant to this branch's
   work — both modified tracked files and untracked files/directories — except
   anything excluded by `.gitignore`. Do not narrow the commit to a subset of
   files based on your own judgment of "scope"; if a file is untracked and not
   gitignored, it belongs in this PR. Use a concise commit message explaining
   why, not just what.
4. Push the current branch to origin.
5. Open a pull request against `{base}` using the `gh` CLI (`gh pr create`), with a title
   and body summarizing the change and a test plan.

Report the PR URL at the end."""


async def main():
    args = parse_args()

    branch = current_branch()
    if branch == args.base:
        raise SystemExit(
            f"Currently on `{branch}`, same as --base. Check out the feature branch first."
        )
    task = task_from_branch(branch)
    prompt = build_prompt(task, args.base, branch)

    session_id = None
    async for message in query(
        prompt=prompt,
        options=ClaudeAgentOptions(
            setting_sources=[],
            allowed_tools=["Read", "Edit", "Glob", "Grep", "Bash"],
            permission_mode="acceptEdits",
            model="claude-sonnet-4-6",
        ),
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text)
                elif hasattr(block, "name"):
                    print(f"Tool: {block.name}")
                    if block.name == "Bash":
                        print(f"  $ {block.input.get('command')}")
        elif isinstance(message, ResultMessage):
            summary = message.result or f"Done: {message.subtype}"
            print(f"PR_AGENT_SUMMARY::{summary}")
            session_id = message.session_id

    print(f"Session ID: {session_id}")
    return session_id


if __name__ == "__main__":
    asyncio.run(main())
