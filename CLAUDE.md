# SlideCrop - Project Notes for Claude

## What This App Does
SlideCrop is an iOS app that automatically detects presentation slides in photos, applies perspective correction, and cleans them up. Users import photos (from library or camera), the app finds and straightens any slides using computer vision, then users can save the results or manually adjust the crop.

**Monetisation**: Free tier (10 saves), then one-time purchase for unlimited saves.
- Product ID: `com.newsira.slidecrop.unlimited`
- Free save limit tracked in UserDefaults (`slidesSavedCount` key)

## Project Structure
```
SlideCrop/
├── App/
│   └── SlideCropApp.swift           # Entry point → WindowGroup { HomeView() }
├── Views/
│   ├── HomeView.swift               # Main screen, photo/camera picker, permissions
│   ├── ProcessingView.swift         # Real-time processing progress bar + thumbnail
│   ├── ResultsView.swift            # Grid of results, selection, save/replace, paywall gating
│   ├── CompareView.swift            # Before/after side-by-side with zoom
│   ├── CropAdjustmentView.swift     # Interactive manual crop editor with loupe + undo
│   ├── SettingsView.swift           # Privacy policy, contact support, workflow tips
│   └── PaywallView.swift            # IAP unlock screen with restore
├── ViewModels/
│   ├── ProcessingViewModel.swift    # Concurrent processing pipeline, ordered result buffering
│   ├── ResultsViewModel.swift       # Save/replace operations + toast notifications
│   ├── SettingsViewModel.swift      # Returns hardcoded ProcessingSettings (best + enhance)
│   ├── PurchaseManager.swift        # StoreKit 2 purchase, restore, entitlement verification
│   └── FreeSaveCounter.swift        # Tracks free 10-save quota (UserDefaults)
├── Services/
│   ├── SlideCropService.swift       # Core Vision + CoreImage processing engine
│   └── PhotoLibraryService.swift    # Photos framework: access, thumbnails, save, replace
├── Models/
│   ├── ProcessedItem.swift          # Processed image result (status, confidence, crop, URLs)
│   ├── ProcessingSettings.swift     # Quality settings: fast (1000px) vs best (1400px)
│   ├── CropQuad.swift               # 4-point normalised crop boundary (0–1 coordinates)
│   └── SlideCropError.swift         # Custom error types with localized descriptions
├── Components/
│   ├── CropOverlayView.swift        # Interactive crop quad overlay with corner/edge handles + loupe
│   ├── HeroCropIconView.swift       # Animated slide-straightening hero illustration
│   ├── PressScaleButtonStyle.swift  # Button press animation + SlideCropTheme colour palette
│   ├── ResultThumbnailCell.swift    # Grid cell: thumbnail, status badge, confidence %, selection
│   └── ZoomableImageView.swift      # UIViewRepresentable pinch-to-zoom (1x–5x)
└── Resources/
    ├── Assets.xcassets/
    ├── Info.plist
    └── PrivacyInfo.xcprivacy
```

## Architecture
**Pattern**: MVVM with SwiftUI
- Views are pure SwiftUI — no UIKit views except UIViewControllerRepresentable wrappers for pickers
- ViewModels use `@MainActor` + `@Published` for thread-safe state
- Async/await + `withTaskGroup` for concurrent image processing
- Services handle all framework interactions (Photos, Vision, CoreImage)
- Navigation: `NavigationStack` with `navigationPath: [HomeRoute]` (.processing, .results)

## User Flow
1. **HomeView** → user selects photos (library picker) or takes photo (camera)
2. **ProcessingView** → shows progress bar, current thumbnail, count
3. **ResultsView** → grid of results grouped by status (Ready/Needs Review/Failed)
   - Select items → Save as New or Replace Originals
   - Per-item actions: Compare, Adjust Crop, Retry Best Quality
   - Paywall gate if free saves exhausted
4. **CompareView** → side-by-side before/after with zoom; "Use This" promotes review→ready
5. **CropAdjustmentView** → drag corners/edges, loupe magnifier, undo stack, apply reprocessing

## Key Technical Details
- **iOS Target**: 17.0+
- **Build config**: XcodeGen (`project.yml`)
- **Frameworks**: Vision, CoreImage, Photos, AVFoundation, StoreKit 2
- **Build command**: `xcodebuild -project SlideCrop.xcodeproj -scheme SlideCrop -destination 'platform=iOS Simulator,name=iPhone 16' build`

### Image Processing Pipeline (SlideCropService.swift)
1. Downsample image (fast=1000px, best=1400px long edge)
2. Detect rectangles with `VNDetectRectanglesRequest` (max 10 observations, min 50% confidence, min 20% size, 22° quadrature tolerance)
3. Score candidates with weighted formula:
   - Area ratio: 36% — penalises too-small or too-large detections (10%–88% range)
   - Aspect ratio: 25% — rewards closeness to 4:3 or 16:9
   - Centeredness: 18% — penalises off-centre detections
   - Skew sanity: 16% — corner angles near 90° + edge length balance (75%/25% split)
   - Text density: 5% — bonus from VNRecognizeTextRequest fast mode
