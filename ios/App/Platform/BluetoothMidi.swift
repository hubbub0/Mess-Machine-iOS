import CoreAudioKit
import SwiftUI

/// Apple's own Bluetooth MIDI pairing screen. Pair a controller here once; after that it shows up as a normal
/// CoreMIDI source and MidiIn picks it up like a USB one.
struct BluetoothMidiPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CABTMIDICentralViewController()
        vc.title = "Bluetooth MIDI"
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}
}
