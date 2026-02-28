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

struct ResultsView: View {
    @ObservedObject var processingViewModel: ProcessingViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @StateObject private var resultsViewModel = ResultsViewModel()

    @State private var selectedDestination: ResultDestination?
    @State private var showSaveAlert = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var hasInitializedSelection = false
    @State private var previousStatusByID: [UUID: ProcessedStatus] = [:]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if !readyItems.isEmpty {
                    section(title: "Ready", ids: readyItems)
                }

                if !needsReviewItems.isEmpty {
                    section(title: "Needs Review", ids: needsReviewItems)
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
        .onAppear {
            initializeSelectionIfNeeded(with: processingViewModel.processedItems)
        }
        .onReceive(processingViewModel.$processedItems) { items in
            syncSelection(with: items)
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
            .filter { $0.status != .auto }
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

    @ViewBuilder
    private var actionPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SlideCropTheme.tint)
                Text("\(selectedExportableItems.count) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Save as New Images") {
                    Task {
                        await resultsViewModel.saveAsNewImages(from: selectedExportableItems)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SlideCropTheme.tint)
                .disabled(resultsViewModel.isSaving || selectedExportableItems.isEmpty)
                .frame(maxWidth: .infinity)

                Button("Replace Originals") {
                    Task {
                        await resultsViewModel.replaceOriginals(with: selectedReplaceableItems)
                    }
                }
                .buttonStyle(.bordered)
                .tint(SlideCropTheme.tint.opacity(0.85))
                .disabled(resultsViewModel.isSaving || selectedReplaceableItems.isEmpty)
                .frame(maxWidth: .infinity)
            }

            if selectedExportableItems.count > selectedReplaceableItems.count {
                Text("Some selected images can be saved as new but cannot replace originals because they were imported without direct Photo Library linkage.")
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
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

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
