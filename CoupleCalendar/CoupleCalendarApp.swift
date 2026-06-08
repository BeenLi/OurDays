import CloudKit
import SwiftUI
import SwiftData
import UIKit

final class ShareCalAppDelegate: NSObject, UIApplicationDelegate {
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
        ShareCalCloudKitShareAcceptanceHandler.accept(metadata: cloudKitShareMetadata)
    }
}

@MainActor
enum ShareCalLaunchDiagnostics {
    static func runIfRequested(
        services: AppServices,
        settings: SettingsStore,
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
    }
}

@main
struct CoupleCalendarApp: App {
    @UIApplicationDelegateAdaptor(ShareCalAppDelegate.self) private var appDelegate
    @State private var settings = SettingsStore()
    @State private var services = AppServices()

    private let modelContainer: ModelContainer = {
        do {
            return try ShareCalModelContainer.make()
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(services)
                .modelContainer(modelContainer)
                .task {
                    await ShareCalLaunchDiagnostics.runIfRequested(services: services, settings: settings)
                }
        }
    }
}
