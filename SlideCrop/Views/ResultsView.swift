import SwiftUI

private enum ResultDestination: Identifiable {
    case compare(UUID)
    case adjust(UUID)

    var id: String {
        switch self {
        case let .compare(id):
            return "compare-\(id.uuidString)"
        case let .adjust(id):
            return "adjust-\(id.uuidString)"
        }
    }
}

private enum SaveAction {
    case saveAsNew
    case replaceOriginals
}

struct ResultsView: View {
    @ObservedObject var processingViewModel: ProcessingViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @StateObject private var resultsViewModel = ResultsViewModel()
    @StateObject private var purchaseManager = PurchaseManager()

    @State private var selectedDestination: ResultDestination?
    @State private var showPaywall = false
    @State private var pendingSaveAction: SaveAction?
    @State private var paywallRequestedCount = 0
    @State private var showSaveAlert = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var hasInitializedSelection = false
    @State private var previousStatusByID: [UUID: ProcessedStatus] = [:]
    @State private var remainingFreeSaves = 0
    @State private var retryingIDs: Set<UUID> = []

    private let retryService = SlideCropService()

    private let freeSaveCounter = FreeSaveCounter()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                resultsSummaryCard

                if !readyItems.isEmpty {
                    section(title: "Ready", ids: readyItems)
                }

                if !needsReviewItems.isEmpty {
                    section(title: "Needs Review", ids: needsReviewItems)
                }

                if !failedItems.isEmpty {
                    section(title: "Failed", ids: failedItems)
                }

