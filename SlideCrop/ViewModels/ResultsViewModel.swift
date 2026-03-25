import Foundation

@MainActor
final class ResultsViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var saveProgressCurrent = 0
    @Published private(set) var saveProgressTotal = 0
    @Published var toastMessage: String?

    private let photoLibraryService: PhotoLibraryService

    init(photoLibraryService: PhotoLibraryService = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }

    @discardableResult
    func saveAsNewImages(from items: [ProcessedItem]) async -> Int {
        guard !isSaving else { return 0 }
        let exportableItems = items.filter { $0.status != .failed }
        guard !exportableItems.isEmpty else { return 0 }

        isSaving = true
        saveProgressCurrent = 0
        saveProgressTotal = exportableItems.count
        defer {
            isSaving = false
            saveProgressCurrent = 0
            saveProgressTotal = 0
        }

        do {
            try await photoLibraryService.saveNewImages(items: exportableItems)
            saveProgressCurrent = exportableItems.count
            toastMessage = "Saved \(exportableItems.count) image(s) as new photos."
            return exportableItems.count
        } catch {
            toastMessage = "Save failed: \(error.localizedDescription)"
            return 0
        }
    }

    @discardableResult
    func replaceOriginals(with items: [ProcessedItem]) async -> Int {
        guard !isSaving else { return 0 }

        let replaceLinkedItems = items.filter { $0.status != .failed && $0.canReplaceOriginal }
        guard !replaceLinkedItems.isEmpty else {
            toastMessage = "These selections were imported without direct Photo Library linkage, so originals cannot be replaced. Re-select from Photos with Full Access."
            return 0
        }

        isSaving = true
        saveProgressCurrent = 0
        saveProgressTotal = replaceLinkedItems.count
        defer {
            isSaving = false
            saveProgressCurrent = 0
            saveProgressTotal = 0
        }

        do {
            let replacedCount = try await photoLibraryService.replaceOriginalImages(
                items: replaceLinkedItems,
                onItemCompleted: { [weak self] completed in
                    self?.saveProgressCurrent = completed
                }
            )
            if replacedCount == 0 {
                toastMessage = "No replaceable originals found. Re-select photos from the library and ensure full Photos access."
            } else {
                toastMessage = "Replaced \(replacedCount) original photo(s) with reversible edits."
            }
            return replacedCount
        } catch {
            toastMessage = "Replace failed: \(error.localizedDescription)"
            return 0
        }
    }
}
