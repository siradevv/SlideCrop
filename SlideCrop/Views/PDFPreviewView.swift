import SwiftUI
import PDFKit

struct PDFPreviewView: View {
    let pdfURL: URL
    let onExportCompleted: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            PDFKitView(url: pdfURL)
                .ignoresSafeArea(edges: .bottom)
                .background(SlideCropPageBackground())
                .navigationTitle("PDF Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(SlideCropTheme.tint)
                    }
                }
                .sheet(isPresented: $showingShareSheet) {
                    ActivityViewController(activityItems: [pdfURL]) { completed in
                        onExportCompleted(completed)
                    }
                }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        pdfView.backgroundColor = .clear
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
