#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-weather-checks.XXXXXX")
xcrun swiftc -parse-as-library \
  BellAI/Services/OpenWeatherClient.swift \
  BellAI/Services/BriefingWeatherService.swift \
  BellAI/ViewModels/BriefingWeatherViewModel.swift \
  BellAITests/BriefingWeatherChecks.swift \
  -o "$check_dir/check-weather"
"$check_dir/check-weather"
