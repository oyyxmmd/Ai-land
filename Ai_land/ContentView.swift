//
//  ContentView.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import SwiftUI
import AppKit

// Import managers
import Foundation

// Agent status row view
struct AgentStatusRow: View {
    let agent: Agent
    
    var body: some View {
        HStack(spacing: 12) {
            // Agent icon
            VStack(spacing: 4) {
                Image(systemName: agent.iconName)
                    .foregroundColor(getStatusColor(agent.status))
                    .font(.headline)
                if case .busy = agent.status {
                    ProgressView()
                        .scaleEffect(0.5)
                        .progressViewStyle(.circular)
                        .foregroundColor(getStatusColor(agent.status))
                }
            }
            .frame(width: 40)
            
            // Agent info
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 16) {
                    Text(agent.status.description)
                        .font(.caption)
                        .foregroundColor(getStatusColor(agent.status))
                    Text(agent.configurationStatus.description)
                        .font(.caption)
                        .foregroundColor(getConfigurationColor(agent.configurationStatus))
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private func getStatusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: return .green
        case .busy: return .blue
        case .error: return .red
        }
    }
    
    private func getConfigurationColor(_ status: ConfigurationStatus) -> Color {
        switch status {
        case .notDetected: return .gray
        case .detected: return .yellow
        case .configured: return .green
        case .error: return .red
        }
    }
}

// Agent status list view
struct AgentStatusListView: View {
    @State private var agents: [Agent] = AgentManager.shared.getAgentsWithStatus()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI Agents")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: refreshAgents) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            List(agents) {
                agent in
                AgentStatusRow(agent: agent)
            }
            .listStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
    
    private func refreshAgents() {
        AgentManager.shared.refreshConfigurationStatus()
        agents = AgentManager.shared.getAgentsWithStatus()
    }
}

struct IslandShoulderShape: Shape {
    var shoulderRadius: CGFloat = 18 // 衔接屏幕顶部的弧度
    var bottomRadius: CGFloat = 30   // 岛屿底部的圆角
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // 1. 起点：左侧中间
        path.move(to: CGPoint(x: 0, y: rect.height - bottomRadius))
        
        // 2. 绘制底部（使用连续曲率模拟）
        path.addLine(to: CGPoint(x: 0, y: rect.height - bottomRadius))
        path.addCurve(to: CGPoint(x: bottomRadius, y: rect.height),
                      control1: CGPoint(x: 0, y: rect.height - bottomRadius * 0.45),
                      control2: CGPoint(x: bottomRadius * 0.45, y: rect.height))
        
        path.addLine(to: CGPoint(x: rect.width - bottomRadius, y: rect.height))
        
        path.addCurve(to: CGPoint(x: rect.width, y: rect.height - bottomRadius),
                      control1: CGPoint(x: rect.width - bottomRadius * 0.45, y: rect.height),
                      control2: CGPoint(x: rect.width, y: rect.height - bottomRadius * 0.45))
        
        // 3. 向上延伸至肩部起点
        path.addLine(to: CGPoint(x: rect.width, y: shoulderRadius))
        
        // 4. 【核心优化】右上角反向过渡 (Inverse Corner)
        // 使用两个控制点让弧度更“软”，完美契合屏幕边缘
        path.addCurve(to: CGPoint(x: rect.width + shoulderRadius, y: 0),
                      control1: CGPoint(x: rect.width, y: shoulderRadius * 0.4),
                      control2: CGPoint(x: rect.width + shoulderRadius * 0.6, y: 0))
        
        // 5. 顶部横线（这一段其实是没入屏幕顶部的）
        path.addLine(to: CGPoint(x: -shoulderRadius, y: 0))
        
        // 6. 【核心优化】左上角反向过渡
        path.addCurve(to: CGPoint(x: 0, y: shoulderRadius),
                      control1: CGPoint(x: -shoulderRadius * 0.6, y: 0),
                      control2: CGPoint(x: 0, y: shoulderRadius * 0.4))
        
