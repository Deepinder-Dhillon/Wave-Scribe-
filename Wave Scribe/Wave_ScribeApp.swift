import SwiftUI
import SwiftData

@main
struct Wave_ScribeApp: App {

    @StateObject private var audioManager = AudioManager()
    @State private var apiKey: String = ""
    @State private var isLoading = true
    
    init() {
    }
    
    var body: some Scene {
        WindowGroup {
            if isLoading {
                VStack {
                    ProgressView("Loading API Key...")
                        .padding()
                }
                .onAppear {
                    Task {
                        apiKey = await fetchAPIKey()
                        isLoading = false
                    }
                }
            } else {
                MainView(apiKey: apiKey)
                    .environmentObject(audioManager)
            }
        }
    }
}
