final class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()

    // Published so UI can refresh when any transcript changes
    @Published private(set) var activeJobs: [UUID: Double] = [:] // seg.id : progress 0…1

    private let queue      = OperationQueue()      // controls concurrency
    private let ctx        = CoreDataStack.shared.persistentContainer.newBackgroundContext()
    private let pathMon    = NetworkMonitor()
    private init() {
        queue.maxConcurrentOperationCount = 2      // tweak for your needs

        // Kick off processing when network comes back
        pathMon.onAvailable = { [weak self] in self?.resumeQueuedWork() }
    }

    // Call this whenever you create a segment OR on app launch
    func resumeQueuedWork() {
        ctx.perform { [weak self] in
            let req: NSFetchRequest<Segment> = Segment.fetchRequest()
            req.predicate = NSPredicate(format: "state == %@", "pendingUpload")
            if let segs = try? self?.ctx.fetch(req) {
                segs.forEach { self?.enqueue($0) }
            }
        }
    }

    private func enqueue(_ seg: Segment) {
        guard seg.state == "pendingUpload" else { return }

        seg.state = "uploading"
        seg.retryCount = 0
        try? ctx.save()

        let op = TranscriptionWorker(segmentID: seg.id, maxRetries: 5)
        op.completionBlock = { [weak self] in
            self?.ctx.perform {
                if let seg = self?.ctx.object(with: seg.objectID) as? Segment {
                    // remove progress UI
                    DispatchQueue.main.async { self?.activeJobs.removeValue(forKey: seg.id) }
                }
            }
        }
        op.onProgress = { [weak self] fraction in
            DispatchQueue.main.async { self?.activeJobs[seg.id] = fraction }
        }
        queue.addOperation(op)
    }
}
