#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-checks.XXXXXX")
xcrun swiftc -D DEBUG -parse-as-library \
  BellAI/Models/ChatRequest.swift \
  BellAI/Services/HTTPBellAIService.swift \
  BellAI/ViewModels/ChatViewModel.swift \
  BellAITests/OllamaSubmissionChecks.swift \
  -o "$check_dir/check-ollama"
"$check_dir/check-ollama"
