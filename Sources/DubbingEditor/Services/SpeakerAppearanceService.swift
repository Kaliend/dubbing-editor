import SwiftUI

enum SpeakerColorPaletteID: String, CaseIterable, Codable, Sendable {
    case coral
    case amber
    case lime
    case moss
    case mint
    case teal
    case cyan
    case sky
    case cobalt
    case indigo
    case rose
    case brick

    var displayName: String {
        switch self {
        case .coral:
            return "Coral"
        case .amber:
            return "Amber"
        case .lime:
            return "Lime"
        case .moss:
            return "Moss"
        case .mint:
            return "Mint"
        case .teal:
            return "Teal"
        case .cyan:
            return "Cyan"
        case .sky:
            return "Sky"
        case .cobalt:
            return "Cobalt"
        case .indigo:
            return "Indigo"
        case .rose:
            return "Rose"
        case .brick:
            return "Brick"
        }
    }
}

struct SpeakerAppearance {
    let paletteID: SpeakerColorPaletteID
    let isOverride: Bool

    var swatchColor: Color {
        SpeakerAppearanceService.swatchColor(for: paletteID)
    }

    var fieldFillColor: Color {
        swatchColor.opacity(0.14)
    }

    var fieldBorderColor: Color {
        swatchColor.opacity(0.78)
    }

    var rowAccentColor: Color {
        swatchColor.opacity(0.85)
    }
}

enum SpeakerAppearanceService {
    private static let paletteColors: [SpeakerColorPaletteID: Color] = [
        .coral: Color(.sRGB, red: 0.87, green: 0.42, blue: 0.38, opacity: 1),
        .amber: Color(.sRGB, red: 0.86, green: 0.64, blue: 0.22, opacity: 1),
        .lime: Color(.sRGB, red: 0.61, green: 0.73, blue: 0.22, opacity: 1),
        .moss: Color(.sRGB, red: 0.44, green: 0.63, blue: 0.27, opacity: 1),
        .mint: Color(.sRGB, red: 0.24, green: 0.72, blue: 0.56, opacity: 1),
        .teal: Color(.sRGB, red: 0.16, green: 0.64, blue: 0.64, opacity: 1),
        .cyan: Color(.sRGB, red: 0.19, green: 0.67, blue: 0.83, opacity: 1),
        .sky: Color(.sRGB, red: 0.30, green: 0.57, blue: 0.88, opacity: 1),
        .cobalt: Color(.sRGB, red: 0.24, green: 0.43, blue: 0.86, opacity: 1),
        .indigo: Color(.sRGB, red: 0.40, green: 0.39, blue: 0.85, opacity: 1),
        .rose: Color(.sRGB, red: 0.84, green: 0.37, blue: 0.58, opacity: 1),
        .brick: Color(.sRGB, red: 0.73, green: 0.34, blue: 0.31, opacity: 1)
    ]

    static let curatedPaletteIDs: [SpeakerColorPaletteID] = SpeakerColorPaletteID.allCases

    static func normalizedSpeakerKey(_ speaker: String) -> String {
        var normalized = String()
        normalized.reserveCapacity(speaker.count)
        var pendingSeparator = false

        for scalar in speaker.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !normalized.isEmpty {
                    pendingSeparator = true
                }
                continue
            }

            if pendingSeparator {
                normalized.append(" ")
                pendingSeparator = false
            }

            normalized.unicodeScalars.append(scalar)
        }

        return normalized.uppercased()
    }

    static func sanitizedOverrides(_ overridesByKey: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(overridesByKey.count)

        for (rawKey, rawPaletteID) in overridesByKey {
            let normalizedKey = normalizedSpeakerKey(rawKey)
            guard !normalizedKey.isEmpty else { continue }
            guard let paletteID = SpeakerColorPaletteID(rawValue: rawPaletteID) else { continue }
            sanitized[normalizedKey] = paletteID.rawValue
        }

        return sanitized
    }

    static func overridePaletteID(
        for speaker: String,
        overridesByKey: [String: String]
    ) -> SpeakerColorPaletteID? {
        let normalizedKey = normalizedSpeakerKey(speaker)
        return overridePaletteID(
            forNormalizedSpeakerKey: normalizedKey,
            overridesByKey: overridesByKey
        )
    }

    static func defaultPaletteID(for speaker: String) -> SpeakerColorPaletteID? {
        defaultPaletteID(forNormalizedSpeakerKey: normalizedSpeakerKey(speaker))
    }

    static func defaultPaletteID(forNormalizedSpeakerKey normalizedKey: String) -> SpeakerColorPaletteID? {
        guard !normalizedKey.isEmpty else { return nil }
        let palette = curatedPaletteIDs
        guard !palette.isEmpty else { return nil }
        let index = Int(stableHash(for: normalizedKey) % UInt64(palette.count))
        return palette[index]
    }

    static func resolvedPaletteID(
        for speaker: String,
        overridesByKey: [String: String]
    ) -> SpeakerColorPaletteID? {
        let normalizedKey = normalizedSpeakerKey(speaker)
        guard !normalizedKey.isEmpty else { return nil }

        if let override = overridePaletteID(
            forNormalizedSpeakerKey: normalizedKey,
            overridesByKey: overridesByKey
        ) {
            return override
        }

        return defaultPaletteID(forNormalizedSpeakerKey: normalizedKey)
    }

    static func resolvedAppearance(
        for speaker: String,
        overridesByKey: [String: String]
    ) -> SpeakerAppearance? {
        let normalizedKey = normalizedSpeakerKey(speaker)
        guard !normalizedKey.isEmpty else {
            return nil
        }

        let overridePaletteID = overridePaletteID(
            forNormalizedSpeakerKey: normalizedKey,
            overridesByKey: overridesByKey
        )
        guard let paletteID = overridePaletteID ?? defaultPaletteID(forNormalizedSpeakerKey: normalizedKey) else {
            return nil
        }

        return SpeakerAppearance(
            paletteID: paletteID,
            isOverride: overridePaletteID != nil
        )
    }

    static func swatchColor(for paletteID: SpeakerColorPaletteID) -> Color {
        paletteColors[paletteID] ?? Color.accentColor
    }

    private static func stableHash(for normalizedKey: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalizedKey.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func overridePaletteID(
        forNormalizedSpeakerKey normalizedKey: String,
        overridesByKey: [String: String]
    ) -> SpeakerColorPaletteID? {
        guard !normalizedKey.isEmpty else { return nil }
        return overridesByKey[normalizedKey].flatMap(SpeakerColorPaletteID.init(rawValue:))
    }
}
