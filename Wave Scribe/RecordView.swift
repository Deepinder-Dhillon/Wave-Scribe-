import Combine
import SwiftUI

struct RecordView: View {
    @EnvironmentObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedMode = "Waveform"
    @State var elapsed: Double = 0
    
    private let modes = ["Waveform", "Transcribe"]
    let timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack{
            VStack(spacing: 4) {
                Picker("", selection: $selectedMode) {
                    ForEach(modes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedMode == "Waveform" {
                    WaveformView(level: $audioManager.audioLevel)
                    
                }
                else {
                    TranscribeView()
                }
            }
            Spacer()
            VStack{
                Text(formatMMSSCs(elapsed))
                    .font(.system(size: 38))
                    .onReceive(timer) { _ in
                        if audioManager.state == .recording {
                            elapsed += 0.01
                            
                        }
                    }
            }
            .padding()
            
            VStack {
                
                ZStack {
                    HStack {
                        Button {
                            audioManager.stop()
                            dismiss()
                            
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.primary)
                                .opacity(0.7)
                            
                        }
                        .disabled(audioManager.isUIDisabled)
                        .opacity(audioManager.isUIDisabled ? 0.5 : 1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 50)
                        
                    }
                    Button {
                        if audioManager.state == .recording {
                            audioManager.pause()
                        }
                        else if audioManager.state == .paused {
                            audioManager.resume()
                        }
                    } label: {
                        Image(systemName: audioManager.state == .recording
                              ? "pause.circle.fill"
                              : "largecircle.fill.circle")
                        .font(.system(size: 90))
                        .foregroundColor(.red)
                    }
                    .disabled(audioManager.isUIDisabled)
                    .opacity(audioManager.isUIDisabled ? 0.5 : 1)
                }
                .padding(.horizontal)
                
            }
        }
        .alert(isPresented: $audioManager.resumePrompt) {
            Alert(
                title: Text("Recording paused by system"),
                message: Text("Would you like to resume or stop?"),
                primaryButton: .default(Text("Resume")) {
                    audioManager.userResume()
                },
                secondaryButton: .destructive(Text("Stop")) {
                    audioManager.userStop()
                    dismiss()
                }
            )
        }
    }
    
    
    func formatMMSSCs(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        let centis = Int((seconds - Double(totalSeconds)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, centis)
    }
}

#Preview {
    RecordView()
        .environmentObject(AudioManager())
    
}



