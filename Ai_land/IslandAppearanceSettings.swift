//
//  IslandAppearanceSettings.swift
//  Ai_land
//
//  样式：十二生肖、窗口位置偏移、灵动岛与窗口尺寸（UserDefaults）
//

import SwiftUI

/// 收起态生肖、布局尺寸、灵动岛窗口相对屏幕的偏移（pt）
@MainActor
final class IslandAppearanceSettings: ObservableObject {
    static let shared = IslandAppearanceSettings()
    
    enum LayoutDefaults {
        static let windowWidth: CGFloat = 760
        /// 收起态窗口高度（pt）；药丸行高与此对齐（见 ContentView `compactPillRowHeight`）
        static let compactWindowHeight: CGFloat = 28
        static let compactContentWidth: CGFloat = 228
        static let expandedContentWidth: CGFloat = 680
    }
    
    private enum Keys {
        static let zodiac = "aiLand.zodiacRaw"
        static let offsetX = "aiLand.windowOffsetX"
        static let offsetY = "aiLand.windowOffsetY"
        static let windowWidth = "aiLand.layout.windowWidth"
        static let compactWindowHeight = "aiLand.layout.compactWindowHeight"
        static let compactContentWidth = "aiLand.layout.compactContentWidth"
        static let expandedContentWidth = "aiLand.layout.expandedContentWidth"
    }
    
    private enum LegacyKeys {
        static let zodiac = "codeIsland.zodiacRaw"
        static let offsetX = "codeIsland.windowOffsetX"
        static let offsetY = "codeIsland.windowOffsetY"
        static let windowWidth = "codeIsland.layout.windowWidth"
        static let compactWindowHeight = "codeIsland.layout.compactWindowHeight"
        static let compactContentWidth = "codeIsland.layout.compactContentWidth"
        static let expandedContentWidth = "codeIsland.layout.expandedContentWidth"
    }
    
    /// 水平：正值整体右移，负值左移（相对「居中基准」）
    @Published var windowOffsetX: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(windowOffsetX), forKey: Keys.offsetX)
            scheduleIslandWindowFrameResync()
        }
    }
    /// 垂直：正值整体上移，负值下移（macOS 坐标，底边为 0）
    @Published var windowOffsetY: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(windowOffsetY), forKey: Keys.offsetY)
            scheduleIslandWindowFrameResync()
        }
    }
    
    @Published var zodiac: IslandZodiac {
        didSet { UserDefaults.standard.set(zodiac.rawValue, forKey: Keys.zodiac) }
    }
    
    /// `NSWindow` 总宽度（用于水平居中与阴影边距）
    @Published var islandWindowWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(islandWindowWidth), forKey: Keys.windowWidth)
            scheduleIslandWindowFrameResync()
        }
    }
    /// 收起态窗口高度（含阴影与底边留白）
    @Published var islandCompactWindowHeight: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(islandCompactWindowHeight), forKey: Keys.compactWindowHeight)
            scheduleIslandWindowFrameResync()
        }
    }
    /// 收起态药丸内容区宽度
    @Published var islandCompactContentWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(islandCompactContentWidth), forKey: Keys.compactContentWidth)
            scheduleIslandWindowFrameResync()
        }
    }
    /// 展开态面板内容宽度
    @Published var islandExpandedContentWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(islandExpandedContentWidth), forKey: Keys.expandedContentWidth) }
    }
    
    private init() {
        let ud = UserDefaults.standard
        Self.migrateIntIfNeeded(ud, key: Keys.zodiac, legacy: LegacyKeys.zodiac)
        let zRaw = ud.object(forKey: Keys.zodiac) as? Int ?? IslandZodiac.rabbit.rawValue
        zodiac = IslandZodiac(rawValue: zRaw) ?? .rabbit
        
        windowOffsetX = CGFloat(Self.migratedDouble(ud, key: Keys.offsetX, legacy: LegacyKeys.offsetX))
        windowOffsetY = CGFloat(Self.migratedDouble(ud, key: Keys.offsetY, legacy: LegacyKeys.offsetY))
        
        islandWindowWidth = Self.migratedLayoutDimension(
            ud, key: Keys.windowWidth, legacy: LegacyKeys.windowWidth, default: LayoutDefaults.windowWidth
        )
        islandCompactWindowHeight = Self.migratedLayoutDimension(
            ud, key: Keys.compactWindowHeight, legacy: LegacyKeys.compactWindowHeight, default: LayoutDefaults.compactWindowHeight
        )
        islandCompactContentWidth = Self.migratedLayoutDimension(
            ud, key: Keys.compactContentWidth, legacy: LegacyKeys.compactContentWidth, default: LayoutDefaults.compactContentWidth
        )
        islandExpandedContentWidth = Self.migratedLayoutDimension(
            ud, key: Keys.expandedContentWidth, legacy: LegacyKeys.expandedContentWidth, default: LayoutDefaults.expandedContentWidth
        )
    }
    
    private static func migrateIntIfNeeded(_ ud: UserDefaults, key: String, legacy: String) {
        guard ud.object(forKey: key) == nil, let v = ud.object(forKey: legacy) as? Int else { return }
        ud.set(v, forKey: key)
        ud.removeObject(forKey: legacy)
    }
    
    private static func migratedDouble(_ ud: UserDefaults, key: String, legacy: String) -> Double {
        if ud.object(forKey: key) != nil {
            return ud.double(forKey: key)
        }
        if ud.object(forKey: legacy) != nil {
            let v = ud.double(forKey: legacy)
            ud.set(v, forKey: key)
            ud.removeObject(forKey: legacy)
            return v
        }
        return 0
    }
    
    private static func migratedLayoutDimension(
        _ ud: UserDefaults,
        key: String,
        legacy: String,
        default def: CGFloat
    ) -> CGFloat {
        if ud.object(forKey: key) != nil {
            return CGFloat(ud.double(forKey: key))
        }
        if ud.object(forKey: legacy) != nil {
            let v = ud.double(forKey: legacy)
            ud.set(v, forKey: key)
            ud.removeObject(forKey: legacy)
            return CGFloat(v)
        }
        return def
    }
    
    private func scheduleIslandWindowFrameResync() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .aiLandReapplyWindowFrame, object: nil)
        }
    }
    
    func resetWindowOffset() {
        windowOffsetX = 0
        windowOffsetY = 0
    }
    
    func resetLayoutDimensionsToDefaults() {
        islandWindowWidth = LayoutDefaults.windowWidth
        islandCompactWindowHeight = LayoutDefaults.compactWindowHeight
        islandCompactContentWidth = LayoutDefaults.compactContentWidth
        islandExpandedContentWidth = LayoutDefaults.expandedContentWidth
        UserDefaults.standard.set(Double(LayoutDefaults.windowWidth), forKey: Keys.windowWidth)
        UserDefaults.standard.set(Double(LayoutDefaults.compactWindowHeight), forKey: Keys.compactWindowHeight)
        UserDefaults.standard.set(Double(LayoutDefaults.compactContentWidth), forKey: Keys.compactContentWidth)
        UserDefaults.standard.set(Double(LayoutDefaults.expandedContentWidth), forKey: Keys.expandedContentWidth)
    }
    
    /// 实际用于 `NSWindow` 的宽度：不小于两侧内容较大者 + 边距，避免裁切（不改写 UserDefaults 中的「首选宽度」）。
    var effectiveIslandWindowWidth: CGFloat {
        let minW = max(islandCompactContentWidth, islandExpandedContentWidth) + 48
        return max(islandWindowWidth, minW)
    }
}
