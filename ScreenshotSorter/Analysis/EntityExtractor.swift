import Foundation
import NaturalLanguage

/// Pulls actionable entities (dates, links, phones, addresses, flights, prices, tracking
/// numbers, one-time codes, names) out of OCR text.
enum EntityExtractor {
    static let maxEntities = 40
    static let maxNamesPerType = 5

    // swiftlint:disable force_try
    private static let detector = try! NSDataDetector(types:
        NSTextCheckingResult.CheckingType.date.rawValue |
        NSTextCheckingResult.CheckingType.link.rawValue |
        NSTextCheckingResult.CheckingType.phoneNumber.rawValue |
        NSTextCheckingResult.CheckingType.address.rawValue |
        NSTextCheckingResult.CheckingType.transitInformation.rawValue
    )
    private static let upsRegex = try! NSRegularExpression(pattern: #"\b1Z[0-9A-Z]{16}\b"#)
    private static let uspsRegex = try! NSRegularExpression(pattern: #"\b(94|93|92|95)\d{20}\b"#)
    private static let otpRegex = try! NSRegularExpression(
        pattern: #"(?i)(code|passcode|otp|pin|verification)[^0-9]{0,20}(\d{4,8})\b"#
    )
    private static let timeOnlyRegex = try! NSRegularExpression(pattern: #"^\s*\d{1,2}[:.]\d{2}\s*([AaPp]\.?[Mm]\.?)?\s*$"#)
    // swiftlint:enable force_try

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter
    }()

    static func extract(from text: String, includeNames: Bool = true) -> [ExtractedEntity] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var entities: [ExtractedEntity] = []
        var seen = Set<String>()

        func add(_ type: EntityType, _ value: String, _ normalized: String?) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = type.rawValue + "|" + (normalized ?? trimmed).lowercased()
            guard !seen.contains(key), entities.count < maxEntities else { return }
            seen.insert(key)
            entities.append(ExtractedEntity(type: type, value: trimmed, normalized: normalized))
        }

        detector.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result else { return }
            let matched = ns.substring(with: result.range)
            switch result.resultType {
            case .date:
                // Skip bare clock times (status bar, chat timestamps) — they aren't useful entities
                let matchedNS = matched as NSString
                let isTimeOnly = timeOnlyRegex.firstMatch(in: matched, options: [], range: NSRange(location: 0, length: matchedNS.length)) != nil
                if !isTimeOnly, let date = result.date {
                    add(.date, matched, isoFormatter.string(from: date))
                }
            case .link:
                if let url = result.url {
                    if url.scheme == "mailto" {
                        add(.email, url.absoluteString.replacingOccurrences(of: "mailto:", with: ""), url.absoluteString)
                    } else {
                        add(.url, matched, url.absoluteString)
                    }
                }
            case .phoneNumber:
                if let phone = result.phoneNumber {
                    let digits = phone.filter { $0.isNumber || $0 == "+" }
                    if digits.count >= 7 { add(.phone, phone, digits) }
                }
            case .address:
                add(.address, matched, nil)
            case .transitInformation:
                let airline = result.components?[.airline] ?? ""
                let flight = result.components?[.flight] ?? ""
                add(.flight, matched, (airline + " " + flight).trimmingCharacters(in: .whitespaces))
            default:
                break
            }
        }

        TextNormalizer.priceRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }
            add(.price, ns.substring(with: match.range), nil)
        }
        for regex in [upsRegex, uspsRegex] {
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                add(.tracking, ns.substring(with: match.range), nil)
            }
        }
        otpRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 2 else { return }
            add(.oneTimeCode, ns.substring(with: match.range(at: 2)), nil)
        }

        if includeNames {
            for entity in names(in: text) {
                add(entity.type, entity.value, nil)
            }
        }
        return entities
    }

    /// People, places and organisations via NLTagger.
    static func names(in text: String) -> [ExtractedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [EntityType: Int] = [:]
        var result: [ExtractedEntity] = []
        var seen = Set<String>()
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            guard let tag else { return true }
            let type: EntityType
            switch tag {
            case .personalName: type = .person
            case .placeName: type = .place
            case .organizationName: type = .organization
            default: return true
            }
            let value = String(text[range])
            guard value.count > 2, counts[type, default: 0] < maxNamesPerType else { return true }
            let key = type.rawValue + value.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                counts[type, default: 0] += 1
                result.append(ExtractedEntity(type: type, value: value, normalized: nil))
            }
            return true
        }
        return result
    }
}
