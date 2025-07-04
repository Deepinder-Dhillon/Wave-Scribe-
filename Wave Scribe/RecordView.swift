import Combine
import SwiftUI

struct RecordView: View {
    private let modes = ["Waveform", "Transcribe"]
    let timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var audiomanager = AudioManager()
    @State private var selectedMode = "Waveform"
    @State var elapsed: Double = 0
    @State private var level: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 4) {
            Picker("", selection: $selectedMode) {
                ForEach(modes, id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedMode == "Waveform" {
                WaveformView(level: $level)
                    .onChange(of: audiomanager.state) {
                        if audiomanager.state == .paused || audiomanager.state == .stopped {
                            level = 0
                        }
                    }
            }
            else {
                TranscribeView()
            }
        }
        .onAppear {
            audiomanager.start()
        }
        Spacer()
        
        VStack{
            Text(formatMMSSCs(elapsed))
                .font(.system(size: 38))
                .onReceive(timer) { _ in
                    if audiomanager.state == .recording {
                        elapsed += 0.01
                        level = 0
                    }
                }
        }
        .padding()
        
        VStack {
            
            ZStack {
                HStack {
                    Button {
                        audiomanager.stop()
                        dismiss()
                        
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.black)
                            .opacity(0.7)
                        
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 50)
                    
                }
                Button {
                    if audiomanager.state == .recording {
                        audiomanager.pause()
                    }
                    else if audiomanager.state == .paused {
                        audiomanager.resume()
                    }
                } label: {
                    Image(systemName: audiomanager.state == .paused
                          ? "pause.circle.fill"
                          : "largecircle.fill.circle")
                    .font(.system(size: 90))
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
        }
    }
}

func formatMMSSCs(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds)
    let m = totalSeconds / 60
    let s = totalSeconds % 60
    let centis = Int((seconds - Double(totalSeconds)) * 100)
    return String(format: "%02d:%02d.%02d", m, s, centis)
}

#Preview {
    RecordView ()
    
}
