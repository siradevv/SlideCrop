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
    @State private var isReorderMode = false
    @State private var pdfURL: URL?
    @State private var showingPDFPreview = false
    @State private var isExportingPDF = false
    @State private var showingLayoutPicker = false
    @State private var pdfExportNeedsConsume = false
    @State private var pendingPDFLayout: PDFLayout?
    @State private var pendingPDFOrientation: PDFOrientation?

    private let retryService = SlideCropService()

    private let freeSaveCounter = FreeSaveCounter()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        Group {
            if isReorderMode {
                reorderListView
            } else {
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
            }
        }
        .background(SlideCropPageBackground())
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isReorderMode.toggle()
                    }
                } label: {
                    Image(systemName: isReorderMode ? "square.grid.2x2" : "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isReorderMode ? SlideCropTheme.tint : .white)
                }
                .accessibilityLabel(isReorderMode ? "Switch to grid view" : "Reorder items")
            }
        }
        .overlay {
            if resultsViewModel.isSaving {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView(resultsViewModel.saveProgressTotal > 0
                                 ? "Saving \(resultsViewModel.saveProgressCurrent) of \(resultsViewModel.saveProgressTotal)"
                                 : "Saving")
                        .padding(18)
                        .slideCropCard(cornerRadius: 16)
                }
            } else if isExportingPDF {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Generating PDF…")
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
        .sheet(isPresented: $showingPDFPreview, onDismiss: cleanupPDFExport) {
            if let pdfURL {
                PDFPreviewView(pdfURL: pdfURL) { completed in
                    if completed && pdfExportNeedsConsume {
                        freeSaveCounter.consumePDFExport()
                        pdfExportNeedsConsume = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingLayoutPicker) {
            PDFLayoutPickerView { layout, orientation in
                showingLayoutPicker = false
                pendingPDFLayout = layout
                pendingPDFOrientation = orientation
            }
            .presentationDetents([.height(360)])
        }
        .onChange(of: showingLayoutPicker) { _, showing in
            guard !showing else { return }
            guard let layout = pendingPDFLayout,
                  let orientation = pendingPDFOrientation else {
                pendingPDFLayout = nil
                pendingPDFOrientation = nil
                return
            }
            pendingPDFLayout = nil
            pendingPDFOrientation = nil
            Task { await handlePDFExport(layout: layout, orientation: orientation) }
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

    private struct CategorizedItems {
        var readyIDs: [UUID] = []
        var reviewIDs: [UUID] = []
        var failedIDs: [UUID] = []
        var exportable: [ProcessedItem] = []
        var replaceable: [ProcessedItem] = []
        var selectedExportable: [ProcessedItem] = []
        var selectedReplaceable: [ProcessedItem] = []
    }

    private var categorized: CategorizedItems {
        var result = CategorizedItems()
        for item in processingViewModel.processedItems {
            switch item.status {
            case .auto:
                result.readyIDs.append(item.id)
            case .review:
                result.reviewIDs.append(item.id)
            case .failed:
                result.failedIDs.append(item.id)
            }

            if item.status != .failed, item.processedImageURL != nil {
                result.exportable.append(item)
                if item.canReplaceOriginal {
                    result.replaceable.append(item)
                }
                if selectedIDs.contains(item.id) {
                    result.selectedExportable.append(item)
                    if item.canReplaceOriginal {
                        result.selectedReplaceable.append(item)
                    }
                }
            }
        }
        return result
    }

    private var readyItems: [UUID] { categorized.readyIDs }
    private var needsReviewItems: [UUID] { categorized.reviewIDs }
    private var failedItems: [UUID] { categorized.failedIDs }
    private var failedItemsCount: Int { categorized.failedIDs.count }
    private var selectedExportableItems: [ProcessedItem] { categorized.selectedExportable }
    private var selectedReplaceableItems: [ProcessedItem] { categorized.selectedReplaceable }
    private var replaceBlockedCount: Int { categorized.selectedExportable.count - categorized.selectedReplaceable.count }

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

            Text(needsReviewItems.isEmpty && failedItemsCount == 0 ? "Looks good. You can save now." : "Please review flagged items before saving.")
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

                Button(replaceBlockedCount > 0
                       ? "Replace \(selectedReplaceableItems.count) Original\(selectedReplaceableItems.count == 1 ? "" : "s")"
                       : "Replace Originals") {
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
                Text("\(replaceBlockedCount) of \(selectedExportableItems.count) selected can't replace originals (imported via camera or file picker). Use Save as New for those.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                if !purchaseManager.isUnlocked {
                    pendingSaveAction = nil
                    paywallRequestedCount = 0
                    showPaywall = true
                } else {
                    showingLayoutPicker = true
                }
            } label: {
                HStack(spacing: 6) {
                    if isExportingPDF {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "doc.richtext")
                    }
                    Text("Export as PDF")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(selectedExportableItems.isEmpty || isExportingPDF || resultsViewModel.isSaving)

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
                                if item.canManualAdjust, item.cropQuad != nil {
                                    Button(item.isEnhanced ? "Remove Enhancement" : "Apply Enhancement",
                                           systemImage: item.isEnhanced ? "wand.and.rays.inverse" : "wand.and.rays") {
                                        Task { await toggleEnhance(id: id) }
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
                            .accessibilityLabel(selectedIDs.contains(id) ? "Selected, tap to deselect" : "Not selected, tap to select")
                            .padding(8)
                            .disabled(!isSelectable(item))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var reorderListView: some View {
        List {
            Section {
                ForEach(processingViewModel.processedItems) { item in
                    reorderRow(item: item)
                }
                .onMove { source, destination in
                    processingViewModel.moveItem(from: source, to: destination)
                }
            } header: {
                Text("Drag to reorder items before saving")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func reorderRow(item: ProcessedItem) -> some View {
        HStack(spacing: 12) {
            if let thumbnail = item.processedThumbnail ?? item.originalThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.status.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor(for: item.status))

                if item.confidenceScore > 0 {
                    Text("\(Int(item.confidenceScore * 100))% confidence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if selectedIDs.contains(item.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SlideCropTheme.tint)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func statusColor(for status: ProcessedStatus) -> Color {
        switch status {
        case .auto: return SlideCropTheme.readyBadge
        case .review: return SlideCropTheme.reviewBadge
        case .failed: return SlideCropTheme.failedBadge
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
        HapticService.lightImpact()
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
        guard !resultsViewModel.isSaving else { return }
        let savedCount: Int
        switch action {
        case .saveAsNew:
            savedCount = await resultsViewModel.saveAsNewImages(from: selectedExportableItems)
        case .replaceOriginals:
            savedCount = await resultsViewModel.replaceOriginals(with: selectedReplaceableItems)
        }
        registerFreeSaveUsage(savedCount)
        if savedCount > 0 {
            HapticService.successNotification()
        }
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

    private func cleanupPDFExport() {
        pdfExportNeedsConsume = false
        guard let pdfURL else { return }
        try? FileManager.default.removeItem(at: pdfURL)
        self.pdfURL = nil
    }

    private func handlePDFExport(layout: PDFLayout, orientation: PDFOrientation) async {
        let items = selectedExportableItems
        guard !items.isEmpty else { return }

        isExportingPDF = true
        defer { isExportingPDF = false }

        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try PDFExportService.exportPDF(from: items, layout: layout, orientation: orientation)
            }.value
            pdfURL = url
            pdfExportNeedsConsume = !purchaseManager.isUnlocked
            showingPDFPreview = true
            HapticService.successNotification()
        } catch {
            resultsViewModel.toastMessage = "PDF export failed: \(error.localizedDescription)"
            HapticService.errorNotification()
        }
    }

    private func retryItem(id: UUID) async {
        guard let index = processingViewModel.processedItems.firstIndex(where: { $0.id == id }) else { return }
        let item = processingViewModel.processedItems[index]
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
            HapticService.successNotification()
        } else {
            resultsViewModel.toastMessage = "Retry still failed. Try Adjust Crop for manual recovery."
            HapticService.errorNotification()
        }
    }

    private func toggleEnhance(id: UUID) async {
        guard let index = processingViewModel.processedItems.firstIndex(where: { $0.id == id }) else { return }
        let item = processingViewModel.processedItems[index]
        guard let quad = item.cropQuad, !retryingIDs.contains(id) else { return }

        retryingIDs.insert(id)
        defer { retryingIDs.remove(id) }

        let newSettings = ProcessingSettings(enhanceReadability: !item.isEnhanced, quality: .best)
        do {
            let updated = try await retryService.processManualAdjustment(
                assetIdentifier: item.assetIdentifier,
                sourceImageURL: item.sourceImageURL,
                quad: quad,
                settings: newSettings,
                originalThumbnail: item.originalThumbnail,
                canReplaceOriginal: item.canReplaceOriginal,
                canManualAdjust: item.canManualAdjust
            )
            var merged = updated
            merged.id = item.id
            processingViewModel.processedItems[index] = merged
            HapticService.successNotification()
        } catch {
            resultsViewModel.toastMessage = "Enhancement toggle failed: \(error.localizedDescription)"
            HapticService.errorNotification()
        }
    }

    private func item(for id: UUID) -> ProcessedItem? {
        processingViewModel.processedItems.first(where: { $0.id == id })
    }

    private func binding(for id: UUID) -> Binding<ProcessedItem>? {
        guard processingViewModel.processedItems.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                processingViewModel.processedItems.first(where: { $0.id == id })
                    ?? ProcessedItem(assetIdentifier: "", originalThumbnail: nil, processedThumbnail: nil, sourceImageURL: nil, processedImageURL: nil, confidenceScore: 0, status: .failed, cropQuad: nil, errorMessage: nil, canReplaceOriginal: false, canManualAdjust: false)
            },
            set: { newValue in
                if let idx = processingViewModel.processedItems.firstIndex(where: { $0.id == id }) {
                    processingViewModel.processedItems[idx] = newValue
                }
            }
        )
    }
}

private struct PDFLayoutPickerView: View {
    let onSelect: (PDFLayout, PDFOrientation) -> Void

    @State private var orientation: PDFOrientation = .portrait

    var body: some View {
        VStack(spacing: 20) {
            Text("PDF Layout")
                .font(.title3.weight(.semibold))
                .padding(.top, 20)

            Picker("Orientation", selection: $orientation) {
                ForEach(PDFOrientation.allCases) { o in
                    Label(o.rawValue, systemImage: o.iconName)
                        .tag(o)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(PDFLayout.allCases) { layout in
                    Button {
                        HapticService.lightImpact()
                        onSelect(layout, orientation)
                    } label: {
                        VStack(spacing: 8) {
                            layoutPreview(layout)
                                .frame(width: previewWidth, height: previewHeight)
                            Text(layout.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .slideCropCard(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private var previewWidth: CGFloat {
        orientation == .landscape ? 72 : 56
    }

    private var previewHeight: CGFloat {
        orientation == .landscape ? 50 : 72
    }

    @ViewBuilder
    private func layoutPreview(_ layout: PDFLayout) -> some View {
        let cols = layout.columns
        let rows = layout.rows
        let spacing: CGFloat = 4

        GeometryReader { geo in
            let totalHSpacing = spacing * CGFloat(cols - 1)
            let totalVSpacing = spacing * CGFloat(rows - 1)
            let cellW = (geo.size.width - totalHSpacing) / CGFloat(cols)
            let cellH = (geo.size.height - totalVSpacing) / CGFloat(rows)

            ForEach(0..<(cols * rows), id: \.self) { index in
                let col = index % cols
                let row = index / cols
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(SlideCropTheme.tint.opacity(0.35))
                    .frame(width: cellW, height: cellH)
                    .position(
                        x: CGFloat(col) * (cellW + spacing) + cellW / 2,
                        y: CGFloat(row) * (cellH + spacing) + cellH / 2
                    )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
