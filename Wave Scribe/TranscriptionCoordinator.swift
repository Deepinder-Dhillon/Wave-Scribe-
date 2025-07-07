import Foundation
import CoreData
import Combine

protocol TranscriptionCoordinatorDelegate: AnyObject {
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didUpdateProgress progress: Double)
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didEncounterError error: Error)
}

final class TranscriptionCoordinator: ObservableObject {
    weak var delegate: TranscriptionCoordinatorDelegate?
    
    private let context: NSManagedObjectContext
    private let transcriptionService: TranscriptionService
    private let networkMonitor = NetworkMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    @Published private(set) var isWorking = false
    @Published private(set) var activeSegments = Set<UUID>()
    
    init(context: NSManagedObjectContext, apiKey: String) {
        self.context = context
        self.transcriptionService = TranscriptionService(apiKey: apiKey)
        setupServices()
    }
    
    private func setupServices() {
        transcriptionService.delegate = self
        
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.resumePendingTranscriptions()
                } else {
                    self?.pauseNewTranscriptions()
                }
            }
            .store(in: &cancellables)
    }
    
    func transcribeSegment(_ segment: Segment) {
        guard let segmentID = segment.id else {
            return
        }
        
        guard networkMonitor.isConnected else {
            let error = NSError(domain: "TranscriptionCoordinator", code: 2, userInfo: [NSLocalizedDescriptionKey: "No network connection"])
            delegate?.transcriptionCoordinator(self, didEncounterError: error)
            return
        }
        
        // Load audio data from file
        guard let filePath = segment.fileURL else {
            return
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        do {
            let audioData = try Data(contentsOf: fileURL)
            
            isWorking = true
            activeSegments.insert(segmentID)
            
            Task {
                await transcriptionService.transcribeAudio(audioData, segmentID: segmentID)
            }
            
        } catch {
            let transcriptionError = NSError(domain: "TranscriptionCoordinator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to load audio data: \(error.localizedDescription)"])
            delegate?.transcriptionCoordinator(self, didEncounterError: transcriptionError)
        }
    }
    
    private func pauseNewTranscriptions() {
        // Pause new transcription requests when network is lost
    }
    
    private func resumePendingTranscriptions() {
        // Resume any pending transcriptions when network is restored
    }
    
    private func markSegmentAsFailed(_ segmentID: UUID) {
        context.perform {
            let fetchRequest: NSFetchRequest<Segment> = Segment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", segmentID as CVarArg)
            
            if let segment = try? self.context.fetch(fetchRequest).first {
                segment.state = "failed"
                try? self.context.save()
            }
        }
    }
}

// MARK: - TranscriptionServiceDelegate

extension TranscriptionCoordinator: TranscriptionServiceDelegate {
    func transcriptionService(_ service: TranscriptionService, didCompleteTranscription text: String, for segmentID: UUID) {
        context.perform {
            let fetchRequest: NSFetchRequest<Segment> = Segment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", segmentID as CVarArg)
            
            if let segment = try? self.context.fetch(fetchRequest).first {
                segment.transcript = text
                segment.state = "completed"
                try? self.context.save()
            }
        }
        
        DispatchQueue.main.async {
            self.activeSegments.remove(segmentID)
            if self.activeSegments.isEmpty {
                self.isWorking = false
            }
        }
    }
    
    func transcriptionService(_ service: TranscriptionService, didFailWithError error: Error, for segmentID: UUID) {
        DispatchQueue.main.async {
            self.activeSegments.remove(segmentID)
            if self.activeSegments.isEmpty {
                self.isWorking = false
            }
        }
        
        markSegmentAsFailed(segmentID)
        delegate?.transcriptionCoordinator(self, didEncounterError: error)
    }
} 