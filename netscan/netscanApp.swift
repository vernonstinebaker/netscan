import SwiftUI

@main
struct netscanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        // Ensure the window's titlebar uses a dark appearance on macOS by setting appearance on launch
        .commands {
            // No-op but keeps available for future app-level commands
        }
    }
}
