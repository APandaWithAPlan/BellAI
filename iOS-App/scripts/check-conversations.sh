#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-conversations-checks.XXXXXX")
xcrun swiftc -parse-as-library \
  BellAI/Models/ConversationNotes.swift \
  BellAI/ViewModels/ConversationsViewModel.swift \
  BellAITests/ConversationsChecks.swift \
  -o "$check_dir/check-conversations"
"$check_dir/check-conversations"
