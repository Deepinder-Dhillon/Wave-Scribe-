import SwiftUI
import UIKit

struct WaveformView: UIViewRepresentable {
    @Binding var level: CGFloat
    
    var waveColor: UIColor = .red
    var numberOfWaves: UInt = 5
    var frequency: CGFloat = 1.5
    var idleAmplitude: CGFloat = 0.01
    
    func makeUIView(context: Context) -> SCSiriWaveformView {
        let view = SCSiriWaveformView()
        view.waveColor = waveColor
        view.numberOfWaves = numberOfWaves
        view.frequency = frequency
        view.idleAmplitude = idleAmplitude
        return view
    }
    
    func updateUIView(_ uiView: SCSiriWaveformView, context: Context) {
        uiView.waveColor = waveColor
        uiView.numberOfWaves = numberOfWaves
        uiView.frequency = frequency
        uiView.idleAmplitude = idleAmplitude
        uiView.isOpaque = false
        uiView.backgroundColor = .clear
        uiView.update(withLevel: level)
    }
}

