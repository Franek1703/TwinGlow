#!/usr/bin/env bash
# Apply TwinGlow's payload-move patch to the installed FirebaseClient library.
# See README.md for what it changes and why.
#
#   ./apply.sh                       # patch the library found in the usual places
#   ./apply.sh --check               # report status only, exit 1 if unpatched
#   ./apply.sh /path/to/FirebaseClient
set -euo pipefail
exec python3 "$(dirname "$0")/apply.py" "$@"
