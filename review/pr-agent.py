import argparse
import asyncio
import json
import re
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

Do not read any file excluded by `.gitignore` (check with `git check-ignore`
if unsure) — they may contain real credentials and are never relevant to
making this change.

Context gathered up front (no need to re-run these checks):
- Diff stat vs `{base}`:
{diff_stat}
- Working tree status (`git status --short`):
{status}
- Commits ahead of `{base}` (`git log origin/{base}..HEAD --oneline`):
{log}

Do the following:

1. Make the following change: {task}
2. Run any relevant tests/linters if they exist and fix failures you introduced.

Do NOT run `git add`, `git commit`, `git push`, or `gh pr create` yourself —
a wrapper script handles staging, committing, pushing, and opening the PR
after you finish. Do not re-verify state with `git status`/`git diff`/`git log`
unless a command you ran failed; trust the context above.

When you are done editing, output ONLY the following JSON object as your
final message, with no surrounding text or code fences:

{{"commit_message": "<concise commit message explaining why, not just what>", "pr_title": "<short PR title>", "pr_body": "<PR body in markdown with a Summary and Test plan section>"}}"""


def extract_plan(result_text: str) -> dict:
    match = re.search(r"\{.*\}", result_text, re.DOTALL)
    if not match:
        raise SystemExit(f"Could not find JSON plan in agent output:\n{result_text}")
    plan = json.loads(match.group(0))
    for key in ("commit_message", "pr_title", "pr_body"):
        if not plan.get(key):
            raise SystemExit(f"Agent plan missing required field {key!r}: {plan}")
    return plan


def commit_push_and_open_pr(plan: dict, base: str, branch: str) -> str:
    subprocess.run(["git", "add", "-A"], check=True)
    subprocess.run(["git", "commit", "-m", plan["commit_message"]], check=True)
    subprocess.run(["git", "push", "-u", "origin", branch], check=True)
    pr = subprocess.run(
        [
            "gh", "pr", "create",
            "--base", base,
            "--title", plan["pr_title"],
            "--body", plan["pr_body"],
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return pr.stdout.strip()


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
    result_text = ""
    async for message in query(
        prompt=prompt,
        options=ClaudeAgentOptions(
            setting_sources=[],
            allowed_tools=["Read", "Edit", "Bash"],
            permission_mode="acceptEdits",
            model="claude-sonnet-4-6",
            max_turns=15
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
            result_text = message.result or ""
            session_id = message.session_id

    plan = extract_plan(result_text)
    pr_url = commit_push_and_open_pr(plan, args.base, branch)
    print(f"PR_AGENT_SUMMARY::{pr_url}")
    print(f"Session ID: {session_id}")
    return session_id


if __name__ == "__main__":
    asyncio.run(main())
