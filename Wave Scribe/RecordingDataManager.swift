import Foundation
import CoreData
import AVFoundation

protocol RecordingDataManagerDelegate: AnyObject {
    func recordingDataManager(_ manager: RecordingDataManager, didCreateRecording recording: Recording)
    func recordingDataManager(_ manager: RecordingDataManager, didEncounterError error: Error)
}

final class RecordingDataManager {
    weak var delegate: RecordingDataManagerDelegate?
    weak var audioManager: AudioManager?
    weak var transcriptionViewModel: TranscriptionViewModel?
    
    private let backgroundContext: NSManagedObjectContext
    private let transcriptionCoordinator: TranscriptionCoordinator
    
    init(apiKey: String) {
        self.backgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.backgroundContext.automaticallyMergesChangesFromParent = true
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
            DispatchQueue.main.async {
                self.delegate?.recordingDataManager(self, didCreateRecording: recording)
            }
        } catch {
            DispatchQueue.main.async {
                self.delegate?.recordingDataManager(self, didEncounterError: error)
            }
        }
        
        return recording
    }
    
    func updateRecordingStatus(_ recording: Recording, status: String) {
        backgroundContext.perform {
            recording.status = status
            try? self.backgroundContext.save()
        }
    }
    
    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // This method is called for each audio buffer during recording
        // Currently no processing needed here, but could be extended for real-time analysis
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
                segment.index = Int16(index)
                segment.createdAt = Date()
                segment.state = "recording"
                segment.recording = recording
                
                try self.backgroundContext.save()
                
                // Update transcription view model on main thread
                Task { @MainActor in
                    self.transcriptionViewModel?.addSegment(id: segment.id!, index: index)
                }
                
                // Load audio data and trigger transcription
                do {
                    let audioData = try Data(contentsOf: url)
                    
                    // Update status to uploading before sending to API
                    segment.state = "uploading"
                    try self.backgroundContext.save()
                    
                    Task { @MainActor in
                        self.transcriptionViewModel?.updateSegmentToUploading(id: segment.id!)
                    }
                    
                    Task {
                        await self.transcriptionCoordinator.transcribeSegment(segmentID: segment.id!, fileURL: url)
                    }
                } catch {
                    // Handle audio data loading error
                    segment.state = "failed"
                    try? self.backgroundContext.save()
                }
                
            } catch {
                DispatchQueue.main.async {
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
                DispatchQueue.main.async {
                    self.delegate?.recordingDataManager(self, didEncounterError: error)
                }
            }
        }
    }
} 
