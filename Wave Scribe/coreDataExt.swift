import CoreData

extension CoreDataStack {
    func saveViewContext() {
        let ctx = viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() }
        catch {}
    }

    func delete<T: NSManagedObject>(_ object: T) {
        viewContext.delete(object)
        saveViewContext()
    }
    //fetch all Recordings, sorted by startTime descending.
    func fetchAllRecordings() throws -> [Recording] {
        let req: NSFetchRequest<Recording> = Recording.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]
        return try viewContext.fetch(req)
    }

    //fetch all Segments for a given Recording, sorted by index.
    func fetchSegments(for recording: Recording) throws -> [Segment] {
        let req: NSFetchRequest<Segment> = Segment.fetchRequest()
        req.predicate = NSPredicate(format: "recording == %@", recording)
        req.sortDescriptors = [NSSortDescriptor(key: "index", ascending: true)]
        return try viewContext.fetch(req)
    }
}

