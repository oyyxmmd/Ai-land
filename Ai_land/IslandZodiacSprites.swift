//
//  IslandZodiacSprites.swift
//  Ai_land
//
//  十二生肖配色与 layer 定义（原 9×6 精灵数据仍供 layerColor / runningBaseColor 使用）
//

import SwiftUI

private let spriteChars: [Character: UInt8] = [
    ".": 0, " ": 0,
    "a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6
]

extension IslandZodiac {
    /// 6 行 × 9 列；字符见文件头说明
    fileprivate var spriteRows: [String] {
        switch self {
        case .rat:
            return [
                "....dd...",
                "..ddaadd.",
                ".eaaabaae",
                ".abbbbbba",
                "..abbbba.",
                "...ccc..."
            ]
        case .ox:
            return [
                "..f...f..",
                ".fddcdddf",
                ".eaaaaaae",
                ".abbbbbba",
                "..abbbba.",
                "...bab..."
            ]
        case .tiger:
            return [
                "...d.d...",
                ".fcaaacaf",
                ".eabbbbae",
                ".abcccbba",
                "..abbbba.",
                ".c..b..c."
            ]
        case .rabbit:
            return [
                ".d.....d.",
                ".db...bd.",
                ".ebbbbbae",
                "..abbbba.",
                "...abba..",
                "....bb..."
            ]
        case .dragon:
            return [
                "...fff...",
                "..fdddf..",
                ".eabffbae",
                ".abbbbbba",
                "..abffba.",
                ".cc....cc"
            ]
        case .snake:
            return [
                "....dd...",
                ".eabbbbae",
                "..bbaabb.",
                ".bba...ab",
                "..bbaabb.",
                "...abba.."
            ]
        case .horse:
            return [
                "...fff...",
                ".ffaaaaff",
                ".eaaaaaae",
                ".abbbbbba",
                "..abbbba.",
                ".c..bb..c"
            ]
        case .goat:
            return [
                ".f.....f.",
                ".fddcdddf",
                ".eaaaaaae",
                "..abbbba.",
                ".aabddbaa",
                "...dd...."
            ]
        case .monkey:
            return [
                "...ddd...",
                ".ddaaadd.",
                ".ebbbbbae",
                ".abbbcbba",
                "..abddba.",
                "...cccc.."
            ]
        case .rooster:
            return [
                "..ddddddd",
                ".dddddddd",
                ".ebbbbbae",
                ".abbbbbba",
                "..abbbba.",
                ".cbbbbbc."
            ]
        case .dog:
            return [
                ".d.....d.",
                ".ddaaadd.",
                ".ebbbbbae",
                ".abbbbbba",
                "..abbbba.",
                "...ccc..."
            ]
        case .pig:
            return [
                "...ddd...",
                "..ddadd..",
                ".ebbbbbae",
                ".abbbdaba",
                "..abbbba.",
                "...ccc..."
            ]
        }
    }
    