                actionPanel
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(SlideCropPageBackground())
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if resultsViewModel.isSaving {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Saving")
                        .padding(18)
                        .slideCropCard(cornerRadius: 16)
                }
            }
        }
        .sheet(item: $selectedDestination) { destination in
            switch destination {
            case let .compare(id):
                if let itemBinding = binding(for: id) {
                    CompareView(
                        item: itemBinding,
                        settings: settingsViewModel.currentSettings()
                    ) { updated in
                        if updated.processedImageURL != nil {
                            selectedIDs.insert(updated.id)
                        }
                    }
                }
            case let .adjust(id):
                if let itemBinding = binding(for: id) {
                    CropAdjustmentView(
                        assetIdentifier: itemBinding.wrappedValue.assetIdentifier,
                        sourceImageURL: itemBinding.wrappedValue.sourceImageURL,
                        initialQuad: itemBinding.wrappedValue.cropQuad ?? .full,
                        settings: settingsViewModel.currentSettings(),
                        originalThumbnail: itemBinding.wrappedValue.originalThumbnail,
                        canReplaceOriginal: itemBinding.wrappedValue.canReplaceOriginal,
                        canManualAdjust: itemBinding.wrappedValue.canManualAdjust
                    ) { updated in
                        var merged = updated
                        merged.id = itemBinding.wrappedValue.id
                        itemBinding.wrappedValue = merged
                        if merged.processedImageURL != nil {
                            selectedIDs.insert(merged.id)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: clearPendingPaywallState) {
            PaywallView(
                purchaseManager: purchaseManager,
                remainingFreeSaves: remainingFreeSaves,
                requestedCount: paywallRequestedCount
            )
        }
        .onAppear {
            refreshRemainingFreeSaves()
            initializeSelectionIfNeeded(with: processingViewModel.processedItems)
        }
        .onReceive(processingViewModel.$processedItems) { items in
            syncSelection(with: items)
        }
        .onChange(of: purchaseManager.isUnlocked) { _, isUnlocked in
            refreshRemainingFreeSaves()
            guard isUnlocked, let action = pendingSaveAction else { return }
            showPaywall = false
            pendingSaveAction = nil
            Task {
                await runSaveAction(action)
            }
        }
        .onChange(of: resultsViewModel.toastMessage) { _, value in
            showSaveAlert = value != nil
        }
        .alert("SlideCrop", isPresented: $showSaveAlert) {
            Button("OK") {
                resultsViewModel.toastMessage = nil
            }
        } message: {
            Text(resultsViewModel.toastMessage ?? "")
        }
    }

    private var readyItems: [UUID] {
        processingViewModel.processedItems
            .filter { $0.status == .auto }
            .map(\.id)
    }

    private var needsReviewItems: [UUID] {
        processingViewModel.processedItems
            .filter { $0.status == .review }
            .map(\.id)
    }

    private var failedItems: [UUID] {
        processingViewModel.processedItems
            .filter { $0.status == .failed }
            .map(\.id)
    }

    private var exportableItems: [ProcessedItem] {
        processingViewModel.processedItems
            .filter { $0.status != .failed && $0.processedImageURL != nil }
    }

    private var replaceableItems: [ProcessedItem] {
        exportableItems.filter(\.canReplaceOriginal)
    }

    private var selectedExportableItems: [ProcessedItem] {
        exportableItems.filter { selectedIDs.contains($0.id) }
    }

    private var selectedReplaceableItems: [ProcessedItem] {
        replaceableItems.filter { selectedIDs.contains($0.id) }
    }

    private var failedItemsCount: Int {
        processingViewModel.processedItems.filter { $0.status == .failed }.count
    }

    private var replaceBlockedCount: Int {
        selectedExportableItems.count - selectedReplaceableItems.count
    }

    @ViewBuilder
    private var resultsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run Summary")
                .font(.headline)
            HStack(spacing: 10) {
                Label("Ready: \(readyItems.count)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SlideCropTheme.readyBadge)
                Label("Review: \(needsReviewItems.count)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(SlideCropTheme.reviewBadge)
                if failedItemsCount > 0 {
                    Label("Failed: \(failedItemsCount)", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(SlideCropTheme.failedBadge)
                }
            }
            .font(.subheadline.weight(.semibold))

            Text(needsReviewItems.isEmpty && failedItemsCount == 0 ? "Looks good. You can save now." : "Review flagged items before final save for best results.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .slideCropCard(cornerRadius: 18)
    }

    @ViewBuilder
    private var actionPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SlideCropTheme.tint)
                Text("\(selectedExportableItems.count) export-ready selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Save as New Images") {
                    Task {
                        await handleSaveAsNewTap()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SlideCropTheme.tint)
                .disabled(resultsViewModel.isSaving || selectedExportableItems.isEmpty)
                .frame(maxWidth: .infinity)

                Button("Replace Originals") {
                    Task {
                        await handleReplaceOriginalsTap()
                    }
                }
                .buttonStyle(.bordered)
                .tint(SlideCropTheme.tint.opacity(0.85))
                .disabled(resultsViewModel.isSaving || selectedReplaceableItems.isEmpty)
                .frame(maxWidth: .infinity)
            }

            if replaceBlockedCount > 0 {
                Text("\(replaceBlockedCount) selected image(s) cannot replace originals. Reason: imported without direct Photo Library linkage (camera/file picker). Save as New still works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !purchaseManager.isUnlocked {
                Text("Free saves left: \(remainingFreeSaves). Upgrade only when needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .slideCropCard(cornerRadius: 20)
    }

    @ViewBuilder
    private func section(title: String, ids: [UUID]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2){
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if title == "Needs Review" {
                    Text("Perspective confidence is lower. Tap item to compare or adjust crop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if title == "Failed" {
                    Text("Try Retry Best Quality. If still failing, use Adjust Crop for manual recovery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(ids, id: \.self) { id in
                    if let item = item(for: id) {
                        ZStack(alignment: .topTrailing) {
                            ResultThumbnailCell(
                                item: item,
                                isSelected: selectedIDs.contains(id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openItem(item, id: id)
                            }
                            .overlay(alignment: .center) {
                                if retryingIDs.contains(id) {
                                    ProgressView()
                                        .padding(8)
                                        .background(.ultraThinMaterial, in: Capsule())
                                }
                            }
                            .contextMenu {
                                Button("Open Compare", systemImage: "rectangle.split.2x1") { selectedDestination = .compare(id) }
                                if item.canManualAdjust {
                                    Button("Adjust Crop", systemImage: "crop") { selectedDestination = .adjust(id) }
                                }
                                if item.status != .auto {
                                    Button("Retry Best Quality", systemImage: "arrow.clockwise") {
                                        Task { await retryItem(id: id) }
                                    }
                                    .disabled(retryingIDs.contains(id))
                                }
                                Button(selectedIDs.contains(id) ? "Deselect" : "Select", systemImage: selectedIDs.contains(id) ? "checkmark.circle" : "circle") { toggleSelection(for: id) }
                            }

                            Button {
                                toggleSelection(for: id)
                            } label: {
                                Image(systemName: selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(id) ? SlideCropTheme.tint : Color.white.opacity(0.95))
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.36))
                                            .frame(width: 24, height: 24)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .disabled(!isSelectable(item))
                        }
                    }
                }
            }
        }
    }

    private func openItem(_ item: ProcessedItem, id: UUID) {
        if item.confidenceScore <= 0.0001, item.canManualAdjust {
            selectedDestination = .adjust(id)
        } else {
            selectedDestination = .compare(id)
        }
    }

    private func isSelectable(_ item: ProcessedItem) -> Bool {
        item.processedImageURL != nil && item.status != .failed
    }

    private func toggleSelection(for id: UUID) {
        guard let item = item(for: id), isSelectable(item) else { return }

        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func initializeSelectionIfNeeded(with items: [ProcessedItem]) {
        guard !hasInitializedSelection else { return }

        selectedIDs = Set(
            items
                .filter { $0.status == .auto && $0.processedImageURL != nil }
                .map(\.id)
        )
        previousStatusByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.status) })
        hasInitializedSelection = true
    }

    private func syncSelection(with items: [ProcessedItem]) {
        initializeSelectionIfNeeded(with: items)

        let currentIDs = Set(items.map(\.id))
        selectedIDs.formIntersection(currentIDs)

        for item in items {
            let previous = previousStatusByID[item.id]
            if previous != nil,
               previous != .auto,
               item.status == .auto,
               item.processedImageURL != nil {
                selectedIDs.insert(item.id)
            }
        }

        previousStatusByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.status) })
    }

    private func handleSaveAsNewTap() async {
        let requestedCount = selectedExportableItems.count
        guard requestedCount > 0 else { return }
        guard !presentPaywallIfNeeded(requestedCount: requestedCount, action: .saveAsNew) else { return }
        await runSaveAction(.saveAsNew)
    }

    private func handleReplaceOriginalsTap() async {
        let requestedCount = selectedReplaceableItems.count
        guard requestedCount > 0 else { return }
        guard !presentPaywallIfNeeded(requestedCount: requestedCount, action: .replaceOriginals) else { return }
        await runSaveAction(.replaceOriginals)
    }

    private func runSaveAction(_ action: SaveAction) async {
        let savedCount: Int
        switch action {
        case .saveAsNew:
            savedCount = await resultsViewModel.saveAsNewImages(from: selectedExportableItems)
        case .replaceOriginals:
            savedCount = await resultsViewModel.replaceOriginals(with: selectedReplaceableItems)
        }
        let actionName: String
        switch action { case .saveAsNew: actionName = "saveAsNew"; case .replaceOriginals: actionName = "replace" }
        registerFreeSaveUsage(savedCount)
    }

    private func presentPaywallIfNeeded(requestedCount: Int, action: SaveAction) -> Bool {
        guard !purchaseManager.isUnlocked else { return false }
        refreshRemainingFreeSaves()
        guard requestedCount > remainingFreeSaves else { return false }

        pendingSaveAction = action
        paywallRequestedCount = requestedCount
        showPaywall = true
        return true
    }

    private func registerFreeSaveUsage(_ count: Int) {
        guard count > 0, !purchaseManager.isUnlocked else { return }
        freeSaveCounter.consumeSaves(count)
        refreshRemainingFreeSaves()
    }

    private func refreshRemainingFreeSaves() {
        remainingFreeSaves = freeSaveCounter.remainingFreeSaves
    }

    private func clearPendingPaywallState() {
        pendingSaveAction = nil
        paywallRequestedCount = 0
        refreshRemainingFreeSaves()
    }


    private func retryItem(id: UUID) async {
        guard let index = processingViewModel.processedItems.firstIndex(where: { $0.id == id }) else { return }
        var item = processingViewModel.processedItems[index]
        guard !retryingIDs.contains(id) else { return }
        retryingIDs.insert(id)
        defer { retryingIDs.remove(id) }

        let retrySettings = ProcessingSettings(enhanceReadability: true, quality: .best)
        let updated: ProcessedItem

        if let dataURL = item.sourceImageURL,
           let data = try? Data(contentsOf: dataURL) {
            updated = await retryService.processImageData(
                data,
                sourceIdentifier: item.assetIdentifier,
                settings: retrySettings,
                fallbackThumbnail: item.originalThumbnail
            )
        } else {
            updated = await retryService.processAsset(
                assetIdentifier: item.assetIdentifier,
                settings: retrySettings,
                fallbackThumbnail: item.originalThumbnail
            )
        }

        var merged = updated
        merged.id = item.id
        processingViewModel.processedItems[index] = merged

        if merged.processedImageURL != nil && merged.status != .failed {
            selectedIDs.insert(merged.id)
            resultsViewModel.toastMessage = "Retry succeeded for one item."
        } else {
            resultsViewModel.toastMessage = "Retry still failed. Try Adjust Crop for manual recovery."
        }
    }

    private func item(for id: UUID) -> ProcessedItem? {
        processingViewModel.processedItems.first(where: { $0.id == id })
    }

    private func binding(for id: UUID) -> Binding<ProcessedItem>? {
        guard let index = processingViewModel.processedItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: { processingViewModel.processedItems[index] },
            set: { processingViewModel.processedItems[index] = $0 }
        )
    }
}
