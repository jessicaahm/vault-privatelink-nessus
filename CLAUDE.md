# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This repo documents the setup of a Tenable Nessus vulnerability scanner on AWS, connected to an HCP Vault cluster over AWS PrivateLink. It is primarily a collection of runbooks/notes and a single setup script, not an application.

Prerequisites: an AWS account and a Nessus Tenable One license.

## Layout

- `README.md` — architecture/prerequisites overview.
- `private-link.md` — step-by-step runbook for establishing the AWS PrivateLink connection between an HCP Vault HVN and a consumer AWS account (HCP API auth, `private-link-services` create/get calls via curl, VPC Endpoint creation). This file is gitignored and untracked because it contains real HCP client credentials and account IDs from past runs — never remove it from `.gitignore` or commit it as-is.
- `script/01_setup_nessus.sh` — idempotent bash script to install and start the Nessus scanner daemon on Ubuntu/Debian.
- `.env` / `.env.sample` — `.env` holds real local secrets and is gitignored; `.env.sample` is the committed template. Every variable defined in `.env` must have a corresponding entry (name only, placeholder value) in `.env.sample` — keep the two files' variable lists in sync whenever either changes.

## Working with `script/01_setup_nessus.sh`

Run directly on a target Ubuntu/Debian host (not locally on macOS):

```bash
bash script/01_setup_nessus.sh
```

It downloads the Nessus `.deb` (version pinned via `NESSUS_VERSION`), installs it with `dpkg`/`apt-get -f`, enables/starts the `nessusd` systemd service, and checks `https://localhost:8834`. The script uses `set -euo pipefail` and re-execs privileged steps with `sudo` if not already root — preserve this pattern when adding steps. There are no build, lint, or test commands for this repo.

## Working with `private-link.md`

This is a manual runbook, not executable code — commands are meant to be run one at a time against the HCP Cloud API (`api.cloud.hashicorp.com`) and HCP auth endpoint (`auth.idp.hashicorp.com`), using `curl`/`jq`. When editing or extending it:
- Treat any embedded `HCP_CLIENT_ID`/`HCP_CLIENT_SECRET`/org/project IDs as already-exposed example values tied to past runs, not live secrets to reuse — generate fresh credentials for any real execution.
- Keep the flow order intact: create HVN → create Vault cluster → fetch HCP API token → create private-link-service (specifying `consumer_accounts` ARNs and `consumer_ip_ranges`) → poll until `state` is `AVAILABLE` → create the consumer-side VPC Endpoint in AWS.
