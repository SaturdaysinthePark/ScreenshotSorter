#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Debug-only: writes downscaled copies of the library's screenshots into the app's Documents folder as one
/// tar archive (`qa-export.tar`), for the judge eval on a Mac (`Tools/eval/judge`). Launch with
/// `-QAExportScreenshots <count>` (0 = all). Uses on-device previews only, so nothing is downloaded.
/// Never compiled into release builds: the archive holds the owner's own screenshots.
enum QAExport {
    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "QAExport")
    static let maxPixel: CGFloat = 1024

    static func runIfRequested(ids: [(id: String, date: Date)]) async {
        guard UserDefaults.standard.object(forKey: "QAExportScreenshots") != nil else { return }
        let limit = UserDefaults.standard.integer(forKey: "QAExportScreenshots")
        let chosen = limit > 0 ? Array(ids.prefix(limit)) : ids
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let archive = documents.appendingPathComponent("qa-export.tar")
        try? FileManager.default.removeItem(at: archive)
        FileManager.default.createFile(atPath: archive.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: archive) else { return }
        defer { try? handle.close() }

        var manifest: [[String: Any]] = []
        let formatter = ISO8601DateFormatter()
        for (index, item) in chosen.enumerated() {
            guard let image = await PhotoImageLoader.loadLocalPreview(id: item.id, maxPixel: maxPixel, minimumPixel: 300),
                  let jpeg = jpegData(image) else { continue }
            let name = "img/" + (item.id.split(separator: "/").first.map(String.init) ?? "\(index)") + ".jpg"
            write(name: name, data: jpeg, to: handle)
            manifest.append(["file": name, "id": item.id, "date": formatter.string(from: item.date)])
            if index % 100 == 99 { logger.notice("QA export \(index + 1, privacy: .public)/\(chosen.count, privacy: .public)") }
        }
        if let json = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]) {
            write(name: "export.json", data: json, to: handle)
        }
        handle.write(Data(count: 1024)) // end-of-archive marker
        logger.notice("QA export done: \(manifest.count, privacy: .public) screenshots → \(archive.path, privacy: .public)")
    }

    private static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// One ustar entry: 512-byte header, the bytes, padding to a 512-byte boundary
    private static func write(name: String, data: Data, to handle: FileHandle) {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ string: String, at offset: Int, length: Int) {
            for (index, byte) in string.utf8.prefix(length).enumerated() { header[offset + index] = byte }
        }
        put(name, at: 0, length: 100)
        put("0000644\0", at: 100, length: 8)
        put("0000000\0", at: 108, length: 8)
        put("0000000\0", at: 116, length: 8)
        put(String(format: "%011o\0", data.count), at: 124, length: 12)
        put(String(format: "%011o\0", Int(Date().timeIntervalSince1970)), at: 136, length: 12)
        put("        ", at: 148, length: 8)
        header[156] = UInt8(ascii: "0")
        put("ustar\0", at: 257, length: 6)
        put("00", at: 263, length: 2)
        let checksum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o\0 ", checksum), at: 148, length: 8)
        handle.write(Data(header))
        handle.write(data)
        let padding = (512 - data.count % 512) % 512
        if padding > 0 { handle.write(Data(count: padding)) }
    }
}
#endif
