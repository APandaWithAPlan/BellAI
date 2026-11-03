#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/bellai-checks.XXXXXX")
xcrun swiftc -D DEBUG -parse-as-library \
  BellAI/Models/ChatRequest.swift \
  BellAI/Models/TaskItem.swift \
  BellAI/Models/MealAnalysis.swift \
  BellAI/Models/MailItem.swift \
  BellAI/Models/FoodPreferences.swift \
  BellAI/Models/MealJournal.swift \
  BellAI/Services/MealLogging.swift \
  BellAI/Services/MailService.swift \
  BellAI/Services/InsightsService.swift \
  BellAI/Services/SpeechTranscriptionService.swift \
  BellAI/ViewModels/MealPhotoViewModel.swift \
  BellAI/ViewModels/MailViewModel.swift \
  BellAI/ViewModels/InsightsViewModel.swift \
  BellAI/Services/HTTPBellAIService.swift \
  BellAI/Services/ServerSettings.swift \
  BellAI/Services/FoodAnalysisService.swift \
  BellAI/Services/VoiceStreamService.swift \
  BellAI/Services/ServerConnectionMonitor.swift \
  BellAI/Services/MicrophoneService.swift \
  BellAI/Services/SpeechPlayer.swift \
  BellAI/ViewModels/ChatViewModel.swift \
  BellAI/ViewModels/TasksViewModel.swift \
  BellAITests/OllamaSubmissionChecks.swift \
  -o "$check_dir/check-ollama"
"$check_dir/check-ollama"
