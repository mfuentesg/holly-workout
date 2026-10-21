import AVFoundation

/// Plays inaudible audio so iOS keeps the app running with the screen locked.
/// No sounds are made; the session mixes with whatever else is playing.
@MainActor
final class Cues {
    static let shared = Cues()

    private var silence: AVAudioPlayer?

    private init() {
        silence = Self.silentPlayer()
        silence?.numberOfLoops = -1
    }

    func activate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        silence?.play()
    }

    func deactivate() {
        silence?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One second of 16-bit mono PCM zeros in a WAV container.
    private static func silentPlayer() -> AVAudioPlayer? {
        let rate: UInt32 = 44100
        let bytes = rate * 2
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(rate); put(rate * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        data.append(Data(count: Int(bytes)))
        let p = try? AVAudioPlayer(data: data)
        p?.volume = 0
        p?.prepareToPlay()
        return p
    }
}
