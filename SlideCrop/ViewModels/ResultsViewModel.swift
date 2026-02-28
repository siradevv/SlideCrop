import Foundation

@MainActor
final class ResultsViewModel: ObservableObject {
    @Published private(set) var isSaving = false
    @Published var toastMessage: String?

    private let photoLibraryService: PhotoLibraryService

    init(photoLibraryService: PhotoLibraryService = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }

    func saveAsNewImages(from items: [ProcessedItem]) async {
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await photoLibraryService.saveNewImages(items: items.filter { $0.status != .failed })
            toastMessage = "Saved as new images."
        } catch {
            toastMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func replaceOriginals(with items: [ProcessedItem]) async {
        guard !isSaving else { return }

        let replaceLinkedItems = items.filter { $0.status != .failed && $0.canReplaceOriginal }
        guard !replaceLinkedItems.isEmpty else {
            toastMessage = "These selections were imported without direct Photo Library linkage, so originals cannot be replaced. Re-select from Photos with Full Access."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let replacedCount = try await photoLibraryService.replaceOriginalImages(
                items: replaceLinkedItems
            )
            if replacedCount == 0 {
                toastMessage = "No replaceable originals found. Re-select photos from the library and ensure full Photos access."
            } else {
                toastMessage = "Replaced originals with reversible edits."
            }
        } catch {
            toastMessage = "Replace failed: \(error.localizedDescription)"
        }
    }
}
