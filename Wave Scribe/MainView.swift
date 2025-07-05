import SwiftUI

struct MainView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var recordings = ["Recording 1", "Recording 2", "Recording 3", "Recording 4", "Recording 5", "Recording 6", "Recording 7", "Recording 8"]
    @State private var editingMode: EditMode = .inactive
    @State private var selectedRecordings = Set<String>()
    @State private var showDeniedAlert = false
    @State private var showRecordView = false
    
    
    var body: some View {
        NavigationStack {
            List(recordings, id: \.self, selection: $selectedRecordings) { rec in
                Text(rec)
            }
            .navigationTitle("Recordings")
            .environment(\.editMode, $editingMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if editingMode == .active {
                        Button {
                            deleteRecordings()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedRecordings.isEmpty)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        toggleEditMode()
                    } label: {
                        Text(editingMode == .inactive ? "Select" : "Done")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Button {
                    if canRecordAudio() {
                        showRecordView = true
                        audioManager.start()
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
            .alert("Microphone Needed",
                   isPresented: $showDeniedAlert) {
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
        }
    }
    
    private func toggleEditMode() {
        if editingMode == .inactive {
            selectedRecordings = Set<String>()
            editingMode = .active
        } else {
            selectedRecordings = Set<String>()
            editingMode = .inactive
        }
    }
    
    private func deleteRecordings() {
        for item in selectedRecordings {
            if let index = recordings.firstIndex(of: item) {
                recordings.remove(at: index)
            }
        }
        
        toggleEditMode()
    }
}


#Preview {
    MainView()
        .environmentObject(AudioManager())
    
}

