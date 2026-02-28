import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum HomeRoute: Hashable {
    case processing
    case results
}

struct HomeView: View {
    @StateObject private var processingViewModel = ProcessingViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()

    @State private var showingPhotoPicker = false
    @State private var navigationPath: [HomeRoute] = []
    @State private var showingSettings = false
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined

    private let photoLibraryService = PhotoLibraryService()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                SlideCropPageBackground()

                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    HeroCropIconView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        Text("SlideCrop")
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Automatically detect, straighten, and clean presentation slides from your photos.")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Button {
                        Task {
                            await requestAccessThenPresentPicker()
                        }
                    } label: {
                        Label("Select Photos", systemImage: "photo.on.rectangle.angled")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(SlideCropTheme.primaryButtonGradient)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            )
                            .shadow(color: SlideCropTheme.indigo.opacity(0.24), radius: 14, y: 8)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .padding(.horizontal, 24)

                    if authorizationStatus == .limited {
                        Button("Manage Limited Library Access") {
                            Task { @MainActor in
                                photoLibraryService.presentLimitedLibraryPicker()
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.5), in: Capsule())
                    }

                    Spacer(minLength: 18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Photo Access Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    openAppSettings()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(permissionMessage)
            }
            .onAppear {
                authorizationStatus = photoLibraryService.currentAuthorizationStatus()
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoLibraryPickerView(
                    selectionLimit: 0,
                    onComplete: { inputs in
                        showingPhotoPicker = false
                        Task {
                            await beginProcessing(with: inputs)
                        }
                    },
                    onCancel: {
                        showingPhotoPicker = false
                    }
                )
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .processing:
                    ProcessingView(
                        viewModel: processingViewModel,
                        onFinished: {
                            guard navigationPath.last == .processing else { return }
                            navigationPath = [.results]
                        },
                        onCancel: {
                            navigationPath.removeAll()
                        }
                    )
                case .results:
                    ResultsView(
                        processingViewModel: processingViewModel,
                        settingsViewModel: settingsViewModel
                    )
                }
            }
        }
    }

    private func beginProcessing(with items: [SelectedPhotoInput]) async {
        guard !items.isEmpty else { return }

        let status = await photoLibraryService.requestReadWriteAccess()
        await MainActor.run {
            authorizationStatus = status
        }

        guard status == .authorized || status == .limited else {
            await MainActor.run {
                permissionMessage = "Allow Photos access to process slides and save edited outputs."
                showPermissionAlert = true
            }
            return
        }

        await MainActor.run {
            processingViewModel.startProcessing(
                selectedPhotos: items,
                settings: settingsViewModel.currentSettings()
            )
            navigationPath = [.processing]
        }
    }

    private func requestAccessThenPresentPicker() async {
        let status = await photoLibraryService.requestReadWriteAccess()
        await MainActor.run {
            authorizationStatus = status
        }

        guard status == .authorized || status == .limited else {
            await MainActor.run {
                permissionMessage = "Allow Photos access to process slides and replace originals."
                showPermissionAlert = true
            }
            return
        }

        await MainActor.run {
            showingPhotoPicker = true
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

struct SelectedPhotoInput {
    let assetIdentifier: String?
    let itemProvider: NSItemProvider?
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onComplete: ([SelectedPhotoInput]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoLibraryPickerView

        init(parent: PhotoLibraryPickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.onCancel()
                return
            }

            Task {
                var selected: [SelectedPhotoInput] = []
                selected.reserveCapacity(results.count)

                for result in results {
                    if let identifier = result.assetIdentifier {
                        selected.append(
                            SelectedPhotoInput(assetIdentifier: identifier, itemProvider: nil)
                        )
                        continue
                    }

                    guard result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                        continue
                    }
                    selected.append(
                        SelectedPhotoInput(assetIdentifier: nil, itemProvider: result.itemProvider)
                    )
                }

                await MainActor.run {
                    if selected.isEmpty {
                        self.parent.onCancel()
                    } else {
                        self.parent.onComplete(selected)
                    }
                }
            }
        }
    }
}
