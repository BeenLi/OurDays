import BackgroundTasks
import CloudKit
import SwiftUI
import SwiftData
import UIKit
import UserNotifications

final class ShareCalAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // BGTaskScheduler requires the handler be registered before launch finishes.
        // The launch handler fires minutes-to-hours later, by which time the App's
        // init has configured the shared runner (notifications decision 0002).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundRefreshSchedulePlan.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                ShareCalBackgroundSyncRunner.shared.handleAppRefresh(refreshTask)
            }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.trigger is UNPushNotificationTrigger {
            // A generic CloudKit alert arrived while the app is active. Kick off a sync
            // so the rich, per-item local notifications get posted (the scenePhase sync
            // won't fire — the app is already active), then suppress the generic push
            // banner here to avoid a duplicate.
            ShareCalRemoteChangeSignal.notifyChanged()
            completionHandler([])
        } else {
            // Local notifications (our rich per-item ones) present normally in foreground.
            completionHandler([.banner, .list, .sound, .badge])
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: ShareCalSceneDelegateConfigurationPlan.configurationName,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = ShareCalSceneDelegateConfigurationPlan.sceneDelegateClass
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        ShareCalCloudKitShareAcceptanceHandler.handle(metadata: cloudKitShareMetadata)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // CloudKit silent (content-available) push (decision 0002): run the sync to
        // completion right here in the background, then report. The shared runner uses
        // the SAME SettingsStore/AppServices instances as the live UI, so a delivery
        // while the app is foregrounded updates the UI too — no separate signal needed.
        // The pipeline's tail (postPendingNotifications) posts rich local notifications
        // only for comment/invite/access activity, so plain calendar-event changes wake
        // a sync silently without any user-facing banner.
        Task { @MainActor in
            ShareCalBackgroundSyncRunner.shared.scheduleAppRefresh()
            let didRun = await ShareCalBackgroundSyncRunner.shared.runSync()
            completionHandler(didRun ? .newData : .noData)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NSLog("ShareCal registered for remote notifications")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("ShareCal failed to register for remote notifications: \(error)")
    }
}

@MainActor
enum ShareCalNotificationSetup {
    /// Request notification authorization, register for CloudKit silent pushes, and
    /// ensure the database subscriptions exist. No-op when CloudKit is disabled.
    static func configure(services: AppServices) async {
        guard services.isCloudKitEnabled else { return }
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("ShareCal notification authorization error: \(error)")
        }
        UIApplication.shared.registerForRemoteNotifications()
        guard let cloudKit = services.cloudKitIfAvailable else { return }
        do {
            try await cloudKit.configureDatabaseSubscription()
        } catch {
            NSLog("ShareCal subscription setup error: \(error)")
        }
    }
}

@MainActor
enum ShareCalUITestLaunchPlan {
    static let resetUserDefaultsArgument = "--sharecal-reset-user-defaults"

    static func resetUserDefaultsIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard arguments.contains(resetUserDefaultsArgument),
              let bundleIdentifier else {
            return
        }
        defaults.removePersistentDomain(forName: bundleIdentifier)
    }
}

