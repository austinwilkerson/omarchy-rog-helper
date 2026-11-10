#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
exec python3 -B "$script_dir/fnlock-setup.py" remove
