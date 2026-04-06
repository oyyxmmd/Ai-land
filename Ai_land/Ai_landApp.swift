//
//  Ai_landApp.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import SwiftUI
import AppKit
import ObjectiveC
import os.log

extension Notification.Name {
    /// 供需要时手动触发 `IslandWindowFrameObserver` 再跑一次 `applyFrame`。
    /// 跳转外置终端时不在「降级层级」同一拍同步 post，改由 `scheduleFrameResyncAfterExternalActivation` 在下一帧与短延迟后对齐，避免瞬时 `window.screen == nil` 误用主屏导致错位。
    static let aiLandReapplyWindowFrame = Notification.Name("aiLandReapplyWindowFrame")
}

private let appOpenURLLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "xiaoo.ai-land",
    category: "openURL"
)

/// 按 host 分发，避免 `task` URL 误入 `InteractionManager`（产生误导日志与无效解析）。
/// 岛窗口默认 `level == .mainMenu + 1`，会压在普通应用之上；从列表跳转外置终端时即使对方已 `activate` 也像「没跳过去」。跳转前短暂降到 `.normal`，再恢复。仅在主线程使用。
final class IslandWindowChromeController {
    static let shared = IslandWindowChromeController()
    private weak var registeredWindow: NSWindow?
    private var restoreWorkItem: DispatchWorkItem?
    
    /// 主岛窗口已聚焦时不再弹出收起态「完成」Peek（用户正在看岛上界面）。
    var isIslandWindowKey: Bool {
        registeredWindow?.isKeyWindow == true
    }
    
    func registerIslandWindow(_ window: NSWindow?) {
        if let window { registeredWindow = window }
    }
    
    /// 供 `IslandWindowFrameObserver.Coordinator` 在层级恢复后重新对齐 frame。
    func registeredWindowForFrameSync() -> NSWindow? {
        registeredWindow
    }
    
    /// 激活外部应用后：下一帧与约 0.12s 后再各触发一次 `applyFrame`，修正 `window.screen` 暂空或非本屏时的几何错位（不与 SwiftUI 同拍抢 `setFrame`）。
    func scheduleFrameResyncAfterExternalActivation() {
        let post = {
            NotificationCenter.default.post(name: .aiLandReapplyWindowFrame, object: nil)
        }
        DispatchQueue.main.async(execute: post)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: post)
    }
    
    /// 在激活 Terminal / IDE 等目标应用前调用；仅当当前层级高于 normal 时才降级。
    func temporarilyLowerForTargetAppActivation(duration: TimeInterval = 0.65) {
        restoreWorkItem?.cancel()
        guard let window = registeredWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isSheet }) else { return }
        let savedLevel = window.level
        guard savedLevel.rawValue > NSWindow.Level.normal.rawValue else { return }
        window.level = .normal
        let work = DispatchWorkItem { [weak window] in
            guard let window else { return }
            window.level = savedLevel
            // 回到 `.mainMenu + 1` 后再对齐一次，避免层级切换后系统/布局与屏坐标不同步。
            NotificationCenter.default.post(name: .aiLandReapplyWindowFrame, object: nil)
        }
        restoreWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}

private func dispatchAiLandURL(_ url: URL) {
    AiLandURLRouting.dispatchOnMainActor(url)
}

/// accessory + 无边框时，SwiftUI `onOpenURL` 有时收不到 `open ai-land://…`；必须由 AppKit 入口转发。
final class AiLandAppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 尽早设为 accessory，避免岛窗首配之前仍以普通应用短暂出现在 Dock。
        // `configureWindow` 内仍会再设一次，行为一致且无害。
        NSApp.setActivationPolicy(.accessory)
        _ = SocketManager.shared
    }
    
    /// 标题栏退出、⌘Q、菜单「退出」等均走 `terminate`，在此统一确认，避免误关。
    /// 岛窗 `level == .mainMenu + 1` 时，`runModal()` 的独立 Alert 会叠在岛下面被挡住；改为挂 sheet 到岛窗/前台窗，或临时降级后再 `runModal()`。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = L10n.fmt("quit_title_format", IslandTheme.appDisplayName)
        alert.informativeText = L10n.str("quit_message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.str("quit_cancel"))
        alert.addButton(withTitle: L10n.str("quit_confirm"))
        
        let hostWindow = IslandWindowChromeController.shared.registeredWindowForFrameSync()
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && !$0.isSheet })
        
        if let window = hostWindow {
            alert.beginSheetModal(for: window) { response in
                NSApp.reply(toApplicationShouldTerminate: response == .alertSecondButtonReturn)
            }
            return .terminateLater
        }
        
        NSApp.activate(ignoringOtherApps: true)
        let island = IslandWindowChromeController.shared.registeredWindowForFrameSync()
        let savedLevel = island?.level
        island?.level = .normal
        let response = alert.runModal()
        if let island, let savedLevel {
            island.level = savedLevel
        }
        if response == .alertSecondButtonReturn {
            return .terminateNow
        }
        return .terminateCancel
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        appOpenURLLog.info("NSApplicationDelegate open urls count=\(urls.count)")
        DispatchQueue.main.async {
            for url in urls {
                appOpenURLLog.info("delegate URL \(url.absoluteString, privacy: .public)")
                dispatchAiLandURL(url)
            }
        }
    }
}

