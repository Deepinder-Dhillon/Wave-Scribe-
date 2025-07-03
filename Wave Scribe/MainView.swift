import SwiftUI

struct MainView: View {
    @State private var recordings = ["Recording 1", "Recording 2", "Recording 3", "Recording 4", "Recording 5", "Recording 6", "Recording 7", "Recording 8", "Recording 9", "Recording 10", "Recording 11", "Recording 12", "Recording 13", "Recording 14", "Recording 15"]
    @State private var editingMode: EditMode = .inactive
    @State private var selectedRecordings = Set<String>()
    
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
                        } label: {
                            Image(systemName: "largecircle.fill.circle")
                                .font(.system(size: 80))
                                .foregroundColor(.red)
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
        
}
