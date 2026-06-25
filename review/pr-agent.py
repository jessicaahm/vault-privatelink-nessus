import argparse
import asyncio
import json
import re
import subprocess

from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, ResultMessage


def parse_args():
    parser = argparse.ArgumentParser(
        description="Describe the already-made changes on this branch and open a PR for them."
    )
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


def full_diff(base: str) -> str:
    merge_base = subprocess.run(
        ["git", "merge-base", "HEAD", f"origin/{base}"],
        capture_output=True,
        text=True,
    )
    ref = merge_base.stdout.strip() if merge_base.returncode == 0 else base
    diff = subprocess.run(
        ["git", "diff", ref, "--", ".", ":(exclude).env*"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    uncommitted = subprocess.run(
        ["git", "diff", "HEAD", "--", ".", ":(exclude).env*"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return (diff + uncommitted).strip() or "(no diff found)"


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


def build_prompt(base: str, branch: str) -> str:
    diff_stat = diff_against_base(base)
    status = status_summary()
    log = recent_log(base)
    diff = full_diff(base)
    return f"""You are reviewing changes already made by hand on git branch `{branch}`
(not `{base}`). Your only job is to describe these changes — you must NOT
edit, create, or delete any files, and must NOT run any git/gh commands
that change repo state. You have no tools other than reading the context
below; do not attempt to run Read/Edit/Bash.

Do not rely on or echo back the contents of `.env` or `.env.sample` — they
are excluded from the diff below on purpose since they may contain real
credentials.

Diff stat vs `{base}`:
{diff_stat}

Working tree status (`git status --short`):
{status}

Commits ahead of `{base}` (`git log origin/{base}..HEAD --oneline`):
{log}

Full diff (`.env*` files excluded):
{diff}

Based solely on the diff above, output ONLY the following JSON object as
your final message, with no surrounding text or code fences:

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
    if status_summary() == "(clean working tree)" and recent_log(args.base) == "(no commits ahead of base yet)":
        raise SystemExit(
            "No changes found on this branch (clean working tree, no commits ahead of "
            f"`{args.base}`). Make your edits first, then re-run /pr-agent."
        )
    prompt = build_prompt(args.base, branch)

    session_id = None
    result_text = ""
    async for message in query(
        prompt=prompt,
        options=ClaudeAgentOptions(
            setting_sources=[],
            allowed_tools=[],
            permission_mode="default",
            model="claude-sonnet-4-6",
            max_turns=1
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
