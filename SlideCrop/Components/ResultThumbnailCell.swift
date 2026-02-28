import SwiftUI

struct ResultThumbnailCell: View {
    let item: ProcessedItem
    let isSelected: Bool

    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image = item.processedThumbnail ?? item.originalThumbnail {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.58))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isSelected ? SlideCropTheme.tint : Color.white.opacity(0.45),
                            lineWidth: 2.2
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

            }

            if item.status != .auto {
                Text("Confidence \(Int(item.confidenceScore * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.96)
        .animation(.easeOut(duration: 0.28), value: isVisible)
        .onAppear {
            isVisible = true
        }
    }
}