@MainActor
enum ShareCalLaunchDiagnostics {
    static func runIfRequested(
        services: AppServices,
        settings: SettingsStore,
        modelContext: ModelContext,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) async {
        if ShareCalLaunchDiagnosticPlan.shouldSeedCalendarEvent(arguments: arguments) {
            do {
                let eventID = try services.calendarAccess.ensureShareCalSmokeTestEvent(
                    draft: ShareCalLaunchDiagnosticPlan.seedCalendarEventDraft(arguments: arguments)
                )
                NSLog("ShareCal seeded calendar event: \(eventID)")
            } catch {
                NSLog("ShareCal failed to seed calendar event: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunCloudKitWriteProbe(arguments: arguments) {
            await services.cloudKit.runPrivateDatabaseWriteProbe()
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunSharedReadProbe(arguments: arguments) {
            let diagnostic = await services.cloudKit.sharedReadDiagnostic()
            NSLog("ShareCal shared read probe:\n\(diagnostic.displayText)")
            NSLog("ShareCal shared read probe proves no access: \(diagnostic.provesNoSharedCalendarReadAccess)")
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunStopSharingProbe(arguments: arguments) {
            do {
                try await services.cloudKit.stopSharing(ownerMemberID: settings.currentMemberID)
                NSLog("ShareCal stop sharing probe succeeded")
            } catch {
                NSLog("ShareCal stop sharing probe failed: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldPreparePairingShare(arguments: arguments) {
            do {
                if !settings.hasSyncedMemberID {
                    settings.currentMemberID = try await services.cloudKit.fetchCurrentUserRecordID()
                }
                if PairingSettingsPlan.normalizedDisplayName(settings.currentDisplayName) == nil {
                    settings.currentDisplayName = PairingSettingsPlan.randomDisplayName()
                    settings.hasCompletedInitialProfilePrompt = true
                }
                let preparedShare = try await services.cloudKit.prepareShare(ownerMemberID: settings.currentMemberID)
                try await services.cloudKit.saveMemberProfileForSync(
                    ownerMemberID: settings.currentMemberID,
                    displayName: settings.currentDisplayName
                )
                settings.iCloudSharingEnabled = true
                settings.hasStartedPairing = true
                settings.markPairingDateIfNeeded()
                NSLog(
                    "%@ %@",
                    ShareCalLaunchDiagnosticPlan.pairingShareURLLogPrefix,
                    preparedShare.share.url?.absoluteString ?? "missing"
                )
            } catch {
                NSLog("ShareCal prepare pairing share probe failed: \(error)")
            }
        }

        if let shareURL = ShareCalLaunchDiagnosticPlan.acceptShareURL(arguments: arguments) {
            do {
                let metadata = try await services.cloudKit.fetchShareMetadata(from: shareURL)
                ShareCalCloudKitShareAcceptanceHandler.handle(metadata: metadata)
                NSLog("ShareCal accept share probe handled metadata owner=%@", metadata.share.recordID.zoneID.ownerName)
            } catch {
                NSLog("ShareCal accept share probe failed: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldForceSync(arguments: arguments) {
            // Reuses the accepted-share signal channel: RootView consumes it and
            // runs a foreground sync that bypasses the automatic-sync throttle.
            ShareCalAcceptedShareSignal.markAccepted(partnerOwnerID: nil)
        }

        // Joint-event / comment smoke flow. Each handler that needs current data runs
        // its own direct foreground sync (the force-sync signal above is consumed by
        // RootView asynchronously, so it can't be relied on within this task).
        if ShareCalLaunchDiagnosticPlan.shouldSeedInvitation(arguments: arguments) {
            await seedInvitation(services: services, settings: settings, modelContext: modelContext, arguments: arguments)
        }
        if ShareCalLaunchDiagnosticPlan.shouldAcceptInvitation(arguments: arguments) {
            await acceptInvitation(services: services, settings: settings, modelContext: modelContext)
        }
        if let body = ShareCalLaunchDiagnosticPlan.jointCommentBody(arguments: arguments) {
            await addJointComment(body: body, services: services, settings: settings, modelContext: modelContext)
        }
        if ShareCalLaunchDiagnosticPlan.shouldProbeJointComments(arguments: arguments) {
            await probeJointComments(services: services, settings: settings, modelContext: modelContext)
        }
    }

    private static let diag = ShareCalLaunchDiagnosticPlan.diagnosticLogPrefix

    private static func runForegroundSync(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        let coordinator = SyncCoordinator(
            calendarAccess: services.calendarAccess,
            eventMirrorService: services.eventMirrorService,
            cloudKit: services.cloudKitIfAvailable
        )
        await coordinator.foregroundSync(modelContext: modelContext, settings: settings)
    }

    private static func acceptedInvitation(in modelContext: ModelContext) -> EventInvitation? {
        let all = (try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? []
        return all.first { $0.status == .accepted && $0.archivedAt == nil }
    }

    /// Owner side: create an invitation matching the owner's already-seeded smoke event
    /// (so the title/date fallback in `localEventExists` keeps it from being auto-canceled
    /// once the partner's acceptance syncs back), then upload it.
    private static func seedInvitation(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext, arguments: [String]
    ) async {
        do {
            _ = try? services.calendarAccess.ensureShareCalSmokeTestEvent()
            let title = ShareCalLaunchDiagnosticPlan.seedInvitationTitle(arguments: arguments)
                ?? ShareCalSmokeTestEventPlan.title
            let window = services.calendarAccess.authorizedEvents(
                from: Date().addingTimeInterval(-2 * 24 * 3600),
                to: Date().addingTimeInterval(8 * 24 * 3600)
            )
            guard let source = window.first(where: { $0.title == title }) else {
                NSLog("%@ seedInvitation failed: no local event titled %@", diag, title)
                return
            }
            let invitation = EventInvitation(
                creatorMemberID: settings.currentMemberID,
                inviteeMemberID: settings.partnerOwnerIDForLocalData,
                title: source.title,
                startDate: source.startDate,
                endDate: source.endDate,
                isAllDay: source.isAllDay,
                location: source.location,
                notes: source.notes,
                statusRawValue: InvitationStatus.pending.rawValue,
                needsCloudKitUpload: services.cloudKitIfAvailable != nil
            )
            modelContext.insert(invitation)
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveInvitationForSync(invitation, currentMemberID: settings.currentMemberID)
                invitation.needsCloudKitUpload = false
                try? modelContext.save()
            }
            NSLog("%@ seedInvitation succeeded id=%@ title=%@", diag, invitation.id, source.title)
        } catch {
            NSLog("%@ seedInvitation failed: %@", diag, String(describing: error))
        }
    }

    /// Partner side: sync to receive the pending invitation, then accept it via the real
    /// flow (creates a local EventKit event so it isn't auto-canceled) and upload.
    private static func acceptInvitation(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        let all = (try? modelContext.fetch(FetchDescriptor<EventInvitation>())) ?? []
        guard let pending = all.first(where: {
            $0.status == .pending && $0.creatorMemberID != settings.currentMemberID
        }) else {
            NSLog("%@ acceptInvitation none-pending", diag)
            return
        }
        do {
            let draft = services.invitationService.draft(from: pending)
            let createdEvent = try services.calendarAccess.createShareCalEvent(from: draft)
            _ = try services.invitationService.accept(pending, createdLocalEventID: createdEvent.eventIdentifier)
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveInvitationForSync(pending, currentMemberID: settings.currentMemberID)
            }
            NSLog("%@ acceptInvitation succeeded id=%@", diag, pending.id)
        } catch {
            NSLog("%@ acceptInvitation failed: %@", diag, String(describing: error))
        }
    }

    /// Either side: sync, find the joint (accepted) invitation, add a comment anchored to
    /// it (routed by `EventCommentAnchorPlan`), and upload.
    private static func addJointComment(
        body: String, services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        guard let invitation = acceptedInvitation(in: modelContext) else {
            NSLog("%@ addJointComment failed: no accepted invitation", diag)
            return
        }
        let anchor = EventCommentAnchorPlan.anchor(forInvitation: invitation)
        let comment = services.commentService.createComment(
            eventMirrorID: anchor.key,
            authorMemberID: settings.currentMemberID,
            body: body
        )
        modelContext.insert(comment)
        do {
            try modelContext.save()
            if let cloudKit = services.cloudKitIfAvailable {
                try await cloudKit.saveCommentForSync(
                    comment,
                    eventOwnerMemberID: anchor.ownerMemberID,
                    currentMemberID: settings.currentMemberID,
                    eventRecordName: anchor.recordName
                )
            }
            NSLog("%@ addJointComment succeeded id=%@ anchor=%@ body=%@", diag, comment.id, anchor.key, body)
        } catch {
            NSLog("%@ addJointComment failed: %@", diag, String(describing: error))
        }
    }

    /// Either side: sync, then log every comment on the joint thread (count + bodies), so
    /// the smoke script can assert both partners' comments are present (symmetry).
    private static func probeJointComments(
        services: AppServices, settings: SettingsStore, modelContext: ModelContext
    ) async {
        await runForegroundSync(services: services, settings: settings, modelContext: modelContext)
        guard let invitation = acceptedInvitation(in: modelContext) else {
            NSLog("%@ jointComments count=0 (no accepted invitation)", diag)
            return
        }
        let anchor = EventCommentAnchorPlan.anchor(forInvitation: invitation)
        let comments = ((try? modelContext.fetch(FetchDescriptor<EventComment>())) ?? [])
            .filter { $0.eventMirrorID == anchor.key && $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let bodies = comments.map(\.body).joined(separator: "|")
        NSLog("%@ jointComments count=%d bodies=[%@]", diag, comments.count, bodies)
    }
}

@main
struct CoupleCalendarApp: App {
    @UIApplicationDelegateAdaptor(ShareCalAppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var services: AppServices

    private let modelContainer: ModelContainer = {
        do {
            return try ShareCalModelContainer.make()
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }()

    init() {
        ShareCalUITestLaunchPlan.resetUserDefaultsIfRequested()
        let settings = SettingsStore()
        let services = AppServices()
        // Test harness: dismiss the first-run profile / existing-iCloud-data sheets by
        // seeding the app's own UserDefaults before the view tree appears. Inert in
        // normal launches (no -ShareCalSeedProfileName argument).
        if let profileName = ShareCalLaunchDiagnosticPlan.seedProfileName() {
            settings.currentDisplayName = profileName
            settings.hasCompletedInitialProfilePrompt = true
            settings.hasResolvedExistingICloudDataPrompt = true
            // The post-pairing advisory sheets (partner note, reinstall safety) also
            // cover the calendar; these flags are only reset on partner replacement, so
            // seeding them true keeps automation on the calendar. (notifications 0003)
            settings.hasPromptedPartnerNoteForCurrentPairing = true
            settings.hasShownPairingSafetyNoticeForCurrentPairing = true
        }
        _settings = State(initialValue: settings)
        _services = State(initialValue: services)
        // Share the live instances with the background runner so background syncs
        // update the same observed state the UI renders (notifications decision 0002).
        ShareCalBackgroundSyncRunner.shared.configure(
            modelContainer: modelContainer,
            settings: settings,
            services: services
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(services)
                .modelContainer(modelContainer)
                .task {
                    await ShareCalLaunchDiagnostics.runIfRequested(
                        services: services,
                        settings: settings,
                        modelContext: modelContainer.mainContext
                    )
                    await ShareCalNotificationSetup.configure(services: services)
                }
        }
    }
}
