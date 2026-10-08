#!/usr/bin/env bash
# Install an existing private header; does not rotate credentials or flash hardware.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
  tg_f4ec6bb0ef83|tg_a398a36269f7) device_id="$1" ;;
  *) echo "Usage: bash tools/select-device-credentials.sh {tg_f4ec6bb0ef83|tg_a398a36269f7}" >&2; exit 1 ;;
esac
if [[ "$#" -ne 1 ]]; then
  echo "Expected exactly one device ID." >&2
  exit 1
fi
credential_source="$project_root/.private/device-credentials/$device_id.h"
if [[ ! -f "$credential_source" ]]; then
  echo "Missing private credential file for $device_id." >&2
  exit 1
fi
install -m 600 "$credential_source" "$project_root/TwinGlow/DeviceCredentials.h"
echo "DeviceCredentials.h now uses $device_id. Rebuild before uploading to that board."
