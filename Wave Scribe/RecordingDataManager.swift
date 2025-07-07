import Foundation
import CoreData

protocol RecordingDataManagerDelegate: AnyObject {
    func recordingDataManager(_ manager: RecordingDataManager, didCreateRecording recording: Recording)
    func recordingDataManager(_ manager: RecordingDataManager, didEncounterError error: Error)
}

final class RecordingDataManager {
    weak var delegate: RecordingDataManagerDelegate?
    
    private let backgroundContext: NSManagedObjectContext
    private let transcriptionCoordinator: TranscriptionCoordinator
    
    init(apiKey: String) {
        self.backgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        self.transcriptionCoordinator = TranscriptionCoordinator(context: backgroundContext, apiKey: apiKey)
    }
    
    // MARK: - Recording Management
    
    func createRecording(with id: UUID) -> Recording {
        let recording = Recording(context: backgroundContext)
        recording.id = id
        recording.startTime = Date()
        recording.status = "recording"
        recording.totalSegments = 0
        recording.duration = 0
        recording.title = ""
        recording.transcript = ""
        
        do {
            try backgroundContext.save()
            delegate?.recordingDataManager(self, didCreateRecording: recording)
        } catch {
            delegate?.recordingDataManager(self, didEncounterError: error)
        }
        
        return recording
    }
    
    func updateRecordingStatus(_ recording: Recording, status: String) {
        backgroundContext.perform {
            recording.status = status
            try? self.backgroundContext.save()
        }
    }
    
    // MARK: - Segment Management
    
    func saveSegment(url: URL, duration: Double, index: Int, for recordingID: UUID) {
        backgroundContext.perform {
            do {
                let fetchRequest: NSFetchRequest<Recording> = Recording.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", recordingID as CVarArg)
                
                guard let recording = try self.backgroundContext.fetch(fetchRequest).first else {
                    return
                }
                
                let segment = Segment(context: self.backgroundContext)
                segment.id = UUID()
                segment.fileURL = url.path
                segment.duration = duration
                segment.index = Int32(index)
                segment.createdAt = Date()
                segment.state = "pending"
                segment.recording = recording
                
                try self.backgroundContext.save()
                
                // Load audio data and trigger transcription
                do {
                    let audioData = try Data(contentsOf: url)
                    self.transcriptionCoordinator.transcribeSegment(segment)
                } catch {
                    // Handle audio data loading error
                }
                
            } catch {
                Task { @MainActor in
                    self.delegate?.recordingDataManager(self, didEncounterError: error)
                }
            }
        }
    }
    
    // MARK: - Public Interface
    
    var context: NSManagedObjectContext {
        return backgroundContext
    }
    
    var transcriptionCoordinatorInstance: TranscriptionCoordinator {
        return transcriptionCoordinator
    }
    
    func saveContext() {
        backgroundContext.perform {
            do {
                try self.backgroundContext.save()
            } catch {
                Task { @MainActor in
                    self.delegate?.recordingDataManager(self, didEncounterError: error)
                }
            }
        }
    }
} 