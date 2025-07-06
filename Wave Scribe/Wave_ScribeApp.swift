import SwiftUI
import SwiftData

@main
struct Wave_ScribeApp: App {

    @StateObject private var audioManager = AudioManager()
    
    init() {
        let bgContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
    

        
    }
    
    
    var body: some Scene {
        
        WindowGroup {
            MainView()
                .environmentObject(audioManager)
                .environment(\.managedObjectContext,
                              CoreDataStack.shared.persistentContainer.viewContext)
                .onAppear {
                    requestMicPermission()
                }
            
            
        }
        
    }
}
