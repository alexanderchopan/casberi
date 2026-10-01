import Foundation
import AVFoundation

/// A recording's ENVELOPE (prd §987.3, lifted here for the card in §1024):
/// 32 peaks off the kept bytes, 6…22pt, the player's bar anatomy, and the
/// length in seconds. One reader for the player's strip and the share
/// card's waveform, so a card never draws a shape the player would not.
enum VoiceEnvelope {
    static let barCount = 32

    /// The bytes as a file, when the caller has only bytes: a temp `.m4a`
    /// that is removed when the read is done.
    static func read(url: URL?, data: Data?, bars count: Int = VoiceEnvelope.barCount) async -> (bars: [CGFloat]?, length: Double)? {
        await Task.detached(priority: .utility) {
            var tempURL: URL?
            defer { tempURL.map { try? FileManager.default.removeItem(at: $0) } }
            let fileURL: URL
            if let url {
                fileURL = url
            } else if let data {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".m4a")
                guard (try? data.write(to: tmp)) != nil else { return nil }
                tempURL = tmp
                fileURL = tmp
            } else {
                return nil
            }
            guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
            let frameCount = AVAudioFrameCount(file.length)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: frameCount),
                  (try? file.read(into: buffer)) != nil,
                  let channelData = buffer.floatChannelData
            else { return (nil, seconds) }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            let bars = count
            guard frames > 0, channels > 0 else { return (nil, seconds) }
            let samplesPerBar = max(1, frames / bars)
            var peaks = [Float](repeating: 0, count: bars)
            for bar in 0..<bars {
                let start = bar * samplesPerBar
                let end = min(start + samplesPerBar, frames)
                guard start < end else { continue }
                var peak: Float = 0
                for ch in 0..<channels {
                    let samples = channelData[ch]
                    for i in start..<end { peak = max(peak, abs(samples[i])) }
                }
                peaks[bar] = peak
            }
            guard let maxPeak = peaks.max(), maxPeak > 0 else { return (nil, seconds) }
            // 6...22pt, the same range the old hardcoded bars drew in.
            return (peaks.map { 6 + CGFloat($0 / maxPeak) * 16 }, seconds)
        }.value
    }
}
