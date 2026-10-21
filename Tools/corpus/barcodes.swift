import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates real QR / Aztec / PDF417 barcodes for the corpus mocks.
//   swift Tools/corpus/barcodes.swift <out-dir>
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let context = CIContext()
let codes: [(String, String, String)] = [
    ("qr-wifi", "CIQRCodeGenerator", "WIFI:T:WPA;S:Cafe Lumen Guest;P:latte2024;;"),
    ("qr-url", "CIQRCodeGenerator", "https://www.example.com/menu?table=12"),
    ("qr-venmo", "CIQRCodeGenerator", "https://venmo.com/code?user_id=3141592653"),
    ("qr-event", "CIQRCodeGenerator", "TICKET-8842-ROW-F-SEAT-14-GA"),
    ("qr-vcard", "CIQRCodeGenerator", "BEGIN:VCARD\nVERSION:3.0\nN:Rivera;Sam\nTEL:+14155550133\nEND:VCARD"),
    ("aztec-boarding", "CIAztecCodeGenerator", "M1RIVERA/SAM EABC123 SFOJFKUA 0837 296Y012A0042 100"),
    ("aztec-train", "CIAztecCodeGenerator", "AMTRAK-NE-REGIONAL-171-COACH-5-SEAT-22"),
    ("pdf417-boarding", "CIPDF417BarcodeGenerator", "M1CHEN/LI EXYZ789 LAXHNDNH 0105 113J003C0007 147"),
    ("pdf417-ticket", "CIPDF417BarcodeGenerator", "EVT-2026-11-14-MSG-SEC114-ROW8-SEAT3"),
]
for (name, filter, payload) in codes {
    let f = CIFilter(name: filter)!
    f.setValue(payload.data(using: .isoLatin1), forKey: "inputMessage")
    let image = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let cg = context.createCGImage(image, from: image.extent)!
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}
print("wrote \(codes.count) barcodes to \(out.path)")
