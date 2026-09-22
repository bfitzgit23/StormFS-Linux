#!/bin/bash
# Compatibility launcher for the provider-aware BFSOS version checker v8.
set -e
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec python3 "$SCRIPT_DIR/checkupdate.py" "$@"