/// 默认无边框 `NSWindow` 往往 `canBecomeKey == false`，SwiftUI 按钮/快捷键在岛上会「点了没反应」。
private final class KeyableIslandWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    override func becomeKey() {
        super.becomeKey()
        TaskActivityManager.shared.dismissCompletionToast()
    }
}

@main
struct Ai_landApp: App {
    @NSApplicationDelegateAdaptor(AiLandAppDelegate.self) private var appDelegate
    @ObservedObject private var appLanguage = AppLanguageSettings.shared

    var body: some Scene {
        // 单窗口场景：`WindowGroup` 在每次 `open ai-land://…` 时容易再开一个新「灵动岛」窗口。
        Window(IslandTheme.appDisplayName, id: "ai-land-main") {
            ContentView()
                .appPreferredLocale(appLanguage)
                .environmentObject(appLanguage)
                .onOpenURL { url in
                    appOpenURLLog.info("onOpenURL received \(url.absoluteString, privacy: .public)")
                    dispatchAiLandURL(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        // 外部 URL 交给已有窗口处理，避免系统再创建第二个 Scene。
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        
        Settings {
            AiLandSettingsView()
                .appPreferredLocale(appLanguage)
                .environmentObject(appLanguage)
        }
    }
}

// 辅助视图：配置无边框窗口，并按 IslandAppearanceSettings 应用位置偏移
struct IslandWindowFrameObserver: NSViewRepresentable {
    @ObservedObject var appearance: IslandAppearanceSettings
    /// 有「问道 / 工具权限」面板时窗口高度由 `interactionIslandLayoutHeight` 驱动
    var interactionActive: Bool
    /// 与 ContentView 一致：有交互或用户悬停展开
    var islandExpanded: Bool
    /// 岛上裁剪后的实际布局高度（SwiftUI `onGeometryChange`），仅 `interactionActive` 时参与计算
    var interactionIslandLayoutHeight: CGFloat
    /// 任务/计划展开面板（非「问道」）的 SwiftUI 实测高度，用于窗高随列表撑开
    var expandedIslandLayoutHeight: CGFloat
    /// 收起态显示 CLI 完成条时，窗口需高于 `windowHeightCompact`，否则 overlay 被裁切
    var showsCompletionToast: Bool
    /// 收起态岛体 SwiftUI 实测高度（含完成 Peek）；用于窗高随内容收紧，避免固定预留造成大块留白
    var collapsedIslandLayoutHeight: CGFloat
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.bind(
            appearance: appearance,
            interactionActive: interactionActive,
            islandExpanded: islandExpanded,
            interactionIslandLayoutHeight: interactionIslandLayoutHeight,
            expandedIslandLayoutHeight: expandedIslandLayoutHeight,
            showsCompletionToast: showsCompletionToast,
            collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
        )
        let appearance = appearance
        let interactionActive = interactionActive
        let islandExpanded = islandExpanded
        let interactionIslandLayoutHeight = interactionIslandLayoutHeight
        let expandedIslandLayoutHeight = expandedIslandLayoutHeight
        let showsCompletionToast = showsCompletionToast
        let collapsedIslandLayoutHeight = collapsedIslandLayoutHeight
        DispatchQueue.main.async {
            Self.configureWindow(
                view.window,
                appearance: appearance,
                interactionActive: interactionActive,
                islandExpanded: islandExpanded,
                interactionIslandLayoutHeight: interactionIslandLayoutHeight,
                expandedIslandLayoutHeight: expandedIslandLayoutHeight,
                showsCompletionToast: showsCompletionToast,
                collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
            )
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bind(
            appearance: appearance,
            interactionActive: interactionActive,
            islandExpanded: islandExpanded,
            interactionIslandLayoutHeight: interactionIslandLayoutHeight,
            expandedIslandLayoutHeight: expandedIslandLayoutHeight,
            showsCompletionToast: showsCompletionToast,
            collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
        )
        guard let window = nsView.window else { return }
        let oid = ObjectIdentifier(window)
        // 首帧/首次挂窗仍走 async 完整配置；之后每帧同步 applyFrame，避免收起岛、Toast、层级变化晚一帧才改几何。
        if Self.islandChromeConfiguredWindows.contains(oid) {
            IslandWindowChromeController.shared.registerIslandWindow(window)
            Self.applyFrame(
                window: window,
                appearance: appearance,
                interactionActive: interactionActive,
                islandExpanded: islandExpanded,
                interactionIslandLayoutHeight: interactionIslandLayoutHeight,
                expandedIslandLayoutHeight: expandedIslandLayoutHeight,
                showsCompletionToast: showsCompletionToast,
                collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
            )
            return
        }
        let appearance = appearance
        let interactionActive = interactionActive
        let islandExpanded = islandExpanded
        let interactionIslandLayoutHeight = interactionIslandLayoutHeight
        let expandedIslandLayoutHeight = expandedIslandLayoutHeight
        let showsCompletionToast = showsCompletionToast
        let collapsedIslandLayoutHeight = collapsedIslandLayoutHeight
        // 窗口已附着时同步配置并立刻贴屏顶，避免再走 async 晚一帧仍停留在 Scene 默认位置（菜单位下方）。
        Self.configureWindow(
            window,
            appearance: appearance,
            interactionActive: interactionActive,
            islandExpanded: islandExpanded,
            interactionIslandLayoutHeight: interactionIslandLayoutHeight,
            expandedIslandLayoutHeight: expandedIslandLayoutHeight,
            showsCompletionToast: showsCompletionToast,
            collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    @MainActor
    final class Coordinator {
        private var appearance: IslandAppearanceSettings?
        private var interactionActive = false
        private var islandExpanded = false
        private var interactionIslandLayoutHeight: CGFloat = 0
        private var expandedIslandLayoutHeight: CGFloat = 0
        private var showsCompletionToast = false
        private var collapsedIslandLayoutHeight: CGFloat = 0
        private var observer: NSObjectProtocol?
        
        func bind(
            appearance: IslandAppearanceSettings,
            interactionActive: Bool,
            islandExpanded: Bool,
            interactionIslandLayoutHeight: CGFloat,
            expandedIslandLayoutHeight: CGFloat,
            showsCompletionToast: Bool,
            collapsedIslandLayoutHeight: CGFloat
        ) {
            self.appearance = appearance
            self.interactionActive = interactionActive
            self.islandExpanded = islandExpanded
            self.interactionIslandLayoutHeight = interactionIslandLayoutHeight
            self.expandedIslandLayoutHeight = expandedIslandLayoutHeight
            self.showsCompletionToast = showsCompletionToast
            self.collapsedIslandLayoutHeight = collapsedIslandLayoutHeight
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: .aiLandReapplyWindowFrame,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reapplyFrame()
                    }
                }
            }
        }
        
        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        private func reapplyFrame() {
            guard let appearance,
                  let window = IslandWindowChromeController.shared.registeredWindowForFrameSync() else { return }
            // 必须与 `TaskActivityManager` 同步：跳转前会 `dismissCompletionToast()`，若仍用 bind 里上一帧的
            // `showsCompletionToast`，`applyFrame` 会多留 Peek 窗高一帧，与已收起的岛内容错位。
            let toastChromeNow = TaskActivityManager.shared.completionToast != nil && !islandExpanded
            IslandWindowFrameObserver.applyFrame(
                window: window,
                appearance: appearance,
                interactionActive: interactionActive,
                islandExpanded: islandExpanded,
                interactionIslandLayoutHeight: interactionIslandLayoutHeight,
                expandedIslandLayoutHeight: expandedIslandLayoutHeight,
                showsCompletionToast: toastChromeNow,
                collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
            )
        }
    }
    
    private static let baseNudgeLeft: CGFloat = 10
    /// 为 `.shadow` 与底边留白，避免裁切
    private static let interactionWindowHeightExtra: CGFloat = 22
    /// 完成 Peek 窗高：实测岛体高度 + 少量余量，避免圆角/阴影被裁
    private static let completionPeekWindowShadowPad: CGFloat = 14
    /// 首帧 `onGeometryChange` 未到前：相对「收起高度」的临时加量，下一帧会按实测收紧
    private static let completionPeekWindowReserveBootstrap: CGFloat = 52
    
    /// 无边框 / 层级等只需对每个 `NSWindow` 设一次；若每次 `updateNSView` 都全量配置会拖慢悬停展开
    private static var islandChromeConfiguredWindows: Set<ObjectIdentifier> = []
    
    /// 展开任务/计划时：SwiftUI 岛体高度与 `NSWindow` 内容区之间的余量（底边与圆角）
    private static let expandedIslandWindowHeightExtra: CGFloat = 28
    
    private static func configureWindow(
        _ window: NSWindow?,
        appearance: IslandAppearanceSettings,
        interactionActive: Bool,
        islandExpanded: Bool,
        interactionIslandLayoutHeight: CGFloat,
        expandedIslandLayoutHeight: CGFloat,
        showsCompletionToast: Bool,
        collapsedIslandLayoutHeight: CGFloat
    ) {
        guard let window else { return }
        IslandWindowChromeController.shared.registerIslandWindow(window)
        
        let oid = ObjectIdentifier(window)
        if islandChromeConfiguredWindows.insert(oid).inserted {
            if type(of: window) == NSWindow.self {
                object_setClass(window, KeyableIslandWindow.self)
            }
            NSApp.setActivationPolicy(.accessory)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask = [.borderless, .fullSizeContentView]
            window.level = .mainMenu + 1
            window.hasShadow = false
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        // 每次同步：老版本曾写死 minHeight=48，会导致低收起高度永不生效，须覆盖为与滑块一致的下限
        window.contentMinSize = NSSize(width: 200, height: 18)
        
        applyFrame(
            window: window,
            appearance: appearance,
            interactionActive: interactionActive,
            islandExpanded: islandExpanded,
            interactionIslandLayoutHeight: interactionIslandLayoutHeight,
            expandedIslandLayoutHeight: expandedIslandLayoutHeight,
            showsCompletionToast: showsCompletionToast,
            collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
        )
    }
    
    private static func resolvedWindowHeight(
        screen: NSScreen,
        appearance: IslandAppearanceSettings,
        interactionActive: Bool,
        islandExpanded: Bool,
        interactionIslandLayoutHeight: CGFloat,
        expandedIslandLayoutHeight: CGFloat,
        showsCompletionToast: Bool,
        collapsedIslandLayoutHeight: CGFloat
    ) -> CGFloat {
        let vfCap = screen.visibleFrame.height * 0.95
        if interactionActive {
            if interactionIslandLayoutHeight > 12 {
                let h = interactionIslandLayoutHeight + interactionWindowHeightExtra
                return min(max(96, h), vfCap)
            }
            return min(max(120, 320), vfCap)
        }
        if islandExpanded {
            if expandedIslandLayoutHeight > 20 {
                let h = expandedIslandLayoutHeight + expandedIslandWindowHeightExtra
                return min(max(96, h), vfCap)
            }
            // 首帧几何未到：略大于收起高度即可，避免固定 260pt 与实测差太多造成大块留白
            let baseCompact = appearance.islandCompactWindowHeight
            return min(max(96, baseCompact + 120), vfCap)
        }
        let baseCompact = appearance.islandCompactWindowHeight
        var h = baseCompact
        if showsCompletionToast {
            if collapsedIslandLayoutHeight > 18 {
                h = max(baseCompact, collapsedIslandLayoutHeight + completionPeekWindowShadowPad)
            } else {
                h = max(baseCompact, baseCompact + completionPeekWindowReserveBootstrap)
            }
        }
        let compactFloor: CGFloat = 18
        return min(max(compactFloor, h), vfCap)
    }
    
    private static func applyFrame(
        window: NSWindow,
        appearance: IslandAppearanceSettings,
        interactionActive: Bool,
        islandExpanded: Bool,
        interactionIslandLayoutHeight: CGFloat,
        expandedIslandLayoutHeight: CGFloat,
        showsCompletionToast: Bool,
        collapsedIslandLayoutHeight: CGFloat
    ) {
        // 层级切换、外接屏等瞬间 `window.screen` 可能为 nil，下一拍再对齐一次比落在错误屏上更稳。
        guard let screen = window.screen ?? NSScreen.main else { return }
        let sf = screen.frame
        let windowWidth = appearance.effectiveIslandWindowWidth
        let windowHeight = resolvedWindowHeight(
            screen: screen,
            appearance: appearance,
            interactionActive: interactionActive,
            islandExpanded: islandExpanded,
            interactionIslandLayoutHeight: interactionIslandLayoutHeight,
            expandedIslandLayoutHeight: expandedIslandLayoutHeight,
            showsCompletionToast: showsCompletionToast,
            collapsedIslandLayoutHeight: collapsedIslandLayoutHeight
        )
        // 必须用整屏 frame 的 maxY 贴顶（勿用 visibleFrame，否则会整窗落在菜单栏下方）；
        // x 须加 minX，多显示器时 (0,0) 假设不成立。
        let x = sf.minX + (sf.width - windowWidth) / 2 - baseNudgeLeft + appearance.windowOffsetX
        let y = sf.maxY - windowHeight + appearance.windowOffsetY
        let rect = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        if !NSEqualRects(window.frame, rect) {
            window.setFrame(rect, display: true)
        }
    }
}