        path.closeSubpath()
        return path
    }
}
struct ContentView: View {
    @State private var isExpanded = false
    /// 点击完成提示后滚动到对应 CLI 任务行
    @State private var cliListScrollNonce = 0
    @State private var pendingCliScrollToId: String?
    @State private var highlightedCliTaskId: String?
    @State private var cliTaskRenameSheetItem: CliTaskRenameSheetItem?
    /// 列表项悬停时展开最近对话 Popover（`chat_r0`… 或 `chat_preview`）
    @State private var cliPreviewPopoverTaskId: String?
    @State private var cliPopoverDismissWorkItem: DispatchWorkItem?
    /// 「问道 / 工具权限」展开时由岛上布局回传，用于 NSWindow 高度随内容自适应（非固定 pt）
    @State private var interactionIslandLayoutHeight: CGFloat = 0
    /// 任务/计划展开面板实测高度，用于窗高随列表撑开（上限见设置「展开最大高度」）
    @State private var expandedIslandLayoutHeight: CGFloat = 0
    /// 点「跳转」后先把完成条动画收拢，再 dismiss / 激活终端（避免面板瞬间消失）
    @State private var completionPeekJumpCollapsing = false
    @State private var completionJumpAfterCollapseSession: UUID?
    /// 收起态岛体（药丸 + 完成 Peek）实测高度，驱动窗高随内容收紧
    @State private var collapsedCompactLayoutHeight: CGFloat = 28
    
    @ObservedObject private var interactionManager = InteractionManager.shared
    @ObservedObject private var taskActivity = TaskActivityManager.shared
    @ObservedObject private var islandAppearance = IslandAppearanceSettings.shared
    @ObservedObject private var codePrefs = AiLandPreferences.shared
    @EnvironmentObject private var appLanguage: AppLanguageSettings
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var showLanguageOnboarding = false
    
    /// 有未完成的「问道」请求时，无论鼠标是否在岛上都应保持展开，否则用户移开指针会立刻收起，选项按钮点不到。
    private var islandExpanded: Bool {
        interactionManager.current != nil || isExpanded
    }
    
    /// 收起态内嵌完成 Peek 时加高窗口，避免裁切。
    private var showsCliCompletionToastChrome: Bool {
        taskActivity.completionToast != nil && !islandExpanded
    }
    
    /// 收起态药丸行高：与设置「收起高度」一致（窗口同值），限制在可点按与绘制的合理区间
    private var compactPillRowHeight: CGFloat {
        max(18, min(52, islandAppearance.islandCompactWindowHeight))
    }
    
    /// 收起态岛体在 SwiftUI 内的上限（仅用于 `!islandExpanded` 分支）
    private var collapsedIslandLayoutMaxHeight: CGFloat {
        if showsCliCompletionToastChrome && !completionPeekJumpCollapsing { return 260 }
        return max(28, compactPillRowHeight + 12)
    }
    
    private var islandShape: IslandShoulderShape {
        IslandShoulderShape(
            shoulderRadius: islandExpanded ? 16 : 8,
            bottomRadius: islandExpanded ? 28 : 16
        )
    }
    
    /// 用户偏好「减弱生肖动效」与系统「减少动态效果」任一开启即视为减弱。
    private var islandReduceMotion: Bool {
        codePrefs.reduceMotionIsland || accessibilityReduceMotion
    }
    
    private var hasCliWaitingConfirm: Bool {
        taskActivity.tasks.contains { if case .waitingConfirm = $0.phase { return true }; return false }
    }
    
    /// 展开态岛体在 SwiftUI 内的最大高度：随内容增高，硬顶为当前屏可视高度（与 NSWindow 上限一致）
    private var maxExpandedIslandHeight: CGFloat {
        let vf = NSScreen.main?.visibleFrame.height ?? 900
        return min(vf * 0.94, 2400)
    }
    
    /// 任务较少时不使用 ScrollView，避免 macOS 上 ScrollView 吃满父级高度导致大块空白
    private var cliTaskListUsesCompactLayout: Bool {
        taskActivity.tasks.count < 15
    }
    
