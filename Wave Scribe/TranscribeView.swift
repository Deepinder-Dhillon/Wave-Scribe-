import SwiftUI

import SwiftUI
import CoreData

struct TranscribeView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.managedObjectContext) private var viewContext

    // Fetch only the segments for the *current* recording,
    // that have been completed.
    @FetchRequest var completedSegments: FetchedResults<Segment>

    init() {
        // "currentRecordingID" is set when you start()
        // we'll just fetch *all* completed segments for simplicity
        let request = NSFetchRequest<Segment>(entityName: "Segment")
        request.predicate = NSPredicate(format: "state == %@", "completed")
        request.sortDescriptors = [
          NSSortDescriptor(keyPath: \Segment.createdAt, ascending: true)
        ]
        _completedSegments = FetchRequest(
          fetchRequest: request,
          animation: .default
        )
    }

    var body: some View {
        VStack {
            // simple controls
            HStack {
                if audioManager.uiStateManager.state == .recording {
                    Button("Stop") { audioManager.stop() }
                } else {
                    Button("Start") { audioManager.start() }
                }
            }
            .padding()

            // live-updating list of transcripts
            List(completedSegments, id: \.id) { seg in
                VStack(alignment: .leading) {
                    Text(seg.transcript ?? "")
                        .lineLimit(nil)
                    Text(seg.createdAt.map {
                         DateFormatter.localizedString(
                           from: $0,
                           dateStyle: .short,
                           timeStyle: .short)
                       } ?? "")
                       .font(.caption)
                       .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Live Transcriptions")
    }
}


#Preview {
    TranscribeView()
}
