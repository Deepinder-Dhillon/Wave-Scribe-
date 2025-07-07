import CoreData

/**
 * Core Data stack manager with proper merge policies and context configuration
 * Handles data persistence and provides access to managed object contexts
 */
class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    
    /**
     * Persistent container with automatic merge policies
     * Configures contexts for proper conflict resolution
     */
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Model")
        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load persistent stores: \(error.localizedDescription)")
            }
        }
        // Set merge policy and automatic merging for viewContext
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()
    
    /**
     * Main context for UI operations
     * Automatically merges changes from background contexts
     */
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    /**
     * Creates a new background context for heavy operations
     * Configured with merge policies for conflict resolution
     */
    var backgroundContext: NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }
    
    /**
     * Saves the view context and handles errors
     * Called when UI needs to persist changes
     */
    func saveContext() {
        let context = persistentContainer.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private init() { }
}
