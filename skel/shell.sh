#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env ROOT=$ROOT $ROOT/install-util/shell.sh
