import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Explicit UIKit document picker for read-only archive inspection.
///
/// SwiftUI fileImporter on iOS 27 beta can leave a tapped file selected
/// without completing the callback. Keep the diagnostic delegate path
/// isolated so we can distinguish a SwiftUI presentation failure from a
/// platform File Provider problem on the user's device.
struct TropLibraryV2DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Import-by-copy: no need to modify a provider-owned original.
        // The archive is validated by content, not by its extension.
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data],
            asCopy: true
        )
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            Log.libraryView.info("V2_FILE_IMPORTER UIKit delegate received selection")
            guard let file = urls.first else {
                onCancel()
                return
            }
            onPick(file)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            Log.libraryView.info("V2_FILE_IMPORTER UIKit cancel received")
            onCancel()
        }
    }
}
