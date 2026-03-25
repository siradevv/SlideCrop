import SwiftUI

struct ShareView: View {
    @ObservedObject var viewModel: ShareProcessingViewModel
    let onDone: () -> Void
    let onCancel: () -> Void

    @State private var hasSaved = false

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.isProcessing {
                    progressContent
                } else if viewModel.processedItems.isEmpty {
                    ContentUnavailableView(
                        "No Images",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("No images were found in the shared content.")
                    )
                } else {
                    resultsContent
                }

                if viewModel.isSaving {
                    ProgressView("Saving...")
                        .padding(18)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("SlideCrop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasSaved {
                        Button("Done") { onDone() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("SlideCrop", isPresented: Binding(
                get: { viewModel.toastMessage != nil },
                set: { if !$0 { viewModel.toastMessage = nil } }
            )) {
                Button("OK") { viewModel.toastMessage = nil }
            } message: {
                Text(viewModel.toastMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(viewModel.processedCount), total: Double(max(1, viewModel.totalCount)))
                .tint(.indigo)
                .frame(maxWidth: 260)

            Text("Processing \(viewModel.processedCount) of \(viewModel.totalCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                let saveableCount = viewModel.processedItems.filter({ $0.processedImageURL != nil && $0.status != .failed }).count
                let failedCount = viewModel.processedItems.filter({ $0.status == .failed }).count

                HStack(spacing: 10) {
                    Label("\(saveableCount) ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if failedCount > 0 {
                        Label("\(failedCount) failed", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(viewModel.processedItems) { item in
                        shareResultCell(item: item)
                    }
                }
                .padding(.horizontal, 16)

                if !hasSaved {
                    Button {
                        Task {
                            let count = await viewModel.saveAll()
                            if count > 0 { hasSaved = true }
                        }
                    } label: {
                        Text("Save All to Photos")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(saveableCount == 0 || viewModel.isSaving)
                    .padding(.horizontal, 16)
                } else {
                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private func shareResultCell(item: ProcessedItem) -> some View {
        VStack(spacing: 4) {
            if let thumbnail = item.processedThumbnail ?? item.originalThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(item.status == .failed ? .red : item.status == .review ? .orange : .green)
                    .frame(width: 8, height: 8)
                Text(item.status == .failed ? "Failed" : "\(Int(item.confidenceScore * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
