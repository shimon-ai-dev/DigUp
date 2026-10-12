// Only public, locally generated probe fixtures. Never opens a user document.
import AppKit
@preconcurrency import AVFoundation
import CoreVideo
import Foundation

@main struct MediaProbeFixtures {
    static func screenshot(_ path: String, title: String, lines: [String]) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
        NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 735, width: 1200, height: 65).fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill(); NSBezierPath(ovalIn: NSRect(x: CGFloat(25 + i * 24), y: 757, width: 14, height: 14)).fill()
        }
        for (i, text) in ([title] + lines).enumerated() {
            let y = CGFloat(640 - i * 88)
            (text as NSString).draw(at: NSPoint(x: 70, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: i == 0 ? 38 : 29, weight: i == 0 ? .bold : .regular),
                .foregroundColor: i == 0 ? NSColor.systemBlue : NSColor.black,
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    static func video(image: URL, audio: URL, output: URL) async throws {
        let temporary = output.deletingLastPathComponent().appendingPathComponent("f061-silent.mov")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let sound = AVURLAsset(url: audio)
        let duration = max(12.0, try await sound.load(.duration).seconds)
        guard let image = NSImage(contentsOf: image), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing frame image"]) }
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1200, AVVideoHeightKey: 800,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1200, kCVPixelBufferHeightKey as String: 800,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        var optionalPixel: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 1200, 800, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &optionalPixel)
        guard status == kCVReturnSuccess, let pixel = optionalPixel else { throw NSError(domain: "probe", code: 2) }
        CVPixelBufferLockBaseAddress(pixel, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 1200, height: 800, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1200, height: 800))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for frame in 0..<Int(ceil(duration * 2)) {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error! }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 2))
            else { throw writer.error ?? NSError(domain: "probe", code: 3) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "probe", code: 4) }
        let movie = AVURLAsset(url: temporary)
        let composition = AVMutableComposition()
        let movieTrack = try await movie.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await sound.loadTracks(withMediaType: .audio)[0]
        let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let targetAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: try await movie.load(.duration)), of: movieTrack, at: .zero)
        try targetAudio.insertTimeRange(CMTimeRange(start: .zero, duration: try await sound.load(.duration)), of: audioTrack, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw NSError(domain: "probe", code: 5) }
        try await exporter.export(to: output, as: .mp4)
    }

    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "screenshots" {
            try screenshot(args[2] + "/Screenshot-f031.png", title: "Airport departure notice", lines: [
                "Flight to Tokyo delayed by two hours", "Reason: storm and severe weather", "Please wait near the departure gate",
            ])
            try screenshot(args[2] + "/Screenshot-f032.png", title: "季度业务报告", lines: [
                "本季度营业收入增长百分之二十", "欧洲市场销售表现强劲", "下一季度继续提高服务质量",
            ])
        } else if args.count == 5, args[1] == "video" {
            try await video(image: URL(fileURLWithPath: args[2]), audio: URL(fileURLWithPath: args[3]),
                            output: URL(fileURLWithPath: args[4]))
        } else {
            throw NSError(domain: "probe", code: 6, userInfo: [NSLocalizedDescriptionKey: "screenshots DIR | video IMAGE AUDIO OUTPUT"])
        }
    }
}
