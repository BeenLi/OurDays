@preconcurrency import CloudKit
import SwiftUI
import UIKit

struct CloudSharingController: UIViewControllerRepresentable {
    let preparedShare: PreparedCloudShare
    let onError: (String) -> Void
    var onSavedShare: (CKShare) -> Void = { _ in }
    let onStoppedSharing: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        cloudKitSharingInfo("CloudSharingController presenting active share=\(preparedShare.share.recordID.recordName)")
        let controller = UICloudSharingController(share: preparedShare.share, container: preparedShare.container)
        controller.availablePermissions = CloudKitSharePermissionPolicy.controllerAvailablePermissions(for: preparedShare.share)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, onSavedShare: onSavedShare, onStoppedSharing: onStoppedSharing)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onError: (String) -> Void
        let onSavedShare: (CKShare) -> Void
        let onStoppedSharing: () -> Void

        init(
            onError: @escaping (String) -> Void,
            onSavedShare: @escaping (CKShare) -> Void,
            onStoppedSharing: @escaping () -> Void
        ) {
            self.onError = onError
            self.onSavedShare = onSavedShare
            self.onStoppedSharing = onStoppedSharing
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            cloudKitSharingError("UICloudSharingController delegate failedToSaveShare error=\(describeCloudKitFailure(error))")
            onError(CloudKitSharingFailureMessage.userFacingMessage(for: error))
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            cloudKitSharingInfo("UICloudSharingController delegate didSaveShare participants=\(csc.share?.participants.count ?? 0)")
            if let share = csc.share { onSavedShare(share) }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            cloudKitSharingInfo("UICloudSharingController delegate didStopSharing")
            onStoppedSharing()
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "OurDays"
        }
    }
}
