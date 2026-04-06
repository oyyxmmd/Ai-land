//
//  IslandZodiac.swift
//  Ai_land
//
//  十二生肖：展示名；收起态动物图标配色见 IslandZodiacSprites.swift（layerColor）
//

import Foundation

enum IslandZodiac: Int, CaseIterable, Identifiable {
    case rat = 0, ox, tiger, rabbit, dragon, snake, horse, goat, monkey, rooster, dog, pig
    
    var id: Int { rawValue }
    
    /// 单字简称（界面）
    var han: String {
        switch self {
        case .rat: return "鼠"
        case .ox: return "牛"
        case .tiger: return "虎"
        case .rabbit: return "兔"
        case .dragon: return "龙"
        case .snake: return "蛇"
        case .horse: return "马"
        case .goat: return "羊"
        case .monkey: return "猴"
        case .rooster: return "鸡"
        case .dog: return "狗"
        case .pig: return "猪"
        }
    }
    
    /// 随应用语言（中英）切换的短名
    var localizedShortName: String {
        switch self {
        case .rat: return L10n.str("zodiac_rat")
        case .ox: return L10n.str("zodiac_ox")
        case .tiger: return L10n.str("zodiac_tiger")
        case .rabbit: return L10n.str("zodiac_rabbit")
        case .dragon: return L10n.str("zodiac_dragon")
        case .snake: return L10n.str("zodiac_snake")
        case .horse: return L10n.str("zodiac_horse")
        case .goat: return L10n.str("zodiac_goat")
        case .monkey: return L10n.str("zodiac_monkey")
        case .rooster: return L10n.str("zodiac_rooster")
        case .dog: return L10n.str("zodiac_dog")
        case .pig: return L10n.str("zodiac_pig")
        }
    }
}
