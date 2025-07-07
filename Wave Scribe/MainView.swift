import SwiftUI

struct MainView: View {
    let apiKey: String
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.managedObjectContext) private var viewContext
    
    @StateObject private var recordingManager: RecordingManager
    @State private var editingMode: EditMode = .inactive
    @State private var selectedRecordings = Set<Recording>()
    @State private var showDeniedAlert = false
    @State private var showRecordView = false
    @State private var selectedRecording: Recording?
    @State private var showRecordingDetail = false
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self._recordingManager = StateObject(wrappedValue: RecordingManager(context: CoreDataStack.shared.persistentContainer.viewContext, apiKey: apiKey))
    }
    
    var body: some View {
        NavigationView {
            Group {
                if recordingManager.isLoading {
                    ProgressView("Loading recordings...")
                } else if recordingManager.recordings.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "mic.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Recordings Yet")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Start your first recording to see it here")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    recordingsListView
                }
            }
            .navigationTitle("Recordings")
            .environment(\.editMode, $editingMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if editingMode == .active {
                        HStack {
                            Button {
                                selectAllRecordings()
                            } label: {
                                Text(selectedRecordings.count == recordingManager.recordings.count ? "Deselect All" : "Select All")
                            }
                            
                            Button {
                                deleteSelectedRecordings()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(selectedRecordings.isEmpty)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if editingMode == .inactive {
                            Button {
                                recordingManager.refreshRecordings()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        
                        Button {
                            toggleEditMode()
                        } label: {
                            Text(editingMode == .inactive ? "Select" : "Done")
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Button {
                    if canRecordAudio() {
                        showRecordView = true
                        do {
                            try audioManager.start()
                        } catch {}
                    } else {
                        requestMicPermission()
                        if !canRecordAudio() {
                            showDeniedAlert = true
                        }
                    }
                } label: {
                    Image(systemName: "largecircle.fill.circle")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                }
                .padding(.bottom, 40)
            }
            .onAppear {
                audioManager.configureTranscription(apiKey: apiKey)
                audioManager.recordingManager = recordingManager
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in }
            .alert("Microphone Needed", isPresented: $showDeniedAlert) {
                Button("OK") { showDeniedAlert = false }
            } message: {
                Text("Please enable microphone access in Settings.")
            }
            .fullScreenCover(isPresented: $showRecordView) {
                RecordView()
                    .environmentObject(audioManager)
                    .onDisappear{
                        if audioManager.state != .stopped {
                            audioManager.stop()
                        }
                    }
            }
            .sheet(isPresented: $showRecordingDetail) {
                if let recording = selectedRecording {
                    RecordingDetailView(recording: recording)
                        .environmentObject(recordingManager)
                }
            }
        }
    }
    
    private func toggleEditMode() {
        if editingMode == .inactive {
            selectedRecordings = Set<Recording>()
            editingMode = .active
        } else {
            selectedRecordings = Set<Recording>()
            editingMode = .inactive
        }
    }
    
    private func selectAllRecordings() {
        if selectedRecordings.count == recordingManager.recordings.count {
            // Deselect all
            selectedRecordings.removeAll()
        } else {
            // Select all
            selectedRecordings = Set(recordingManager.recordings)
        }
    }
    
    private func deleteSelectedRecordings() {
        for recording in selectedRecordings {
            recordingManager.deleteRecording(recording)
        }
        selectedRecordings.removeAll()
        toggleEditMode()
    }
    
    private func deleteRecordings(offsets: IndexSet) {
        for index in offsets {
            let recording = recordingManager.recordings[index]
            recordingManager.deleteRecording(recording)
        }
    }
    
    private var recordingsListView: some View {
        List(recordingManager.recordings, id: \.objectID, selection: $selectedRecordings) { recording in
            RecordingRow(recording: recording)
                .onTapGesture {
                    if editingMode == .inactive {
                        selectedRecording = recording
                        showRecordingDetail = true
                    }
                }
        }
    }
}


// MARK: - RecordingRow

struct RecordingRow: View {
    let recording: Recording
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title?.isEmpty == false ? recording.title! : "Untitled Recording")
                    .font(.headline)
                    .lineLimit(1)
                
                Text(formatDate(recording.startTime ?? Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    MainView(apiKey: "")
        .environmentObject(AudioManager())
}

