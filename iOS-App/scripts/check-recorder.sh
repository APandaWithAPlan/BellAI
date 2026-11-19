#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-checks.XXXXXX")
xcrun swiftc -parse-as-library \
  BellAI/Services/RecorderReceiver.swift \
  BellAI/Services/RecorderWifiSetup.swift \
  BellAITests/RecorderReceiverChecks.swift \
  -o "$check_dir/check-recorder"
"$check_dir/check-recorder"
