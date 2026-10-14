#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/twinglow-wifi-frame-test.XXXXXX")"
trap 'rm -rf "$task_test_dir"' EXIT
c++ -std=c++17 -fsanitize=address,undefined -g tools/wifi-diagnostic/frame-test.cpp -o "$task_test_dir/frames"
"$task_test_dir/frames"
