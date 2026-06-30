import argparse
import asyncio

from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, ResultMessage


def parse_args():
    parser = argparse.ArgumentParser(description="Create and check out a new feature branch.")
    parser.add_argument(
        "--task",
        required=True,
        help='Description of the upcoming change, used to name the branch, e.g. --task "fix the off-by-one in parser.py"',
    )
    parser.add_argument(
        "--base",
        default="main",
        help="Base branch to branch from (default: main)",
    )
    return parser.parse_args()


def build_prompt(task: str, base: str) -> str:
    return f"""You are working in a git repository.

1. Make sure `{base}` is up to date locally (fetch/pull as needed without overwriting local changes).
2. Create a new branch off `{base}` with a short, descriptive, kebab-case name derived
   from this task: {task}
3. Check out the new branch.

Report the branch name you created at the end."""


async def main():
    args = parse_args()
    async for message in query(
        prompt=build_prompt(args.task, args.base),
        options=ClaudeAgentOptions(
            setting_sources=[],
            allowed_tools=["Bash"],
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
            print(f"FEATURE_AGENT_SUMMARY::{summary}")
            session_id = message.session_id

    print(f"Session ID: {session_id}")
    return session_id


if __name__ == "__main__":
    asyncio.run(main())