4. Confidence ≥ 0.68 → `.auto` (Ready); < 0.68 → `.review` (Needs Review); no detection → `.failed`
5. Perspective correct with `CIPerspectiveCorrection`
6. Optional readability boost: +5% contrast, +2% brightness via `CIColorControls`
7. Export JPEG 0.9 quality to `/tmp/slidecrop_*.jpg`

### Processing Concurrency (ProcessingViewModel.swift)
- `withTaskGroup` structured concurrency
- Fast mode: up to 3 concurrent tasks; Best mode: up to 2
- Capped by CPU count (max 3, min 1)
- **Ordered commit buffer**: results collected in `completedBuffer[index]` and flushed in order so UI shows items in the same sequence as input
- Input types: `assetIdentifier` (photo library), `itemProvider` (PHPicker), `imageData` (camera)
- DEBUG builds log per-item timing and batch statistics

### Photo Library (PhotoLibraryService.swift)
- Supports `.authorized`, `.limited`, and `.denied` access states
- **Save new**: Creates new `PHAsset` via `PHAssetCreationRequest`
- **Replace original**: Uses `PHContentEditingOutput` with reversible adjustment data (format `"com.local.SlideCrop.adjustment"` v1.0)
- Replace only works for photo library assets — camera/picker items have no asset identifier
- Thumbnails fetched via `PHImageManager` with high quality + fast resize mode

### In-App Purchase (PurchaseManager.swift)
- StoreKit 2 with `Product.products(for:)` to load product
- `Transaction.currentEntitlements` for verification
- `AppStore.sync()` for restore
- Caches unlock state in UserDefaults (`isUnlocked` key)
- Detects storefront mismatch (country code vs device region)

### Theme System (PressScaleButtonStyle.swift)
- `SlideCropTheme` enum with colour palette:
  - Tint: indigo (#5A6EDB)
  - Badge colours: ready (green), review (orange), failed (red) — light/dark variants
  - Crop accent: cyan (#62F0C2)
  - Primary gradient: indigo → purple
- `SlideCropPageBackground` — layered gradient background (base + page + 2 radial)
- `.slideCropCard` modifier — ultra-thin material + stroke + shadow

### Manual Crop Editor (CropAdjustmentView.swift)
- Zoomable canvas (1x–6x) with overlay crop quad
- 4 corner handles (free drag) + 4 edge midpoint handles (perpendicular drag only)
- Loupe magnifier: 132pt circle, 2.8x zoom, auto-repositions away from finger
- Undo stack: up to 40 snapshots, captured on interaction start/end
- On apply: calls `SlideCropService.processManualAdjustment()` and updates the ProcessedItem

### Results & Selection Logic (ResultsView.swift)
- Auto-selects all `.auto` items on first load
- Re-selects items that upgrade from `.review` → `.auto` after manual adjustment
- Per-item context menu: Compare, Adjust Crop, Retry Best Quality, Select/Deselect
- Retry reprocesses with `.best` quality, attempts asset first then falls back to sourceImageURL
- Save gating: checks free save count → shows PaywallView if exhausted → defers save action until purchase completes

## Key Constants & Thresholds
| Constant | Value | Location |
|---|---|---|
| Confidence threshold | 0.68 | SlideCropService.swift |
| Free save limit | 10 | FreeSaveCounter.swift |
| Fast mode long edge | 1000px | ProcessingSettings.swift |
| Best mode long edge | 1400px | ProcessingSettings.swift |
| Max concurrent (fast) | 3 | ProcessingViewModel.swift |
| Max concurrent (best) | 2 | ProcessingViewModel.swift |
| Min detection size | 0.2 (20%) | SlideCropService.swift |
| Max rectangles | 10 | SlideCropService.swift |
| JPEG export quality | 0.9 | SlideCropService.swift |
| Readability: contrast | +5% | SlideCropService.swift |
| Readability: brightness | +2% | SlideCropService.swift |
| Zoom range (crop editor) | 1x–6x | CropAdjustmentView.swift |
| Undo history limit | 40 | CropAdjustmentView.swift |
| Loupe size / zoom | 132pt / 2.8x | CropOverlayView.swift |

## Important Notes
- **Bundle ID (production)**: `com.newsira.slidecrop` — app is live on the App Store
- **Bundle ID (local dev)**: `com.local.SlideCrop` in project.yml — needs swapping for App Store builds
- **GitHub account**: siradevv
- **Privacy manifest**: `Resources/PrivacyInfo.xcprivacy` in place
- **Info.plist permissions**: Camera, Photo Library (read), Photo Library (add)
- **App Store checklist**: See `AppStoreSubmissionChecklist.md` in project root
- **Sprint plan**: See `SPRINT_PLAN_P0_P1_P2.md` for current improvement priorities (P0: results clarity & trust, P1: workflow friction, P2: diagnostics)
- **Regression checklist**: See `PROCESSING_REGRESSION_CHECKLIST.md` for baseline testing protocol
- Temp files written to `/tmp/slidecrop_*` — cleaned up on processing cancel

## Build Notes
- XcodeGen generates the `.xcodeproj` from `project.yml`
- To regenerate: `xcodegen generate`
- Simulator build: `xcodebuild -project SlideCrop.xcodeproj -scheme SlideCrop -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Signed archive at `/build/SlideCrop.xcarchive` (may be outdated)
