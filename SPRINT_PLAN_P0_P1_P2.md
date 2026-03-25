# SlideCrop Improvement Sprint Plan (P0/P1/P2)

Branch: `sprint/slidecrop-coreloop-clarity-20260312`

## P0 (Core trust/clarity loop)
1. Results summary + guidance card
   - File: `SlideCrop/Views/ResultsView.swift`
2. Save/replace clarity (blocked replace reason + free-save context)
   - Files: `SlideCrop/Views/ResultsView.swift`, `SlideCrop/ViewModels/ResultsViewModel.swift`
3. Clear review/failed explanations
   - Files: `SlideCrop/Views/ResultsView.swift`, `SlideCrop/Components/ResultThumbnailCell.swift`
4. Per-item quick actions (compare/adjust/retry)
   - File: `SlideCrop/Views/ResultsView.swift`
5. Failure recovery UX (retry best quality + manual path messaging)
   - File: `SlideCrop/Views/ResultsView.swift`

## P1 (Workflow friction reduction)
1. Onboarding/helper copy around replace-original limitations
   - File: `SlideCrop/Views/HomeView.swift`
2. Settings help text for processing quality/readability tradeoffs
   - File: `SlideCrop/Views/SettingsView.swift`
3. Better completion messaging and next actions after processing
   - File: `SlideCrop/Views/ProcessingView.swift` and/or `ResultsView.swift`

## P2 (Higher leverage / reasonable sprint subset)
1. Lightweight local diagnostics logging (core events)
   - File: `SlideCrop/Services/AnalyticsLogger.swift` (new), hook into `ResultsView.swift` + `ProcessingViewModel.swift`
2. Retry telemetry display hook (non-blocking, optional in UI)
   - File: `SlideCrop/Views/ResultsView.swift`
3. Keep architecture safe: no backend/account changes in this sprint
