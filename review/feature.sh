#!/usr/bin/env bash
set -euo pipefail

base="main"
task=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      base="$2"
      shift 2
      ;;
    --task)
      task="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$task" ]]; then
  echo "Usage: $0 --task \"<description>\" [--base <branch>]" >&2
  exit 1
fi

slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')

if [[ -z "$slug" ]]; then
  echo "Could not derive a branch name from task: $task" >&2
  exit 1
fi

git fetch origin "$base"

current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" == "$base" ]]; then
  git merge --ff-only "origin/$base"
elif git show-ref --verify --quiet "refs/heads/$base"; then
  if git merge-base --is-ancestor "$base" "origin/$base"; then
    git branch -f "$base" "origin/$base"
  fi
else
  git branch "$base" "origin/$base"
fi

git checkout -b "$slug" "$base"

echo "Branch name: $slug"
