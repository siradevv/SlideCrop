import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AVFoundation

private enum HomeRoute: Hashable {
    case processing
    case results
}

private enum AccessAlertAction {
    case none
    case openSettings
    case manageLimitedAccess
}

struct HomeView: View {
    @StateObject private var processingViewModel = ProcessingViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()

    @State private var showingPhotoPicker = false
    @State private var showingCameraPicker = false
    @State private var navigationPath: [HomeRoute] = []
    @State private var showingSettings = false
    @State private var showPermissionAlert = false
    @State private var permissionAlertTitle = "Access Required"
    @State private var permissionAlertAction: AccessAlertAction = .none
    @State private var permissionMessage = ""
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var presenterViewController: UIViewController?

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

                    Button {
                        Task {
                            await requestCameraAccessThenPresentCamera()
                        }
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .padding(.horizontal, 24)

                    if authorizationStatus == .limited {
                        Button("Manage Limited Library Access") {
                            Task {
                                await MainActor.run {
                                    presentLimitedLibraryPicker()
                                }
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
                .background(
                    PhotoLibraryPresenter { controller in
                        if presenterViewController !== controller {
                            presenterViewController = controller
                        }
                    }
                    .frame(width: 0, height: 0)
                )
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
            .alert(permissionAlertTitle, isPresented: $showPermissionAlert) {
                if permissionAlertAction == .openSettings {
                    Button("Open Settings") {
                        openAppSettings()
                    }
                }
                if permissionAlertAction == .manageLimitedAccess {
                    Button("Manage Access") {
                        presentLimitedLibraryPicker()
                    }
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
                    },
                    onImportFailure: {
                        showingPhotoPicker = false
                        Task {
                            await handlePickerImportFailure()
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showingCameraPicker) {
                CameraCaptureView(
                    onCapture: { input in
                        showingCameraPicker = false
                        Task {
                            await beginProcessing(with: [input])
                        }
                    },
                    onCancel: {
                        showingCameraPicker = false
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

        let status = await resolvePhotoLibraryStatus()
        await MainActor.run {
            authorizationStatus = status
        }

        guard status == .authorized || status == .limited else {
            await MainActor.run {
                presentSettingsAccessAlert(
                    message: "Allow Photos access to process slides and save edited outputs."
                )
            }
            return
        }

        let hasInaccessibleAsset = items.contains { input in
            guard let identifier = input.assetIdentifier else { return false }
            return !photoLibraryService.canAccessAsset(with: identifier)
        }

        if hasInaccessibleAsset {
            await handlePickerImportFailure()
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
        let status = await resolvePhotoLibraryStatus()
        await MainActor.run {
            authorizationStatus = status
        }

        guard status == .authorized || status == .limited else {
            await MainActor.run {
                presentSettingsAccessAlert(
                    message: "Allow Photos access to import photos."
                )
            }
            return
        }

        await MainActor.run {
            showingPhotoPicker = true
        }
    }

    private func requestCameraAccessThenPresentCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            await MainActor.run {
                presentAccessAlert(
                    title: "Camera Unavailable",
                    message: "This device does not have an available camera.",
                    action: .none
                )
            }
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            await MainActor.run {
                showingCameraPicker = true
            }
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }

            if granted {
                await MainActor.run {
                    showingCameraPicker = true
                }
            } else {
                await MainActor.run {
                    presentAccessAlert(
                        title: "Camera Access Required",
                        message: "Allow Camera access in Settings to take photos for slide processing.",
                        action: .openSettings
                    )
                }
            }
        case .denied, .restricted:
            await MainActor.run {
                presentAccessAlert(
                    title: "Camera Access Required",
                    message: "Allow Camera access in Settings to take photos for slide processing.",
                    action: .openSettings
                )
            }
        @unknown default:
            await MainActor.run {
                presentAccessAlert(
                    title: "Camera Access Required",
                    message: "Unable to access the camera right now. Please try again.",
                    action: .none
                )
            }
        }
    }

    private func resolvePhotoLibraryStatus() async -> PHAuthorizationStatus {
        let current = photoLibraryService.currentAuthorizationStatus()
        guard current == .notDetermined else {
            return current
        }
        return await photoLibraryService.requestReadWriteAccess()
    }

    private func handlePickerImportFailure() async {
        let status = photoLibraryService.currentAuthorizationStatus()
        await MainActor.run {
            authorizationStatus = status
            switch status {
            case .limited:
                presentAccessAlert(
                    title: "Limited Photo Access",
                    message: "SlideCrop only has access to selected photos. Allow access to more photos?",
                    action: .manageLimitedAccess
                )
            case .denied, .restricted:
                presentSettingsAccessAlert(
                    message: "SlideCrop can't access that photo. Open Settings to allow Photos access."
                )
            case .authorized:
                presentAccessAlert(
                    title: "Import Failed",
                    message: "SlideCrop couldn't import one or more selected photos. Please try again.",
                    action: .none
                )
            case .notDetermined:
                presentSettingsAccessAlert(
                    message: "SlideCrop needs Photos access to import this image."
                )
            @unknown default:
                presentAccessAlert(
                    title: "Import Failed",
                    message: "SlideCrop couldn't import the selected photo.",
                    action: .none
                )
            }
        }
    }

    @MainActor
    private func presentLimitedLibraryPicker() {
        guard let presenterViewController else {
            return
        }
        photoLibraryService.presentLimitedLibraryPicker(from: presenterViewController)
    }

    @MainActor
    private func presentSettingsAccessAlert(message: String) {
        presentAccessAlert(
            title: "Photo Access Required",
            message: message,
            action: .openSettings
        )
    }

    private func presentAccessAlert(title: String, message: String, action: AccessAlertAction) {
        permissionAlertTitle = title
        permissionMessage = message
        permissionAlertAction = action
        showPermissionAlert = true
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
    let imageData: Data?
}

struct PhotoLibraryPresenter: UIViewControllerRepresentable {
    let onResolve: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> ResolverViewController {
        let controller = ResolverViewController()
        controller.onResolve = onResolve
        return controller
    }

    func updateUIViewController(_ uiViewController: ResolverViewController, context: Context) {
        uiViewController.onResolve = onResolve
        DispatchQueue.main.async {
            onResolve(uiViewController)
        }
    }

    final class ResolverViewController: UIViewController {
        var onResolve: ((UIViewController) -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onResolve?(self)
        }
    }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onComplete: ([SelectedPhotoInput]) -> Void
    let onCancel: () -> Void
    let onImportFailure: () -> Void

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
                var importFailureCount = 0

                for result in results {
                    if let identifier = result.assetIdentifier {
                        selected.append(
                            SelectedPhotoInput(assetIdentifier: identifier, itemProvider: nil, imageData: nil)
                        )
                        continue
                    }

                    guard result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                        importFailureCount += 1
                        continue
                    }

                    if let imageData = await Self.loadImageData(from: result.itemProvider) {
                        selected.append(
                            SelectedPhotoInput(assetIdentifier: nil, itemProvider: nil, imageData: imageData)
                        )
                    } else {
                        importFailureCount += 1
                    }
                }

                await MainActor.run {
                    if importFailureCount > 0 {
                        self.parent.onImportFailure()
                    } else if selected.isEmpty {
                        self.parent.onCancel()
                    } else {
                        self.parent.onComplete(selected)
                    }
                }
            }
        }

        private static func loadImageData(from provider: NSItemProvider) async -> Data? {
            await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (SelectedPhotoInput) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }

            let imageData = image.jpegData(compressionQuality: 0.95) ?? image.pngData()
            guard let imageData else {
                parent.onCancel()
                return
            }

            parent.onCapture(
                SelectedPhotoInput(assetIdentifier: nil, itemProvider: nil, imageData: imageData)
            )
        }
    }
}
