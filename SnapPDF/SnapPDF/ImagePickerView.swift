import SwiftUI
import AVFoundation

// Passes through all touches except those on subviews (like the flash button)
private class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImageCaptured: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator

        if sourceType == .camera {
            picker.cameraCaptureMode = .photo
            picker.cameraFlashMode = .auto

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                context.coordinator.addFlashButton(to: picker)
            }
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        private var flashButton: UIButton?
        private var currentFlashMode: UIImagePickerController.CameraFlashMode = .auto

        init(_ parent: ImagePickerView) { self.parent = parent }

        func addFlashButton(to picker: UIImagePickerController) {
            guard picker.sourceType == .camera else { return }

            let button = UIButton(type: .system)
            button.setImage(flashIcon(for: .auto), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            button.layer.cornerRadius = 22
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(toggleFlash(_:)), for: .touchUpInside)

            let overlay = PassthroughView(frame: picker.view.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.backgroundColor = .clear
            overlay.addSubview(button)
            picker.cameraOverlayView = overlay

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44),
                button.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 12),
                button.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 16)
            ])

            flashButton = button
        }

        @objc private func toggleFlash(_ sender: UIButton) {
            switch currentFlashMode {
            case .auto: currentFlashMode = .on
            case .on:   currentFlashMode = .off
            case .off:  currentFlashMode = .auto
            @unknown default: currentFlashMode = .auto
            }

            sender.setImage(flashIcon(for: currentFlashMode), for: .normal)

            if let picker = sender.window?.rootViewController?.presentedViewController as? UIImagePickerController {
                picker.cameraFlashMode = currentFlashMode
            }

            toggleTorch(on: currentFlashMode == .on)
        }

        private func flashIcon(for mode: UIImagePickerController.CameraFlashMode) -> UIImage? {
            let name: String
            switch mode {
            case .auto: name = "bolt.badge.automatic.fill"
            case .on:   name = "bolt.fill"
            case .off:  name = "bolt.slash.fill"
            @unknown default: name = "bolt.badge.automatic.fill"
            }
            return UIImage(systemName: name)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        }

        private func toggleTorch(on: Bool) {
            guard let device = AVCaptureDevice.default(for: .video),
                  device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            toggleTorch(on: false)
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image.fixOrientation())
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            toggleTorch(on: false)
            parent.onCancel()
        }
    }
}
