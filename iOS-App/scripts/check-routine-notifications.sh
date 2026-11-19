#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-routine-checks.XXXXXX")
xcrun swiftc -parse-as-library \
  BellAI/Models/Routine.swift \
  BellAI/Models/ChatRequest.swift \
  BellAI/Services/ServerSettings.swift \
  BellAI/Services/HTTPBellAIService.swift \
  BellAI/Services/HTTPRoutineService.swift \
  BellAI/Services/RoutineNotifications.swift \
  BellAITests/RoutineNotificationChecks.swift \
  -o "$check_dir/check-routines"
"$check_dir/check-routines"
