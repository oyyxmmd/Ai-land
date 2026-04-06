//
//  AiLandSettingsView.swift
//  Ai_land
//
//  独立设置窗口：系统设置风格（分组 Form + 侧栏），含灵动岛尺寸、外观、AI 代理与权限。
//

import SwiftUI
import AppKit

private enum AiLandSettingsPane: String, CaseIterable, Identifiable {
    case general
    case island
    case agents
    case permissions
    
    var id: String { rawValue }
    
    var titleKey: LocalizedStringKey {
        switch self {
        case .general: "pane_general"
        case .island: "pane_island"
        case .agents: "pane_agents"
        case .permissions: "pane_permissions"
        }
    }
}

/// macOS `Settings` 场景根视图
struct AiLandSettingsView: View {
    @State private var selectedPane: AiLandSettingsPane = .island
    
    var body: some View {
        NavigationSplitView {
            // 不用 `List(selection:)`：在部分 macOS 版本上 `Binding` + `.tag` 会导致整侧栏点击无效；改为显式 `Button` 更新状态。
            List {
                ForEach(AiLandSettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        HStack(spacing: 10) {
                            Label { Text(pane.titleKey) } icon: { Image(systemName: pane.iconName) }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedPane == pane ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch selectedPane {
                case .general:
                    SettingsGeneralPane()
                case .island:
                    SettingsIslandAndWindowPane()
                case .agents:
                    SettingsAgentsPane()
                case .permissions:
                    SettingsPermissionsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 520)
    }
}

private extension AiLandSettingsPane {
    var iconName: String {
        switch self {
        case .general: return "gearshape.2"
        case .island: return "rectangle.topthird.inset.filled"
        case .agents: return "cpu"
        case .permissions: return "lock.shield"
        }
    }
}

// MARK: - 通用（通知 / 声音 / 诊断）

@ViewBuilder
private func soundAssignButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
    }
    .buttonStyle(.bordered)
    .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 2)
    )
}

