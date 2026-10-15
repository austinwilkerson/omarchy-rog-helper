#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
"$plugin_dir/scripts/revoke-access.sh" lightbar
# The external z13ctl CLI and last-applied settings are kept for other users/tools.
