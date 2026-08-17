#!/bin/bash
# import-venomlinux.sh - Wrapper that runs the PowerShell import script
# Converts venomlinux/scratchpkg ports to CRUX/prt-get Pkgfile format
# and imports new ports into StormFS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
powershell -ExecutionPolicy Bypass -File "$SCRIPT_DIR/import-venomlinux.ps1"
