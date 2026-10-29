@preconcurrency import CloudKit
import Foundation
import UIKit

/// Holds a share invitation whose acceptance would replace the current partner,
/// until the user confirms or cancels in the UI. Kept in memory only: scene
/// delegates re-deliver the metadata on cold start.
@MainActor
enum ShareCalPendingShareReplacement {
    private(set) static var metadata: CKShare.Metadata?
    private(set) static var incomingOwnerID: String?

    static func store(metadata: CKShare.Metadata, incomingOwnerID: String) {
        self.metadata = metadata
        self.incomingOwnerID = incomingOwnerID
    }

    static func consume() -> (metadata: CKShare.Metadata, incomingOwnerID: String)? {
        guard let metadata, let incomingOwnerID else { return nil }
        clear()
        return (metadata, incomingOwnerID)
    }

    static func clear() {
        metadata = nil
        incomingOwnerID = nil
    }
}

enum ShareCalCloudKitShareAcceptanceHandler {
    static func handle(metadata: CKShare.Metadata) {
        let incomingOwnerID = metadata.share.recordID.zoneID.ownerName
        if ShareAcceptanceGuardPolicy.requiresReplacementConfirmation(
            incomingOwnerID: incomingOwnerID,
            storedPartnerID: SettingsStore.storedPartnerShareOwnerID(),
            outgoingParticipantIDs: SettingsStore.storedOutgoingShareParticipantIDs()
        ) {
            NSLog("ShareCal deferring CloudKit share acceptance pending replacement confirmation")
            Task { @MainActor in
                ShareCalPendingShareReplacement.store(metadata: metadata, incomingOwnerID: incomingOwnerID)
                NotificationCenter.default.post(name: ShareCalAcceptedShareSignal.notificationName, object: nil)
            }
            return
        }
        accept(metadata: metadata, incomingOwnerID: incomingOwnerID)
    }

    static func accept(metadata: CKShare.Metadata, incomingOwnerID: String) {
        Task { try? await acceptNow(metadata: metadata, incomingOwnerID: incomingOwnerID) }
    }

    /// The UI moves on when this starts and steps back, with the error, if it fails.
    static func acceptNow(metadata: CKShare.Metadata, incomingOwnerID: String) async throws {
        await MainActor.run {
            ShareCalShareAcceptanceProgressSignal.postStarted(ownerID: incomingOwnerID)
        }
        do {
            try await CloudKitCoupleSpaceService().acceptShare(metadata: metadata)
            await MainActor.run {
                ShareCalAcceptedShareSignal.markAccepted(partnerOwnerID: incomingOwnerID)
            }
        } catch {
            NSLog("ShareCal failed to accept CloudKit share: \(error)")
            await MainActor.run {
                ShareCalShareAcceptanceProgressSignal.postFailed(
                    ownerID: incomingOwnerID,
                    message: CloudKitSharingFailureMessage.userFacingMessage(for: error)
                )
            }
            throw error
        }
    }
}

final class ShareCalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata else { return }
        NSLog("ShareCal scene delegate received CloudKit share metadata at connection")
        ShareCalCloudKitShareAcceptanceHandler.handle(metadata: cloudKitShareMetadata)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NSLog("ShareCal scene delegate received CloudKit share metadata")
        ShareCalCloudKitShareAcceptanceHandler.handle(metadata: cloudKitShareMetadata)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // This app uses the UIScene lifecycle, so background transitions land here —
        // NOT on UIApplicationDelegate.applicationDidEnterBackground (never called once
        // a scene delegate exists). Queue the opportunistic BGAppRefresh every time we
        // background so partner data keeps catching up when silent pushes are throttled
        // or dropped (notifications decision 0002).
        Task { @MainActor in
            ShareCalBackgroundSyncRunner.shared.scheduleAppRefresh()
        }
    }
}

enum ShareCalSceneDelegateConfigurationPolicy {
    static let configurationName = "Default Configuration"
    static let acceptsColdStartShareMetadata = true

    static var sceneDelegateClass: AnyClass {
        ShareCalSceneDelegate.self
    }
}
