import Foundation
import CoreData
import Combine
import SwiftUI

protocol RecordingManagerDelegate: AnyObject {
    func recordingManager(_ manager: RecordingManager, didUpdateRecording recording: Recording)
    func recordingManager(_ manager: RecordingManager, didEncounterError error: Error)
}

/**
 * Manages recording lifecycle and Core Data operations
 * Handles automatic updates, recording status tracking, and data persistence
 */
@MainActor
final class RecordingManager: ObservableObject {
    weak var delegate: RecordingManagerDelegate?
    
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var isLoading = false
    
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    private let transcriptionCoordinator: TranscriptionCoordinator
    
    init(context: NSManagedObjectContext, apiKey: String = "") {
        self.context = context
        self.context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context.automaticallyMergesChangesFromParent = true
        self.transcriptionCoordinator = TranscriptionCoordinator(context: context, apiKey: apiKey)
        
        setupNotifications()
        loadRecordings()
    }
    
    // MARK: - Public Interface
    
    /**
     * Loads all recordings from Core Data with proper sorting
     * Updates UI automatically when data changes
     */
    func loadRecordings() {
        isLoading = true
        
        context.perform { [weak self] in
            let fetchRequest: NSFetchRequest<Recording> = Recording.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Recording.startTime, ascending: false)]
            
            do {
                let recordings = try self?.context.fetch(fetchRequest) ?? []
                DispatchQueue.main.async {
                    self?.recordings = recordings
                    self?.isLoading = false
                }
            } catch {
                print("Failed to load recordings:", error)
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
            }
        }
    }
    
    /**
     * Manually refreshes recordings list
     * Useful for pull-to-refresh or explicit updates
     */
    func refreshRecordings() {
        loadRecordings()
    }
    
    /**
     * Deletes a recording and all its associated segments
     * Removes audio files and Core Data entries
     */
    func deleteRecording(_ recording: Recording) {
        context.perform { [weak self] in
            guard let self = self else { return }
            
            // Delete associated segments first
            if let segments = recording.segments?.allObjects as? [Segment] {
                for segment in segments {
                    // Delete audio file
                    if let fileURLString = segment.fileURL, let fileURL = URL(string: fileURLString) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    self.context.delete(segment)
                }
            }
            
            // Delete recording
            self.context.delete(recording)
            
            // Save changes
            do {
                try self.context.save()
            } catch {
                print("Failed to delete recording:", error)
            }
        }
    }
    
    func updateRecordingTitle(_ recording: Recording, title: String) {
        context.perform { [weak self] in
            recording.title = title
            try? self?.context.save()
            
            DispatchQueue.main.async {
                self?.loadRecordings()
            }
        }
    }
    
    /**
     * Checks if all segments for a recording are complete
     * Updates recording status to "completed" when all segments finish
     */
    func checkAndUpdateRecordingStatus(_ recording: Recording) {
        context.perform { [weak self] in
            guard let self = self else { return }
            
            // Fetch fresh recording with segments
            let fetchRequest: NSFetchRequest<Recording> = Recording.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", recording.id! as CVarArg)
            
            guard let freshRecording = try? self.context.fetch(fetchRequest).first,
                  let segments = freshRecording.segments?.allObjects as? [Segment] else {
                return
            }
            
            // Check if all segments are transcribed or failed
            let allSegmentsProcessed = segments.allSatisfy { segment in
                segment.state == "transcribed" || segment.state == "failed"
            }
            
            if allSegmentsProcessed {
                // Aggregate transcripts from successful segments
                let successfulTranscripts = segments
                    .filter { $0.state == "transcribed" }
                    .compactMap { $0.transcript }
                    .filter { !$0.isEmpty }
                
                let fullTranscript = successfulTranscripts.joined(separator: " ")
                
                // Update recording
                freshRecording.transcript = fullTranscript
                freshRecording.status = "completed"
                
                // Delete segments after successful aggregation
                for segment in segments {
                    if let fileURLString = segment.fileURL, let fileURL = URL(string: fileURLString) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    self.context.delete(segment)
                }
                
                // Save changes
                do {
                    try self.context.save()
                } catch {
                    print("Failed to update recording status:", error)
                }
            }
        }
    }
    
    // MARK: - Recording Details
    
    /**
     * Retrieves detailed information for a recording
     * Includes segments, status, and aggregated transcript
     */
    func getRecordingDetails(for recording: Recording) async -> RecordingDetails {
        return await context.perform {
            // Fetch fresh recording with segments
            let fetchRequest: NSFetchRequest<Recording> = Recording.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", recording.id! as CVarArg)
            
            guard let freshRecording = try? self.context.fetch(fetchRequest).first else {
                return RecordingDetails(
                    id: recording.id ?? UUID(),
                    title: recording.title ?? "",
                    status: recording.status ?? "unknown",
                    duration: recording.duration,
                    totalSegments: Int(recording.totalSegments),
                    startTime: recording.startTime ?? Date(),
                    transcript: recording.transcript ?? "",
                    segments: []
                )
            }
            
            // Check if segments exist (for in-progress recordings)
            guard let segments = freshRecording.segments?.allObjects as? [Segment] else {
                // No segments means recording is completed and transcript is aggregated
                return RecordingDetails(
                    id: freshRecording.id ?? UUID(),
                    title: freshRecording.title ?? "",
                    status: freshRecording.status ?? "unknown",
                    duration: freshRecording.duration,
                    totalSegments: Int(freshRecording.totalSegments),
                    startTime: freshRecording.startTime ?? Date(),
                    transcript: freshRecording.transcript ?? "",
                    segments: []
                )
            }
            
            // Convert segments to detail objects
            let segmentDetails = segments.map { segment in
                SegmentDetail(
                    id: segment.id ?? UUID(),
                    index: Int(segment.index),
                    status: segment.state ?? "unknown",
                    transcript: segment.transcript ?? "",
                    duration: segment.duration
                )
            }
            
            return RecordingDetails(
                id: freshRecording.id ?? UUID(),
                title: freshRecording.title ?? "",
                status: freshRecording.status ?? "unknown",
                duration: freshRecording.duration,
                totalSegments: Int(freshRecording.totalSegments),
                startTime: freshRecording.startTime ?? Date(),
                transcript: freshRecording.transcript ?? "",
                segments: segmentDetails
            )
        }
    }
    
    // MARK: - Notification Setup
    
    /**
     * Sets up Core Data save notifications for automatic UI updates
     * Ensures recordings list stays in sync with database changes
     */
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: context,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadRecordings()
            }
        }
    }
}

// MARK: - Data Models

/**
 * Detailed recording information for UI display
 * Contains aggregated data from recording and segments
 */
struct RecordingDetails {
    let id: UUID
    let title: String
    let status: String
    let duration: Double
    let totalSegments: Int
    let startTime: Date
    let transcript: String
    let segments: [SegmentDetail]
}

/**
 * Individual segment information
 * Represents a single audio segment with transcription status
 */
struct SegmentDetail: Identifiable {
    let id: UUID
    let index: Int
    let status: String
    let transcript: String
    let duration: Double
} 