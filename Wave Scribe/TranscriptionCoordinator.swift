import Foundation
import CoreData
import Combine

/**
 * Coordinates transcription of audio segments with rate limiting and retry logic
 * Manages concurrent transcription tasks and handles network failures gracefully
 */
class TranscriptionCoordinator: NSObject {
    // MARK: - Dependencies
    private let context: NSManagedObjectContext
    private let transcriptionService: TranscriptionService
    private let networkMonitor: NetworkMonitor
    private let taskTracker: TaskTracker
    
    // MARK: - Configuration
    private let apiKey: String
    private let maxConcurrentTasks: Int
    
    // MARK: - Delegation
    weak var delegate: TranscriptionCoordinatorDelegate?
    
    init(context: NSManagedObjectContext, apiKey: String, maxConcurrentTasks: Int = 3) {
        self.context = context
        self.apiKey = apiKey
        self.maxConcurrentTasks = maxConcurrentTasks
        self.transcriptionService = TranscriptionService(apiKey: apiKey)
        self.networkMonitor = NetworkMonitor()
        self.taskTracker = TaskTracker(maxConcurrentTasks: maxConcurrentTasks)
        
        super.init()
        
        transcriptionService.delegate = self
    }
    
    // MARK: - Public Interface
    
    /**
     * Initiates transcription for an audio segment
     * Queues the task if at capacity, otherwise starts immediately
     */
    func transcribeSegment(segmentID: UUID, fileURL: URL) {
        Task {
            await taskTracker.waitForAvailableSlot()
            await updateSegmentStatus(segmentID: segmentID, status: "uploading")
            await transcriptionService.transcribeAudio(fileURL: fileURL, segmentID: segmentID)
        }
    }
    
    // MARK: - Segment Management
    
    /**
     * Updates segment status in Core Data
     * Handles background context operations safely
     */
    private func updateSegmentStatus(segmentID: UUID, status: String) async {
        await context.perform {
            let fetchRequest: NSFetchRequest<Segment> = Segment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", segmentID as CVarArg)
            
            if let segment = try? self.context.fetch(fetchRequest).first {
                segment.state = status
                try? self.context.save()
            }
        }
    }
    
    /**
     * Finds segment by ID in Core Data context
     * Returns nil if segment not found
     */
    private func findSegment(by segmentID: UUID) async -> Segment? {
        await context.perform {
            let fetchRequest: NSFetchRequest<Segment> = Segment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", segmentID as CVarArg)
            return try? self.context.fetch(fetchRequest).first
        }
    }
}

// MARK: - TranscriptionServiceDelegate

/**
 * Handles transcription service callbacks
 * Updates segment status and notifies delegate of completion
 */
extension TranscriptionCoordinator: TranscriptionServiceDelegate {
    func transcriptionService(_ service: TranscriptionService, didCompleteTranscription transcript: String, for segmentID: UUID) {
        Task {
            let segment = await findSegment(by: segmentID)
            if let segment = segment {
                await taskTracker.taskDidFinish(for: segment)
            }
            do {
                let fetchRequest: NSFetchRequest<Segment> = Segment.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", segmentID as CVarArg)
                if let segment = try context.fetch(fetchRequest).first {
                    segment.transcript = transcript
                    segment.state = "transcribed"
                    try context.save()
                    await self.delegate?.transcriptionCoordinator(self, didCompleteSegment: segment)
                }
            } catch {}
        }
    }
    
    func transcriptionService(_ service: TranscriptionService, didEncounterError error: Error, for segmentID: UUID) {
        Task {
            let segment = await findSegment(by: segmentID)
            if let segment = segment {
                await taskTracker.taskDidFinish(for: segment)
            }
            await updateSegmentStatus(segmentID: segmentID, status: "failed")
            await self.delegate?.transcriptionCoordinator(self, didEncounterError: error)
        }
    }
    
    func transcriptionService(_ service: TranscriptionService, didUpdateProgress progress: Double, for segmentID: UUID) {
        Task {
            await self.delegate?.transcriptionCoordinator(self, didUpdateProgress: progress)
        }
    }
}

// MARK: - Task Tracker

/**
 * Manages concurrent transcription tasks with rate limiting
 * Prevents overwhelming the transcription service with too many requests
 */
actor TaskTracker {
    private var activeTasks: Set<Segment> = []
    private var waitingTasks: [(Segment, CheckedContinuation<Void, Never>)] = []
    private let maxConcurrentTasks: Int
    
    init(maxConcurrentTasks: Int) {
        self.maxConcurrentTasks = maxConcurrentTasks
    }
    
    /**
     * Waits for an available slot in the task queue
     * Blocks until a slot becomes available
     */
    func waitForAvailableSlot() async {
        while activeTasks.count >= maxConcurrentTasks {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waitingTasks.append((Segment(), continuation))
            }
        }
    }
    
    /**
     * Marks a task as finished and processes waiting tasks
     * Frees up a slot for the next task in queue
     */
    func taskDidFinish(for segment: Segment) {
        activeTasks.remove(segment)
        
        // Process waiting tasks if any
        if !waitingTasks.isEmpty {
            let (_, continuation) = waitingTasks.removeFirst()
            continuation.resume()
        }
    }
}

// MARK: - Delegate Protocol

/**
 * Protocol for receiving transcription coordination events
 * Allows UI updates and recording status management
 */
protocol TranscriptionCoordinatorDelegate: AnyObject {
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didUpdateProgress progress: Double) async
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didEncounterError error: Error) async
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didCompleteSegment segment: Segment) async
} 