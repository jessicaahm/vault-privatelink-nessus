#!/usr/bin/env bash
set -euo pipefail

base="main"
branch=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      base="$2"
      shift 2
      ;;
    --branch)
      branch="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$branch" ]]; then
  echo "Usage: $0 --branch <name> [--base <branch>]" >&2
  exit 1
fi

if [[ "$branch" == "$base" ]]; then
  echo "Refusing to prune base branch: $branch" >&2
  exit 1
fi

current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" == "$branch" ]]; then
  git checkout "$base"
fi

if git show-ref --verify --quiet "refs/heads/$branch"; then
  git branch -D "$branch"
else
  echo "No local branch named $branch" >&2
fi

if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  git push origin --delete "$branch"
else
  echo "No remote branch named $branch on origin" >&2
fi

git fetch origin --prune

echo "Pruned branch: $branch"
