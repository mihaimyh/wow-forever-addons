#!/usr/bin/env bash
# Git Bash / POSIX wrapper for scripts/release-curseforge.mjs
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node "$SCRIPT_DIR/release-curseforge.mjs" "$@"
