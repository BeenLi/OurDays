import SwiftUI
import SwiftData

@main
struct CoupleCalendarApp: App {
    @State private var settings = SettingsStore()
    @State private var services = AppServices()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            CoupleSpace.self,
            MemberProfile.self,
            EventMirror.self,
            LocalEventShadow.self,
            EventInvitation.self,
            EventComment.self,
            SyncState.self
        ])
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
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
        }
    }
}
