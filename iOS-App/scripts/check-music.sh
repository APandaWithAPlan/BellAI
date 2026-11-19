#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-music-checks.XXXXXX")
xcrun swiftc -parse-as-library \
  BellAI/Models/Music.swift \
  BellAI/ViewModels/MusicViewModel.swift \
  BellAITests/MusicChecks.swift \
  -o "$check_dir/check-music"
"$check_dir/check-music"
