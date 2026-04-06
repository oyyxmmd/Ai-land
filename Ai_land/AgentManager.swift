//
//  AgentManager.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import Foundation

// Agent status
enum AgentStatus {
    case idle
    case busy
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return L10n.str("agent_idle")
        case .busy: return L10n.str("agent_busy")
        case .error(let message): return L10n.fmt("agent_error_format", message)
        }
    }
}

// Agent model
struct Agent: Identifiable {
    var id: String { type.rawValue }
    let type: AIAssistantType
    var status: AgentStatus
    var lastActivity: Date?
    var configurationStatus: ConfigurationStatus
    
    var displayName: String {
        return type.rawValue
    }
    
    /// 须为系统 SF Symbols 中存在的名称；`code`、`robot` 等并非有效符号名，会导致控制台报错与列表重绘卡顿。
    var iconName: String {
        switch type {
        case .claudeCode: return "brain"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .geminiCLI: return "star"
        case .cursor: return "cursorarrow"
        case .openCode: return "terminal"
        case .droid: return "cpu"
        }
    }
}

// Agent manager class
class AgentManager {
    static let shared = AgentManager()
    
    /// 启动时自动安装钩子的结果摘要，供「设置 › AI 代理」展示
    private(set) var lastStartupAutoConfigureSummary: String?
    
    @Published var agents: [Agent]
    
    struct StartupAutoConfigureResult {
        var detectedCount = 0
        var configuredNowCount = 0
        var alreadyConfiguredCount = 0
        var notDetectedCount = 0
        var errorMessages: [String] = []
        
        var summaryText: String {
            if !errorMessages.isEmpty {
                return L10n.fmt("auto_cfg_summary_errors", configuredNowCount, alreadyConfiguredCount, errorMessages.count)
            }
            if detectedCount == 0 {
                return L10n.str("auto_cfg_no_agents")
            }
            return L10n.fmt("auto_cfg_summary_ok", configuredNowCount, alreadyConfiguredCount)
        }
    }
    
    private init() {
        // Initialize agents with default status
        agents = AIAssistantType.allCases.map { type in
            Agent(
                type: type,
                status: .idle,
                lastActivity: nil,
                configurationStatus: ConfigurationManager.shared.configurationStatus(for: type)
            )
        }
    }
    
    /// 进程内仅跑一次：为「已检测到 CLI 且尚未安装 hook」的代理自动配置；已有 hook 不覆盖。
    private var didRunStartupAutoConfigure = false
    
    func performStartupAutoConfigureIfNeeded(completion: ((StartupAutoConfigureResult) -> Void)? = nil) {
        guard !didRunStartupAutoConfigure else {
            completion?(StartupAutoConfigureResult())
            return
        }
        didRunStartupAutoConfigure = true
        
        DispatchQueue.global(qos: .utility).async {
            var result = StartupAutoConfigureResult()
            
            for type in AIAssistantType.allCases {
                let status = ConfigurationManager.shared.configurationStatus(for: type)
                switch status {
                case .detected:
                    result.detectedCount += 1
                    let configured = ConfigurationManager.shared.configureAssistant(type)
                    switch configured {
                    case .configured:
                        result.configuredNowCount += 1
                    case .error(let message):
                        result.errorMessages.append("\(type.rawValue): \(message)")
                    case .notDetected, .detected:
                        break
                    }
                case .configured:
                    result.detectedCount += 1
                    result.alreadyConfiguredCount += 1
                case .notDetected:
                    result.notDetectedCount += 1
                case .error(let message):
                    result.errorMessages.append("\(type.rawValue): \(message)")
                }
            }
            DispatchQueue.main.async {
                self.refreshConfigurationStatus()
                self.lastStartupAutoConfigureSummary = result.summaryText
                completion?(result)
            }
        }
    }
    
    /// 处理来自 hook 的 URL 回调：`ai-land://hook?assistant=claude&args=...`（兼容 `code-island`）
    func handleHookURL(_ url: URL) {
        guard AiLandURLRouting.isAppURLScheme(url.scheme) else { return }
        guard url.host?.lowercased() == "hook" else { return }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        let assistant = items.first(where: { $0.name == "assistant" })?.value
            .flatMap { AiLandURLRouting.clampField($0, maxChars: AiLandPayloadLimits.assistant) }
        let rawArgs = items.first(where: { $0.name == "args" })?.value
            .flatMap { AiLandURLRouting.clampField($0, maxChars: AiLandPayloadLimits.hookArgs) }
        
        guard let assistant else { return }
        guard let type = AIAssistantType.resolve(from: assistant) else { return }
        
        // 立即标记为 busy，短暂保持（hook 通常在“开始执行”时触发）
        updateStatus(type, status: .busy)
        Task { @MainActor in
            TaskActivityManager.shared.recordLegacyHook(assistant: type)
        }
        if let rawArgs, !rawArgs.isEmpty {
            _ = rawArgs
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            // 若期间没有其它状态更新，则回落 idle（与任务列表 legacy 自动收尾时长一致）
            if let agent = self.getAgent(type), case .busy = agent.status {
                self.updateStatus(type, status: .idle)
            }
        }
    }
    
    // Get agent by type
    func getAgent(_ type: AIAssistantType) -> Agent? {
        return agents.first { $0.type == type }
    }
    
    // Update agent status
    func updateStatus(_ type: AIAssistantType, status: AgentStatus) {
        if let index = agents.firstIndex(where: { $0.type == type }) {
            agents[index].status = status
            agents[index].lastActivity = Date()
        }
    }
    
    // Refresh configuration status for all agents
    func refreshConfigurationStatus() {
        let statuses = ConfigurationManager.shared.getStatusForAll()
        
        for (type, status) in statuses {
            if let index = agents.firstIndex(where: { $0.type == type }) {
                agents[index].configurationStatus = status
            }
        }
    }
    
    // Run command with agent
    func runCommand(_ type: AIAssistantType, command: String, completion: @escaping (String?, Error?) -> Void) {
        updateStatus(type, status: .busy)
        
        // Execute the actual command using the agent's executable
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = [type.executableName, command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        do {
            try task.run()
            
            // Read output asynchronously
            DispatchQueue.global(qos: .userInitiated).async {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let output = String(data: outputData, encoding: .utf8)
                let error = String(data: errorData, encoding: .utf8)
                
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        self.updateStatus(type, status: .idle)
                        completion(output, nil)
                    } else {
                        let errorMessage = error ?? "Command failed"
                        self.updateStatus(type, status: .error(errorMessage))
                        completion(nil, NSError(domain: "AgentError", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage]))
                    }
                }
            }
        } catch {
            updateStatus(type, status: .error(error.localizedDescription))
            completion(nil, error)
        }
    }
    
    // Configure all agents
    func configureAllAgents() -> [AIAssistantType: ConfigurationStatus] {
        let results = ConfigurationManager.shared.autoConfigureAll()
        refreshConfigurationStatus()
        return results
    }
    
    // Get all configured agents
    func getConfiguredAgents() -> [Agent] {
        return agents.filter { 
            if case .configured = $0.configurationStatus {
                return true
            }
            return false
        }
    }
    
    // Get all agents with status
    func getAgentsWithStatus() -> [Agent] {
        return agents
    }
}