    /// 长列表时列表区可滚动高度上限（留出标题、「清除全部」与底边距）
    private var cliTaskScrollViewportMaxHeight: CGFloat {
        max(220, maxExpandedIslandHeight - 118)
    }
    
    /// 收起且无完成 Peek 时用 `maxHeight: .infinity` + `Spacer` 把药丸顶到窗口顶部；其余情况（含任务列表展开）纵向必须随内容收缩，否则父级无限高会把 `onGeometryChange` 撑成整窗，窗高与岛体下半截大块黑底都失真。
    private struct RootIslandVerticalSizing: ViewModifier {
        let interactionOnly: Bool
        let compactHugsContent: Bool
        let islandExpanded: Bool
        @ViewBuilder
        func body(content: Content) -> some View {
            if interactionOnly || compactHugsContent || islandExpanded {
                content
                    .frame(maxWidth: .infinity, alignment: .top)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
    
    /// 仅在「问道」展示时订阅几何；平时任务/悬停展开也会改窗高，若仍挂着 `onGeometryChange` 易与窗口 `setFrame` 形成反馈环并触发 SwiftUI 警告。
    private struct InteractionIslandHeightObserver: ViewModifier {
        let isActive: Bool
        @Binding var layoutHeight: CGFloat
        
        @ViewBuilder
        func body(content: Content) -> some View {
            if isActive {
                content
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { _, newHeight in
                        if abs(newHeight - layoutHeight) <= 0.5 { return }
                        let captured = newHeight
                        DispatchQueue.main.async {
                            guard InteractionManager.shared.current != nil else { return }
                            if abs(captured - layoutHeight) > 0.5 {
                                layoutHeight = captured
                            }
                        }
                    }
            } else {
                content
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Dynamic Island Pill
            HStack {
                if islandExpanded {
                    expandedView
                } else {
                    VStack(spacing: 0) {
                        compactView
                            .frame(height: compactPillRowHeight, alignment: .center)
                            .padding(.top, (taskActivity.completionToast != nil && !islandExpanded && !completionPeekJumpCollapsing) ? 4 : 0)
                        if let toast = taskActivity.completionToast, !completionPeekJumpCollapsing {
                            cliCompletionPeekStrip(toast: toast)
                                .padding(.top, 6)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .bottom))
                                ))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, islandExpanded ? 16 : 2)
            // 纵向始终按内容理想高度（药丸 ~32、展开列表随内容），再用 maxHeight 封顶；避免「纯收起」时 fixedSize=false 被 VStack+Spacer 拉成一大块黑底
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: islandExpanded ? maxExpandedIslandHeight : collapsedIslandLayoutMaxHeight, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { _, newHeight in
                if islandExpanded {
                    guard interactionManager.current == nil else { return }
                    if abs(expandedIslandLayoutHeight - newHeight) > 1 {
                        expandedIslandLayoutHeight = newHeight
                    }
                } else {
                    if abs(collapsedCompactLayoutHeight - newHeight) > 0.5 {
                        collapsedCompactLayoutHeight = newHeight
                    }
                }
            }
            .background {
                if showsCliCompletionToastChrome && !completionPeekJumpCollapsing {
                    // 完成 Peek 时整块纯黑，避免顶部渐变在下半截像「另一层」盖住上方
                    Color.black
                } else {
                    ZStack {
                        Color.black
                        if hasCliWaitingConfirm {
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.32),
                                    Color.orange.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.015),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            }
            .overlay(
                islandShape
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(islandShape)
            .modifier(InteractionIslandHeightObserver(
                isActive: interactionManager.current != nil,
                layoutHeight: $interactionIslandLayoutHeight
            ))
            .animation(islandReduceMotion ? .none : .spring(response: 0.24, dampingFraction: 0.86), value: islandExpanded)
            .animation(islandReduceMotion ? .none : .spring(response: 0.36, dampingFraction: 0.84), value: taskActivity.completionToast?.taskId)
            .animation(islandReduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.9), value: completionPeekJumpCollapsing)
            .onHover { hovering in
                if interactionManager.current != nil {
                    if !isExpanded { isExpanded = true }
                } else if isExpanded != hovering {
                    isExpanded = hovering
                }
            }
            .onAppear {
                ConfigurationManager.shared.installClaudeAskUserQuestionBridgeIfNeeded()
                ConfigurationManager.shared.installClaudeTaskLifecycleHookIfNeeded()
                AgentManager.shared.performStartupAutoConfigureIfNeeded { _ in }
            }
            .onChange(of: interactionManager.current) { oldVal, newVal in
                DispatchQueue.main.async {
                    if oldVal?.id != newVal?.id {
                        interactionIslandLayoutHeight = 0
                    }
                    guard newVal != nil else { return }
                    if !isExpanded {
                        isExpanded = true
                    }
                }
            }
            // 仅「收起 + 无完成 Peek」时 Root 会走 maxHeight:∞；用 Spacer 顶上去，避免药丸在窗内垂直居中（勿再包一层全屏 frame，易搞乱首帧与贴屏坐标感观）。
            if !islandExpanded, interactionManager.current == nil, !showsCliCompletionToastChrome {
                Spacer(minLength: 0)
            }
        }
        .environment(\.aiLandReduceMotion, islandReduceMotion)
        .modifier(RootIslandVerticalSizing(
            interactionOnly: interactionManager.current != nil,
            compactHugsContent: showsCliCompletionToastChrome,
            islandExpanded: islandExpanded
        ))
        // Keep the window outside the island fully transparent so the inverse-corner
        // transition can visually fuse with the system's top black area (menu bar / notch).
        .background(Color.clear)
        .onChange(of: islandExpanded) { _, expanded in
            if expanded {
                completionJumpAfterCollapseSession = nil
                completionPeekJumpCollapsing = false
                taskActivity.dismissCompletionToast()
                collapsedCompactLayoutHeight = compactPillRowHeight
            } else {
                expandedIslandLayoutHeight = 0
            }
        }
        .onChange(of: taskActivity.completionToast) { _, newToast in
            if newToast == nil {
                completionJumpAfterCollapseSession = nil
                completionPeekJumpCollapsing = false
                collapsedCompactLayoutHeight = compactPillRowHeight
                return
            }
            if islandExpanded {
                taskActivity.dismissCompletionToast()
            }
        }
        .background {
            Group {
                Button("") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
                if let onlyConfirm = taskActivity.singleWaitingConfirmTaskId,
                   islandExpanded,
                   interactionManager.current == nil {
                    Button("") { taskActivity.submitTaskUserConfirmation(taskId: onlyConfirm, approved: true) }
                        .keyboardShortcut("y", modifiers: [])
                    Button("") { taskActivity.submitTaskUserConfirmation(taskId: onlyConfirm, approved: false) }
                        .keyboardShortcut("n", modifiers: [])
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .sheet(item: $cliTaskRenameSheetItem) { item in
            CliTaskRenameSheet(initialTitle: item.initialTitle) { newTitle in
                taskActivity.renameCliTask(id: item.id, title: newTitle)
            }
        }
        .background(
            IslandWindowFrameObserver(
                appearance: islandAppearance,
                interactionActive: interactionManager.current != nil,
                islandExpanded: islandExpanded,
                interactionIslandLayoutHeight: interactionIslandLayoutHeight,
                expandedIslandLayoutHeight: expandedIslandLayoutHeight,
                showsCompletionToast: showsCliCompletionToastChrome,
                collapsedIslandLayoutHeight: islandExpanded ? 0 : collapsedCompactLayoutHeight
            )
        )
        .onAppear {
            if appLanguage.needsLanguageOnboarding {
                showLanguageOnboarding = true
            }
        }
        .sheet(isPresented: $showLanguageOnboarding) {
            AppLanguageOnboardingSheet(isPresented: $showLanguageOnboarding, settings: appLanguage)
        }
    }
    
    /// 收起态图标：问道/任务运行 → 进行中；待确认 → 警告橙环；刚完成 → 对勾；否则生肖 idle。
    private var islandCompactPixelPhase: PixelIslandCompactPhase {
        if interactionManager.current != nil { return .running }
        if hasCliWaitingConfirm { return .waitingConfirm }
        if !taskActivity.runningTasks.isEmpty { return .running }
        if let until = taskActivity.compactCompletedGlowDeadline, Date() < until { return .completed }
        return .waiting
    }
    
    private var islandCompactAccessibilityLabel: String {
        switch islandCompactPixelPhase {
        case .waiting: return L10n.fmt("compact_a11y_idle", IslandTheme.appDisplayName)
        case .running: return L10n.fmt("compact_a11y_running", IslandTheme.appDisplayName)
        case .waitingConfirm: return L10n.fmt("compact_a11y_confirm", IslandTheme.appDisplayName)
        case .completed: return L10n.fmt("compact_a11y_completed", IslandTheme.appDisplayName)
        }
    }
    
    /// CLI 完成：收起态下在灵动岛内侧向下多露一条（非独立浮窗）。
    @ViewBuilder
    private func cliCompletionPeekStrip(toast: CLITaskCompletionToast) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(toast.success ? "toast_task_done" : "toast_task_ended")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(toast.success ? IslandTheme.teal : Color.orange.opacity(0.9))
                Text(toast.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)
                if !toast.dialogSnippet.isEmpty {
                    Text(toast.dialogSnippet)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 6) {
                Button {
                    openCliTaskFromCompletionToast(toast.taskId)
                } label: {
                    Text("jump_button")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(IslandTheme.teal)
                }
                .buttonStyle(.plain)
                .disabled(completionPeekJumpCollapsing)
                .accessibilityLabel(L10n.fmt("cli_a11y_jump", toast.title))
                Button {
                    completionJumpAfterCollapseSession = nil
                    taskActivity.dismissCompletionToast()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white.opacity(0.45), Color.white.opacity(0.12))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("dismiss_toast_help")
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: islandAppearance.islandCompactContentWidth)
        .background(Color.clear)
    }
    
    /// 点击 CLI 任务行：与侧栏终端列表同一套 `activateInstance`；精确跳转覆盖 iTerm2（含 tmux -CC）、Ghostty 1.3+、cmux、Terminal.app、Warp 与 IDE 集成终端（捆绑 VSIX）；Alacritty/Kitty/Hyper 等为尽力按窗口标题匹配。不调用编辑器 CLI、不经访达。
    private func jumpToWindowForCliTask(_ task: AgentCLITask) {
        let path = task.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hints = task.windowHints
        let title = task.title
        if interactionManager.current == nil {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                isExpanded = false
            }
        }
        IslandWindowChromeController.shared.temporarilyLowerForTargetAppActivation()
        _ = TerminalManager.shared.activateBestWindow(
            forWorkspacePath: path,
            hints: hints,
            titleHint: title
        )
        IslandWindowChromeController.shared.scheduleFrameResyncAfterExternalActivation()
    }
    
    private func cliTaskJumpHelp(_ task: AgentCLITask) -> String {
        var parts: [String] = [L10n.str("cli_help_click")]
        parts.append(L10n.str("cli_help_jump_detail"))
        if task.windowHints.hasUsableSignal {
            parts.append(L10n.str("cli_help_signal"))
        }
        parts.append(L10n.str("cli_help_finder_note"))
        if let p = task.workspacePath, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(p)
        }
        return parts.joined(separator: " ")
    }
    
    private func cliTaskPercentEncodeQueryValue(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
    
    /// 供右键复制：与当前阶段一致的 `ai-land://task?…` 示例链接。
    private func cliTaskSyntheticOpenURL(_ task: AgentCLITask) -> String {
        let state: String
        let okFragment: String
        switch task.phase {
        case .running:
            state = "running"
            okFragment = ""
        case .waitingConfirm:
            state = "waiting_confirm"
            okFragment = ""
        case .completed(let success):
            state = "completed"
            okFragment = success ? "&ok=1" : "&ok=0"
        }
        var q = "assistant=\(cliTaskPercentEncodeQueryValue(task.assistantExecutable))&state=\(state)&task_id=\(cliTaskPercentEncodeQueryValue(task.id))&title=\(cliTaskPercentEncodeQueryValue(task.title))"
        q += okFragment
        if let cwd = task.workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            q += "&cwd=\(cliTaskPercentEncodeQueryValue(cwd))"
        }
        let anchor = task.identityPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !anchor.isEmpty, anchor != "task:\(task.id)" {
            q += "&abs_path=\(cliTaskPercentEncodeQueryValue(anchor))"
        }
        if let pn = task.projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !pn.isEmpty {
            q += "&project_name=\(cliTaskPercentEncodeQueryValue(pn))"
        }
        if let b = task.branchName?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            q += "&branch=\(cliTaskPercentEncodeQueryValue(b))"
        }
        if let p = task.progressPercent {
            q += "&progress=\(p)"
        }
        if task.isGenerating {
            q += "&generating=1"
        }
        return "ai-land://task?\(q)"
    }
    
    private func openCliTaskFromCompletionToast(_ taskId: String) {
        completionJumpAfterCollapseSession = nil
        let session = UUID()
        completionJumpAfterCollapseSession = session
        let delay: TimeInterval = 0.48
        let taskForJump = taskActivity.tasks.first(where: { $0.id == taskId })
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            completionPeekJumpCollapsing = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard completionJumpAfterCollapseSession == session else {
                // 被关条/展开取消（session 置 nil）时收回状态；被新一次跳转替换时不要动（新会话会再设 true）
                if completionJumpAfterCollapseSession == nil {
                    completionPeekJumpCollapsing = false
                }
                return
            }
            completionJumpAfterCollapseSession = nil
            taskActivity.dismissCompletionToast()
            if let task = taskForJump {
                jumpToWindowForCliTask(task)
                return
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            pendingCliScrollToId = taskId
            highlightedCliTaskId = taskId
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if interactionManager.current == nil {
                    isExpanded = true
                }
            }
            cliListScrollNonce += 1
            let captured = taskId
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                if highlightedCliTaskId == captured {
                    highlightedCliTaskId = nil
                }
            }
        }
    }
    
