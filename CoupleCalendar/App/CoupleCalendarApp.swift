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
            forTaskWithIdentifier: BackgroundRefreshSchedulePolicy.taskIdentifier,
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
            name: ShareCalSceneDelegateConfigurationPolicy.configurationName,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = ShareCalSceneDelegateConfigurationPolicy.sceneDelegateClass
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
enum ShareCalUITestLaunchPolicy {
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
        ShareCalUITestLaunchPolicy.resetUserDefaultsIfRequested()
        let settings = SettingsStore()
        let services = AppServices()
        // Test harness: dismiss the first-run profile / existing-iCloud-data sheets by
        // seeding the app's own UserDefaults before the view tree appears. Inert in
        // normal launches (no -ShareCalSeedProfileName argument).
        if let profileName = ShareCalLaunchDiagnosticPolicy.seedProfileName() {
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
