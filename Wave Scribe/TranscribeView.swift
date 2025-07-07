import SwiftUI

struct TranscribeView: View {
    @EnvironmentObject var audioManager: AudioManager
    
    var filteredSegments: [SegmentStatus] {
        audioManager.transcriptionViewModel.sortedSegments.filter { segment in
            // Show segments that have transcripts, or are currently processing
            (segment.transcript != nil && !segment.transcript!.isEmpty) || 
            segment.status == "uploading" || 
            segment.status == "failed" ||
            segment.status == "completed"
        }
    }
    
    var body: some View {
        VStack {
            if filteredSegments.isEmpty {
                VStack {
                    Text("No transcriptions yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding()
                    
                    Text("Transcriptions will update every \(Int(audioManager.settings.segmentDuration)) seconds.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSegments) { segment in
                            SegmentTranscriptionView(segment: segment)
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
        }
        .navigationTitle("Transcriptions")
    }
}

struct SegmentTranscriptionView: View {
    let segment: SegmentStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // No segment index
                Spacer()
                StatusIndicator(status: segment.status)
            }
            
            if let transcript = segment.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            } else {
                Text(statusMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusMessage: String {
        switch segment.status {
        case "recording":
            return "Processing..."
        case "uploading":
            return "Transcribing..."
        case "failed":
            return "Transcription failed"
        default:
            return "Processing..."
        }
    }
}

struct StatusIndicator: View {
    let status: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusColor: Color {
        switch status {
        case "recording":
            return .red
        case "uploading":
            return .orange
        case "completed":
            return .green
        case "failed":
            return .red
        default:
            return .gray
        }
    }
    
    private var statusText: String {
        switch status {
        case "recording":
            return "Processing"
        case "uploading":
            return "Transcribing"
        case "completed":
            return "Completed"
        case "failed":
            return "Failed"
        default:
            return "Unknown"
        }
    }
}

#Preview {
    TranscribeView()
        .environmentObject(AudioManager())
}
