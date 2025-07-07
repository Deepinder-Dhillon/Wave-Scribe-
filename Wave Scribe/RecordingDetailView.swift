import SwiftUI

struct RecordingDetailView: View {
    let recording: Recording
    @State private var recordingDetails: RecordingDetails?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var recordingManager: RecordingManager
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading recording details...")
                } else if let details = recordingDetails {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Recording Info
                            RecordingInfoSection(details: details)
                            
                            // Final Transcript
                            if !details.transcript.isEmpty {
                                FinalTranscriptSection(transcript: details.transcript)
                            }
                        }
                        .padding()
                    }
                } else {
                    Text("Failed to load recording details")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(recordingDetails?.title ?? "Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadRecordingDetails()
        }
    }
    
    private func loadRecordingDetails() async {
        recordingDetails = await recordingManager.getRecordingDetails(for: recording)
        isLoading = false
    }
}

// MARK: - Subviews

struct RecordingInfoSection: View {
    let details: RecordingDetails
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording Information")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Status", value: details.status.capitalized)
                InfoRow(label: "Duration", value: formatDuration(details.duration))
                InfoRow(label: "Started", value: formatDate(details.startTime))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct FinalTranscriptSection: View {
    let transcript: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Complete Transcript")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(transcript)
                .font(.body)
                .foregroundColor(.primary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    RecordingDetailView(recording: Recording())
} 