    /// 分层着色（1…6）；phase 微调饱和度/明暗
    func layerColor(_ layer: UInt8, phase: PixelIslandCompactPhase) -> Color {
        guard layer >= 1, layer <= 6 else { return .clear }
        let boost: CGFloat = {
            switch phase {
            case .waiting: return 1.0
            case .running: return 1.05
            case .waitingConfirm: return 1.06
            case .completed: return 1.12
            }
        }()
        func lit(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(
                red: min(1, r * Double(boost)),
                green: min(1, g * Double(boost)),
                blue: min(1, b * Double(boost))
            )
        }
        switch self {
        case .rat:
            switch layer {
            case 1: return lit(0.62, 0.58, 0.68)
            case 2: return lit(0.78, 0.74, 0.88)
            case 3: return lit(0.38, 0.34, 0.42)
            case 4: return lit(0.98, 0.72, 0.82)
            case 5: return lit(0.12, 0.1, 0.14)
            case 6: return lit(0.5, 0.45, 0.55)
            default: return .clear
            }
        case .ox:
            switch layer {
            case 1: return lit(0.55, 0.4, 0.28)
            case 2: return lit(0.82, 0.72, 0.58)
            case 3: return lit(0.32, 0.22, 0.14)
            case 4: return lit(0.72, 0.58, 0.42)
            case 5: return lit(0.1, 0.08, 0.06)
            case 6: return lit(0.88, 0.78, 0.55)
            default: return .clear
            }
        case .tiger:
            switch layer {
            case 1: return lit(0.95, 0.58, 0.18)
            case 2: return lit(1.0, 0.82, 0.55)
            case 3: return lit(0.15, 0.12, 0.1)
            case 4: return lit(0.95, 0.35, 0.12)
            case 5: return lit(0.08, 0.06, 0.05)
            case 6: return lit(0.2, 0.18, 0.16)
            default: return .clear
            }
        case .rabbit:
            switch layer {
            case 1: return lit(0.92, 0.9, 0.92)
            case 2: return lit(1.0, 0.98, 1.0)
            case 3: return lit(0.65, 0.62, 0.68)
            case 4: return lit(0.98, 0.75, 0.88)
            case 5: return lit(0.2, 0.18, 0.22)
            case 6: return lit(0.88, 0.82, 0.9)
            default: return .clear
            }
        case .dragon:
            switch layer {
            case 1: return lit(0.22, 0.72, 0.48)
            case 2: return lit(0.45, 0.92, 0.68)
            case 3: return lit(0.12, 0.42, 0.32)
            case 4: return lit(0.95, 0.35, 0.28)
            case 5: return lit(0.95, 0.88, 0.35)
            case 6: return lit(0.98, 0.82, 0.22)
            default: return .clear
            }
        case .snake:
            switch layer {
            case 1: return lit(0.28, 0.68, 0.42)
            case 2: return lit(0.55, 0.88, 0.52)
            case 3: return lit(0.12, 0.38, 0.22)
            case 4: return lit(0.85, 0.9, 0.35)
            case 5: return lit(0.15, 0.55, 0.25)
            case 6: return lit(0.4, 0.75, 0.45)
            default: return .clear
            }
        case .horse:
            switch layer {
            case 1: return lit(0.58, 0.4, 0.26)
            case 2: return lit(0.78, 0.62, 0.45)
            case 3: return lit(0.28, 0.2, 0.14)
            case 4: return lit(0.45, 0.32, 0.22)
            case 5: return lit(0.08, 0.06, 0.05)
            case 6: return lit(0.18, 0.14, 0.12)
            default: return .clear
            }
        case .goat:
            switch layer {
            case 1: return lit(0.9, 0.9, 0.92)
            case 2: return lit(1.0, 1.0, 1.0)
            case 3: return lit(0.55, 0.55, 0.58)
            case 4: return lit(0.95, 0.82, 0.88)
            case 5: return lit(0.15, 0.14, 0.16)
            case 6: return lit(0.82, 0.8, 0.78)
            default: return .clear
            }
        case .monkey:
            switch layer {
            case 1: return lit(0.72, 0.52, 0.38)
            case 2: return lit(0.88, 0.7, 0.55)
            case 3: return lit(0.42, 0.28, 0.2)
            case 4: return lit(0.95, 0.72, 0.58)
            case 5: return lit(0.12, 0.1, 0.08)
            case 6: return lit(0.55, 0.38, 0.28)
            default: return .clear
            }
        case .rooster:
            switch layer {
            case 1: return lit(0.85, 0.65, 0.2)
            case 2: return lit(0.98, 0.88, 0.45)
            case 3: return lit(0.35, 0.22, 0.12)
            case 4: return lit(0.95, 0.18, 0.15)
            case 5: return lit(0.08, 0.06, 0.05)
            case 6: return lit(0.92, 0.25, 0.18)
            default: return .clear
            }
        case .dog:
            switch layer {
            case 1: return lit(0.78, 0.58, 0.32)
            case 2: return lit(0.92, 0.78, 0.55)
            case 3: return lit(0.42, 0.3, 0.18)
            case 4: return lit(0.62, 0.42, 0.28)
            case 5: return lit(0.1, 0.08, 0.06)
            case 6: return lit(0.55, 0.4, 0.28)
            default: return .clear
            }
        case .pig:
            switch layer {
            case 1: return lit(0.95, 0.72, 0.82)
            case 2: return lit(1.0, 0.88, 0.92)
            case 3: return lit(0.72, 0.48, 0.58)
            case 4: return lit(0.98, 0.55, 0.68)
            case 5: return lit(0.35, 0.22, 0.28)
            case 6: return lit(0.88, 0.5, 0.62)
            default: return .clear
            }
        }
    }
    
    /// 奔跑态：主色与主题青绿混合，保留生肖色相
    func runningBaseColor(accent: Bool) -> Color {
        if accent {
            return Color(red: 1.0, green: 0.38, blue: 0.52)
        }
        let tr = 0.32, tg = 0.82, tb = 0.76
        func mix(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(
                red: r * 0.5 + tr * 0.5,
                green: g * 0.5 + tg * 0.5,
                blue: b * 0.5 + tb * 0.5
            )
        }
        switch self {
        case .rat: return mix(0.62, 0.58, 0.68)
        case .ox: return mix(0.55, 0.4, 0.28)
        case .tiger: return mix(0.95, 0.58, 0.18)
        case .rabbit: return mix(0.92, 0.9, 0.92)
        case .dragon: return mix(0.22, 0.72, 0.48)
        case .snake: return mix(0.28, 0.68, 0.42)
        case .horse: return mix(0.58, 0.4, 0.26)
        case .goat: return mix(0.9, 0.9, 0.92)
        case .monkey: return mix(0.72, 0.52, 0.38)
        case .rooster: return mix(0.85, 0.65, 0.2)
        case .dog: return mix(0.78, 0.58, 0.32)
        case .pig: return mix(0.95, 0.72, 0.82)
        }
    }
}

// MARK: - 分层网格

enum IslandZodiacLayers {
    private static var cache: [IslandZodiac: [UInt8]] = [:]
    
    static func layer(z: IslandZodiac, r: Int, c: Int) -> UInt8 {
        guard r >= 0, r < 6, c >= 0, c < 9 else { return 0 }
        return grid(z)[r * 9 + c]
    }
    
    static func grid(_ z: IslandZodiac) -> [UInt8] {
        if let c = cache[z] { return c }
        var out = [UInt8](repeating: 0, count: 54)
        let rows = z.spriteRows
        for (r, line) in rows.prefix(6).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for (c, ch) in trimmed.prefix(9).enumerated() {
                let i = r * 9 + c
                if i < 54 { out[i] = spriteChars[ch] ?? 0 }
            }
        }
        cache[z] = out
        return out
    }
}
