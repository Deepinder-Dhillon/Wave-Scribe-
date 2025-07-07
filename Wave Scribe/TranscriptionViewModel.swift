import Foundation
import SwiftUI
import Combine

struct SegmentStatus: Identifiable {
    let id: UUID
    let index: Int
    var status: String // "recording", "uploading", "completed", "failed"
    var transcript: String?
    
    init(id: UUID, index: Int, status: String = "recording", transcript: String? = nil) {
        self.id = id
        self.index = index
        self.status = status
        self.transcript = transcript
    }
}

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var segmentStatuses: [SegmentStatus] = []
    @Published var currentRecordingSegmentIndex: Int = 0
    @Published var currentProcessingSegmentIndex: Int = 0
    @Published var isRecording: Bool = false
    
    // Reset all status tracking
    func resetStatusTracking() {
        segmentStatuses.removeAll()
        currentRecordingSegmentIndex = 0
        currentProcessingSegmentIndex = 0
        isRecording = false
    }
    
    // Add a new segment when recording starts
    func addSegment(id: UUID, index: Int) {
        let newSegment = SegmentStatus(id: id, index: index, status: "recording")
        segmentStatuses.append(newSegment)
        currentRecordingSegmentIndex = index
        isRecording = true
    }
    
    // Update segment status to uploading when API call starts
    func updateSegmentToUploading(id: UUID) {
        if let idx = segmentStatuses.firstIndex(where: { $0.id == id }) {
            segmentStatuses[idx].status = "uploading"
            currentProcessingSegmentIndex = segmentStatuses[idx].index
        }
    }
    
    // Update segment when transcription completes
    func updateSegmentCompleted(id: UUID, transcript: String) {
        if let idx = segmentStatuses.firstIndex(where: { $0.id == id }) {
            segmentStatuses[idx].status = "completed"
            segmentStatuses[idx].transcript = transcript
            currentProcessingSegmentIndex = 0 // Reset processing index
        }
    }
    
    // Update segment when transcription fails
    func updateSegmentFailed(id: UUID) {
        if let idx = segmentStatuses.firstIndex(where: { $0.id == id }) {
            segmentStatuses[idx].status = "failed"
            currentProcessingSegmentIndex = 0 // Reset processing index
        }
    }
    
    // Update recording state
    func updateRecordingState(_ isRecording: Bool) {
        self.isRecording = isRecording
        if !isRecording {
            currentRecordingSegmentIndex = 0
        }
    }
    
    // Get segments for current recording (sorted by index)
    var sortedSegments: [SegmentStatus] {
        segmentStatuses.sorted { $0.index < $1.index }
    }
    
    // Check if any segments are currently processing
    var hasProcessingSegments: Bool {
        segmentStatuses.contains { $0.status == "uploading" }
    }
} 