    // Compact mode view：仅生肖；总宽仍由 `islandCompactContentWidth` 约束，与原先一致。
    var compactView: some View {
        HStack(alignment: .center, spacing: 8) {
            PixelIslandCompactGlyph(phase: islandCompactPixelPhase, zodiac: islandAppearance.zodiac)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.trailing, 10)
        .frame(width: islandAppearance.islandCompactContentWidth)
        .accessibilityLabel(islandCompactAccessibilityLabel)
    }
    
    // Expanded mode view
    var expandedView: some View {
        VStack(spacing: 0) {
            if let request = interactionManager.current {
                // 问道模式：顶部仅保留刷新 + 退出（与主界面同一排、紧贴），下面才是选项卡片
                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        islandHeaderRefreshAndQuit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    IslandInteractionPaletteView(request: request, interactionManager: interactionManager)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            } else {
                // Header
                HStack {
                    Text(IslandTheme.appDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    islandHeaderRefreshAndQuit()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                cliTasksView
            }
        }
        .frame(width: islandAppearance.islandExpandedContentWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    /// CLI / 钩子上报的任务进度（运行中、已完成）
    var cliTasksView: some View {
        VStack(spacing: 8) {
            if !taskActivity.tasks.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        highlightedCliTaskId = nil
                        cliPreviewPopoverTaskId = nil
                        taskActivity.clearAllCliTasks()
                    } label: {
                        Text("cli_clear_all")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            
            if taskActivity.tasks.isEmpty {
                ScrollView {
                    cliTaskEmptyStateContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if cliTaskListUsesCompactLayout {
                VStack(spacing: 6) {
                    cliTaskListRows
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            cliTaskListRows
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .frame(maxHeight: cliTaskScrollViewportMaxHeight)
                    .onChange(of: cliListScrollNonce) { _, _ in
                        guard let id = pendingCliScrollToId else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                            pendingCliScrollToId = nil
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var cliTaskEmptyStateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("cli_empty_title")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            Text("cli_empty_body")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
            Text("open -g \"ai-land://task?assistant=claude&state=running&task_id=demo&title=Demo&abs_path=/path/to/repo&project_name=MyApp&chat_r0=…&chat_r1=…\"")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .textSelection(.enabled)
            Text("cli_empty_footer")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.32))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 24)
    }
    
    @ViewBuilder
    private var cliTaskListRows: some View {
        ForEach(taskActivity.tasks) { task in
            cliTaskRow(task, isHighlighted: highlightedCliTaskId == task.id)
                .id(task.id)
                .help(cliTaskJumpHelp(task))
                .contextMenu {
                    Button("menu_rename") {
                        cliTaskRenameSheetItem = CliTaskRenameSheetItem(id: task.id, initialTitle: task.title)
                    }
                    if let path = task.workspacePath, !path.isEmpty {
                        Button("menu_copy_workspace") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                    }
                    Button("menu_copy_task_url") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cliTaskSyntheticOpenURL(task), forType: .string)
                    }
                    Divider()
                    Button("menu_remove", role: .destructive) {
                        removeCliTaskRow(task)
                    }
                }
        }
    }
    
    private func scheduleCliPopoverDismiss() {
        cliPopoverDismissWorkItem?.cancel()
        let work = DispatchWorkItem { cliPreviewPopoverTaskId = nil }
        cliPopoverDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
    }
    
    @ViewBuilder
    private func cliChatPreviewPopoverContent(task: AgentCLITask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("cli_preview_title")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
            ForEach(Array(task.chatPreviewTurns.enumerated()), id: \.offset) { pair in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.fmt("cli_turn_prefix", pair.offset + 1))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(pair.element)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: 320)
    }
    
    @ViewBuilder
    private func cliTaskRow(_ task: AgentCLITask, isHighlighted: Bool = false) -> some View {
        let hashColor = CLIWorkspaceIdentity.swiftUIColor(forAnchor: task.identityPath)
        let ident = CLIWorkspaceIdentity.identiconCharacter(
            projectName: task.projectName,
            workspacePath: task.workspacePath,
            titleFallback: task.title
        )
        let stripeActive: Bool = {
            switch task.phase {
            case .running, .waitingConfirm: return true
            default: return false
            }
        }()
        HStack(alignment: .center, spacing: 0) {
            CLIBreathingStripe(hashColor: hashColor, active: stripeActive, reduceMotion: islandReduceMotion)
            
            HStack(alignment: .center, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    CLITaskAvatarWithProgressRing(
                        task: task,
                        hashColor: hashColor,
                        ident: ident,
                        reduceMotion: islandReduceMotion
                    )
                    
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            HStack(spacing: 0) {
                                Text(CLITaskRowFormatting.headlineProject(from: task))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(" · ")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.42))
                                Text(CLITaskRowFormatting.branchLabel(from: task))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.88))
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            Spacer(minLength: 6)
                            switch task.phase {
                            case .completed, .running:
                                EmptyView()
                            default:
                                cliTaskStatusPill(task)
                                    .fixedSize()
                            }
                        }
                        
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("💬")
                                .font(.system(size: 11))
                            Text(CLITaskRowFormatting.truncatedPreview(CLITaskRowFormatting.previewSource(from: task)))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if task.isGenerating {
                                CLIGeneratingEllipsis(reduceMotion: islandReduceMotion)
                            }
                        }
                        
                        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                            let rel = CLITaskRowFormatting.relativeShort(since: task.startedAt, now: timeline.date)
                            let tty = CLITaskRowFormatting.ttySnippet(from: task).map { " · \($0)" } ?? ""
                            Text("\(task.assistantDisplayName) · \(rel)\(tty)")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.34))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
                .onTapGesture { jumpToWindowForCliTask(task) }
                
