import MediaPlayer
import UIKit

/// Keeps Mess Machine playing when you leave the app, with a Stop control (Android: PlaybackService.kt).
/// iOS keeps audio apps alive through the `audio` background mode in Info.plist; this adds the lock screen and
/// Control Center entry, so Stop is one tap away the way Android's notification gives it.
final class Background {
    private var stopHandler: (() -> Void)?
    private var targets: [Any] = []

    func playing(line: String, stop: @escaping () -> Void) {
        stopHandler = stop
        let center = MPRemoteCommandCenter.shared()
        if targets.isEmpty {
            for cmd in [center.stopCommand, center.pauseCommand, center.togglePlayPauseCommand] {
                cmd.isEnabled = true
                targets.append(cmd.addTarget { [weak self] _ in self?.stopHandler?(); return .success })
            }
            center.playCommand.isEnabled = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Mess Machine is playing",
            MPMediaItemPropertyArtist: line,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    func stopped() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}

/// The pad buzz (Android: a short vibration on a pad hit).
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    static func pad(strong: Bool = false) {
        (strong ? rigid : light).impactOccurred()
    }

    static func prepare() { light.prepare(); rigid.prepare() }
}
