import FirebaseCore
import SwiftUI

@main struct MyApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // sign in early, the service retries later anyway
                .task { try? await FirebaseUserDataService().signInAnonymouslyIfNeeded() }
        }
    }
}