                cliTaskRemoveButton(task)
                    .padding(.trailing, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(IslandTheme.strokeSubtle, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    (task.phase == .waitingConfirm ? Color.orange : IslandTheme.teal).opacity(0.85),
                    lineWidth: (isHighlighted || task.phase == .waitingConfirm) ? 2 : 0
                )
        )
        .onHover { inside in
            if inside {
                cliPopoverDismissWorkItem?.cancel()
                if !task.chatPreviewTurns.isEmpty {
                    cliPreviewPopoverTaskId = task.id
                }
            } else {
                scheduleCliPopoverDismiss()
            }
        }
        .popover(
            isPresented: Binding(
                get: { cliPreviewPopoverTaskId == task.id && !task.chatPreviewTurns.isEmpty },
                set: { newVal in
                    if !newVal, cliPreviewPopoverTaskId == task.id { cliPreviewPopoverTaskId = nil }
                }
            ),
            arrowEdge: .leading
        ) {
            cliChatPreviewPopoverContent(task: task)
        }
        .animation(islandReduceMotion ? .none : .easeInOut(duration: 0.25), value: isHighlighted)
    }
    
    private func removeCliTaskRow(_ task: AgentCLITask) {
        taskActivity.removeCliTask(id: task.id)
        if highlightedCliTaskId == task.id { highlightedCliTaskId = nil }
        if cliPreviewPopoverTaskId == task.id { cliPreviewPopoverTaskId = nil }
    }
    