private struct AiLandSoundAssignRow: View {
    @ObservedObject private var prefs = AiLandPreferences.shared
    let row: AiLandSoundRow
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                if row.id.hasPrefix("res:") {
                    Text((row.id as NSString).lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 140, maxWidth: 220, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                soundAssignButton(title: L10n.str("sound_preview"), isOn: false) {
                    SoundManager.shared.playToken(row.id)
                }
                .help("help_sound_preview")
                soundAssignButton(title: L10n.str("sound_success"), isOn: prefs.taskCompletionSoundSuccessToken == row.id) {
                    prefs.taskCompletionSoundSuccessToken = row.id
                    SoundManager.shared.playToken(row.id)
                }
                .help("help_sound_success")
                soundAssignButton(title: L10n.str("sound_failure"), isOn: prefs.taskCompletionSoundFailureToken == row.id) {
                    prefs.taskCompletionSoundFailureToken = row.id
                    SoundManager.shared.playToken(row.id)
                }
                .help("help_sound_failure")
                soundAssignButton(title: L10n.str("sound_interact"), isOn: prefs.interactionSoundToken == row.id) {
                    prefs.interactionSoundToken = row.id
                    SoundManager.shared.playToken(row.id)
                }
                .help("help_sound_interact")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

private struct AiLandSoundLibrarySections: View {
    private var grouped: [String: [AiLandSoundRow]] {
        Dictionary(grouping: AiLandSoundCatalog.allRows(), by: \.section)
    }
    
    var body: some View {
        ForEach(AiLandSoundCatalog.sectionDisplayOrder, id: \.self) { section in
            if let rows = grouped[section], !rows.isEmpty {
                Section(section) {
                    ForEach(rows) { row in
                        AiLandSoundAssignRow(row: row)
                    }
                }
            }
        }
    }
}

private struct SettingsGeneralPane: View {
    @ObservedObject private var prefs = AiLandPreferences.shared
    @EnvironmentObject private var appLanguage: AppLanguageSettings
    
    var body: some View {
        Form {
            Section {
                Picker("settings_section_language", selection: $appLanguage.mode) {
                    ForEach(AppLanguageMode.allCases) { mode in
                        Text(mode.titleKey).tag(mode)
                    }
                }
                Text("settings_language_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("settings_task_feedback") {
                Toggle("settings_play_sound", isOn: $prefs.soundOnTaskCompletion)
                LabeledContent("settings_success_sound") {
                    Text(AiLandSoundCatalog.displayLabel(forToken: prefs.taskCompletionSoundSuccessToken))
                        .foregroundStyle(.secondary)
                }
                LabeledContent("settings_failure_sound") {
                    Text(AiLandSoundCatalog.displayLabel(forToken: prefs.taskCompletionSoundFailureToken))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button("settings_preview_success") {
                        SoundManager.shared.playToken(prefs.taskCompletionSoundSuccessToken)
                    }
                    Button("settings_preview_failure") {
                        SoundManager.shared.playToken(prefs.taskCompletionSoundFailureToken)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Toggle("settings_system_notify", isOn: $prefs.systemNotificationOnTaskCompletion)
                Text("settings_notify_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("settings_interaction") {
                Toggle("settings_sound_on_interaction", isOn: $prefs.soundOnInteraction)
                LabeledContent("settings_current_interaction_sound") {
                    Text(AiLandSoundCatalog.displayLabel(forToken: prefs.interactionSoundToken))
                        .foregroundStyle(.secondary)
                }
                Button("settings_preview_interaction") {
                    SoundManager.shared.playToken(prefs.interactionSoundToken)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Section {
                Text("settings_sound_library_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AiLandSoundLibrarySections()
            } header: {
                Text("settings_sound_library_header")
            }
            Section("settings_animation") {
                Toggle("settings_reduce_zodiac_motion", isOn: $prefs.reduceMotionIsland)
                Text("settings_reduce_zodiac_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("settings_diagnostics") {
                Button("settings_copy_diagnostics") {
                    let text = AiLandDiagnostics.buildReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Text("settings_diagnostics_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 灵动岛与窗口

private struct SettingsIslandAndWindowPane: View {
    @ObservedObject private var appearance = IslandAppearanceSettings.shared
    
    var body: some View {
        Form {
            Section {
                Text("settings_zodiac_header")
                    .font(.headline)
                Text("settings_zodiac_subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
                    ForEach(IslandZodiac.allCases) { z in
                        Button {
                            appearance.zodiac = z
                        } label: {
                            VStack(spacing: 6) {
                                PixelIslandCompactGlyph(phase: .waiting, zodiac: z)
                                    .frame(height: 40)
                                Text(z.han)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(appearance.zodiac == z ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(appearance.zodiac == z ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Section("settings_window_sizes") {
                settingsSliderRow(title: L10n.str("settings_total_width"), value: $appearance.islandWindowWidth, range: 400...1400, step: 4)
                Text("settings_total_width_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                settingsSliderRow(title: L10n.str("settings_compact_height"), value: $appearance.islandCompactWindowHeight, range: 18...200, step: 1)
                Text("settings_compact_height_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                settingsSliderRow(title: L10n.str("settings_compact_content_width"), value: $appearance.islandCompactContentWidth, range: 160...520, step: 2)
                settingsSliderRow(title: L10n.str("settings_expanded_content_width"), value: $appearance.islandExpandedContentWidth, range: 320...1200, step: 4)
                Button("settings_reset_layout") {
                    appearance.resetLayoutDimensionsToDefaults()
                }
            }
            
            Section("settings_screen_position") {
                settingsSliderRow(title: L10n.str("settings_offset_x"), value: $appearance.windowOffsetX, range: -240...240, step: 2, suffix: " pt")
                settingsSliderRow(title: L10n.str("settings_offset_y"), value: $appearance.windowOffsetY, range: -120...120, step: 2, suffix: " pt")
                Text("settings_offset_footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("settings_reset_offset") {
                    appearance.resetWindowOffset()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - AI 代理

private struct SettingsAgentsPane: View {
    @State private var agents: [Agent] = AgentManager.shared.getAgentsWithStatus()
    @State private var hookAlertTitle = ""
    @State private var hookAlertMessage = ""
    @State private var showHookAlert = false
    
    var body: some View {
        Form {
            if let summary = AgentManager.shared.lastStartupAutoConfigureSummary, !summary.isEmpty {
                Section("settings_startup_auto") {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Text("settings_configured")
                    Spacer()
                    Text("\(configuredCount) / \(agents.count)")
                        .foregroundStyle(.secondary)
                }
                Button("settings_refresh_status") { refreshAgents() }
            }
            Section("settings_agents_hooks") {
                ForEach(agents) { agent in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: agent.iconName)
                            .foregroundStyle(settingsStatusColor(agent.status))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(agent.displayName)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Text(agent.status.description)
                                    .font(.caption)
                                    .foregroundStyle(settingsStatusColor(agent.status))
                                Text(agent.configurationStatus.description)
                                    .font(.caption)
                                    .foregroundStyle(settingsConfigColor(agent.configurationStatus))
                            }
                        }
                        Spacer(minLength: 8)
                        Button {
                            runQuickHookConfigure(for: agent.type)
                        } label: {
                            Image(systemName: "link.badge.plus")
                                .font(.body.weight(.semibold))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .help(L10n.fmt("settings_install_hooks", IslandTheme.appDisplayName))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshAgents() }
        .alert(hookAlertTitle, isPresented: $showHookAlert) {
            Button("hook_alert_ok", role: .cancel) {}
        } message: {
            Text(hookAlertMessage)
        }
    }
    
    private var configuredCount: Int {
        agents.filter { if case .configured = $0.configurationStatus { return true }; return false }.count
    }
    
    private func refreshAgents() {
        AgentManager.shared.refreshConfigurationStatus()
        agents = AgentManager.shared.getAgentsWithStatus()
    }
    
    private func runQuickHookConfigure(for type: AIAssistantType) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ConfigurationManager.shared.quickConfigureHooks(for: type)
            DispatchQueue.main.async {
                hookAlertTitle = result.success ? L10n.str("hook_configure_title") : L10n.str("hook_configure_fail")
                hookAlertMessage = result.message
                showHookAlert = true
                refreshAgents()
            }
        }
    }
}

// MARK: - 权限

private struct SettingsPermissionsPane: View {
    @State private var permissionStatuses: [PermissionType: PermissionStatus] = PermissionManager.shared.getAllPermissionStatuses()
    
    var body: some View {
        Form {
            Section {
                Button("settings_refresh_perm") { refreshPermissions() }
            }
            Section("settings_permissions_list") {
                ForEach(PermissionType.allCases, id: \.self) { permission in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: settingsPermissionIcon(permission))
                            .foregroundStyle((permissionStatuses[permission] ?? .unknown).color)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(permission.description)
                                .font(.headline)
                            Text(permissionStatuses[permission]?.localizedDescription ?? L10n.str("perm_status_unknown"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if permissionStatuses[permission] != .granted {
                            Button("perm_request") {
                                requestPermission(permission)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Button("settings_request_all_perm") {
                    _ = PermissionManager.shared.requestAllPermissions()
                    refreshPermissions()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshPermissions() }
    }
    
    private func refreshPermissions() {
        permissionStatuses = PermissionManager.shared.getAllPermissionStatuses()
    }
    
    private func requestPermission(_ permission: PermissionType) {
        switch permission {
        case .accessibility:
            _ = PermissionManager.shared.requestAccessibilityPermission()
        case .automation:
            _ = PermissionManager.shared.requestAutomationPermission()
        case .fileSystem, .network:
            break
        }
        refreshPermissions()
    }
}

// MARK: - 颜色与图标（设置窗口用系统语义色）

private func settingsStatusColor(_ status: AgentStatus) -> Color {
    switch status {
    case .idle: return .green
    case .busy: return .blue
    case .error: return .red
    }
}

private func settingsConfigColor(_ status: ConfigurationStatus) -> Color {
    switch status {
    case .notDetected: return .secondary
    case .detected: return .orange
    case .configured: return .green
    case .error: return .red
    }
}

private func settingsPermissionIcon(_ permission: PermissionType) -> String {
    switch permission {
    case .accessibility: return "lock.open"
    case .automation: return "hammer"
    case .fileSystem: return "folder"
    case .network: return "network"
    }
}

@ViewBuilder
private func settingsSliderRow(
    title: String,
    value: Binding<CGFloat>,
    range: ClosedRange<CGFloat>,
    step: CGFloat,
    suffix: String = ""
) -> some View {
    LabeledContent(title) {
        HStack {
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue))\(suffix)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
        }
    }
}
