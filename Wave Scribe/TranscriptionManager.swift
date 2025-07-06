import Foundation
import CoreData
import Combine
import SwiftOpenAI

actor TaskTracker {
    private var activeSegments = Set<Segment>()
    
    func canStartTask(for segment: Segment) -> Bool {
        return activeSegments.insert(segment).inserted
    }
    
    func taskDidFinish(for segment: Segment) {
        activeSegments.remove(segment)
    }
}

final class TranscriptionManager: ObservableObject {
    @Published private(set) var isWorking = false
    
    private let context: NSManagedObjectContext
    private let networkMonitor = NetworkMonitor()
    private let taskTracker: TaskTracker
    private var openAIService: OpenAIService?
    private var apiKey: String =  ""
    
    init(
        context: NSManagedObjectContext,
        taskTracker: TaskTracker = TaskTracker()
    ) {
        self.context = context
        self.taskTracker = taskTracker
        
        Task{
            apiKey = await fetchAPIKey()
        }
        networkMonitor.onStatusChange = { [weak self] online in
            guard let self = self, online else { return }
            Task { await self.resumeQueuedWork() }
        }
    }
    
    func configure(apiKey: String) {
        openAIService = OpenAIServiceFactory.service(apiKey: apiKey)
        Task {
            await resumeQueuedWork()
        }
    }
    
    private func openAi() -> OpenAIService {
        return OpenAIServiceFactory.service(apiKey: apiKey)
    }
    
    func resumeQueuedWork() async {
        let segmentsToProcess = await fetchSegments()
        
        for segment in segmentsToProcess {
            
            if await taskTracker.canStartTask(for: segment) {
                Task {
                    await self.processSegment(segment: segment)
                    await self.taskTracker.taskDidFinish(for: segment)
                }
            }
        }
    }
    
    private func fetchSegments() async -> [Segment] {
        return await context.perform {
            let request: NSFetchRequest<Segment> = Segment.fetchRequest()
            request.predicate = NSPredicate(format: "state == %@", "pendingUpload")
            
            guard let segments = try? self.context.fetch(request) else {
                return []
            }
            return segments
        }
    }
    
    private func processSegment(segment: Segment) async {
        guard !apiKey.isEmpty else {
            await updateSegmentState(segment: segment, to: "failed")
            return
        }
        
        let openAI = openAi()
        
        
        let audioData: Data? = try? await context.perform {
            guard let path = segment.fileURL else { return nil }
            let url = URL(fileURLWithPath: path)
            return try Data(contentsOf: url)
        }
        
        guard let audioData = audioData else {
            await updateSegmentState(segment: segment, to: "failed")
            return
        }
        
        await updateSegmentState(segment: segment, to: "uploading", retryCount: 0)
        
        let maxRetries = 5
        for attempt in 1...maxRetries {
            do {
                let params = AudioTranscriptionParameters(fileName: (segment.id?.uuidString ?? UUID().uuidString) + "default.m4a",
                                                          file: audioData)
                let response = try await openAI.createTranscription(parameters: params)
                
                await saveTranscript(response.text, to: segment)
                return
            } catch {
                
                if attempt >= maxRetries { break }
                
                await updateSegmentState(segment: segment, retryCount: Int16(attempt))
                
                do {
                    let delay = Backoff.delay(for: attempt)
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }
            }
        }
        
        await updateSegmentState(segment: segment, to: "failed")
    }
    
    private func updateSegmentState(segment: Segment, to newState: String? = nil, retryCount: Int16? = nil) async {
        await context.perform {
            guard let managedSegment = try? self.context.existingObject(with: segment.objectID) as? Segment else { return }
            
            if let newState = newState {
                managedSegment.state = newState
            }
            if let retryCount = retryCount {
                managedSegment.retryCount = retryCount
            }
            
            if self.context.hasChanges {
                try? self.context.save()
            }
        }
    }
    
    private func saveTranscript(_ text: String, to segment: Segment) async {
        await context.perform {
            guard let transcribedSegment = try? self.context.existingObject(with: segment.objectID) as? Segment else { return }
            transcribedSegment.transcript = text
            transcribedSegment.state = "completed"
            try? self.context.save()
        }
    }
}

fileprivate struct Backoff {
    static func delay(for attempt: Int) -> Double {
        return pow(2.0, Double(attempt))
    }
}