    @ViewBuilder
    private func cliTaskRemoveButton(_ task: AgentCLITask) -> some View {
        Button {
            removeCliTaskRow(task)
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.red.opacity(0.92))
        }
        .buttonStyle(.plain)
        .help("remove_from_list_help")
        .accessibilityLabel("remove_from_list_a11y")
    }
    
    /// 列表项右侧状态胶囊（主视觉）
    @ViewBuilder
    private func cliTaskStatusPill(_ task: AgentCLITask) -> some View {
        let (fg, fill, stroke) = cliTaskStatusPillColors(task)
        Text(task.statusLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
    
    private func cliTaskStatusPillColors(_ task: AgentCLITask) -> (Color, Color, Color) {
        switch task.phase {
        case .running:
            return (
                IslandTheme.teal,
                IslandTheme.teal.opacity(0.2),
                IslandTheme.teal.opacity(0.45)
            )
        case .waitingConfirm:
            return (
                Color.orange.opacity(0.98),
                Color.orange.opacity(0.22),
                Color.orange.opacity(0.5)
            )
        case .completed(let ok):
            if ok {
                return (
                    Color.green.opacity(0.95),
                    Color.green.opacity(0.18),
                    Color.green.opacity(0.4)
                )
            }
            return (
                Color.orange.opacity(0.95),
                Color.orange.opacity(0.18),
                Color.orange.opacity(0.4)
            )
        }
    }
    
    /// 刷新与退出并排、间距紧凑（与原先窗口角上孤立关闭钮相比，更贴近工具栏习惯）。
    private func islandHeaderRefreshAndQuit() -> some View {
        HStack(spacing: 4) {
            islandToolbarIconButton(systemName: "arrow.clockwise", action: refreshAll)
                .help("help_refresh")
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("help_settings")
            islandToolbarIconButton(systemName: "xmark", action: { NSApplication.shared.terminate(nil) })
                .help(L10n.fmt("help_quit_format", IslandTheme.appDisplayName))
        }
    }
    
    /// 工具栏图标按钮：纯黑底 + 细描边 + 蓝色图标
    private func islandToolbarIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func refreshAll() {
        // 任务来自共享管理器；代理与权限请在「设置」中查看与刷新。
    }
}

// MARK: - CLI task rename (context menu)

private struct CliTaskRenameSheetItem: Identifiable {
    let id: String
    let initialTitle: String
}

private struct CliTaskRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    let onSave: (String) -> Void
    
    init(initialTitle: String, onSave: @escaping (String) -> Void) {
        _title = State(initialValue: initialTitle)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("rename_task_title")
                .font(.system(size: 15, weight: .semibold))
            TextField("field_title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("save") {
                    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    onSave(t)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 300)
    }
}

// Simple waveform animation helper
struct WaveformView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<6) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 3, height: CGFloat.random(in: 5...15))
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.1), value: phase)
            }
        }
        .onAppear {
            phase = 1
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppLanguageSettings.shared)
            .appPreferredLocale(AppLanguageSettings.shared)
            .padding()
            .background(Color.gray.opacity(0.1))
    }
}
