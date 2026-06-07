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
            name: nil,
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
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) async {
        if ShareCalLaunchDiagnosticPlan.shouldSeedCalendarEvent(arguments: arguments) {
            do {
                let eventID = try services.calendarAccess.ensureShareCalSmokeTestEvent(
                    title: ShareCalLaunchDiagnosticPlan.seedCalendarEventTitle(arguments: arguments)
                        ?? ShareCalSmokeTestEventPlan.title
                )
                NSLog("ShareCal seeded calendar event: \(eventID)")
            } catch {
                NSLog("ShareCal failed to seed calendar event: \(error)")
            }
        }

        if ShareCalLaunchDiagnosticPlan.shouldRunCloudKitWriteProbe(arguments: arguments) {
            await services.cloudKit.runPrivateDatabaseWriteProbe()
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
                    await ShareCalLaunchDiagnostics.runIfRequested(services: services)
                }
        }
    }
}
