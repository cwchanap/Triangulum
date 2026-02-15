//
//  ImagePicker.swift
//  Triangulum
//
//  Extracted from ContentView.swift
//

import SwiftUI
import UIKit

// MARK: - ImagePicker Component
struct ImagePicker: UIViewControllerRepresentable {
    enum SourceType {
        case camera
        case photoLibrary

        var uiImagePickerSourceType: UIImagePickerController.SourceType {
            switch self {
            case .camera:
                return .camera
            case .photoLibrary:
                return .photoLibrary
            }
        }
    }

    let sourceType: SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType.uiImagePickerSourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
