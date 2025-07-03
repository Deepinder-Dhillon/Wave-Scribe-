import Combine
import SwiftUI

struct RecordView: View {
    private let modes = ["Waveform", "Transcribe"]
    let timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    @State private var selectedMode = "Waveform"
    @State private var isRunning: Bool = false
    @State var elapsed: Double = 0
    @State private var level: CGFloat = 0
    @State private var waveformTimer: Timer? // temporary  to see waveform
    
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
                    .onChange(of: isRunning) {
                        if isRunning {
                            waveformTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
                                level = CGFloat.random(in: 0...0.5)
                            }
                        } else {
                            waveformTimer?.invalidate()
                            waveformTimer = nil
                            level = 0
                        }
                    }
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
                    if isRunning {
                        elapsed += 0.01
                    }
                }
        }
        .padding()
        
        VStack {
            
            ZStack {
                HStack {
                    Button {
                        isRunning = false
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
                    isRunning.toggle()
                } label: {
                    Image(systemName: isRunning
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
    RecordView()
    
}
