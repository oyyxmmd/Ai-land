//
//  PermissionManager.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import Foundation
import AppKit
import SwiftUI

// Permission types
enum PermissionType: String, CaseIterable {
    case accessibility
    case automation
    case fileSystem
    case network
    
    var description: String {
        switch self {
        case .accessibility: return L10n.str("perm_accessibility")
        case .automation: return L10n.str("perm_automation")
        case .fileSystem: return L10n.str("perm_filesystem")
        case .network: return L10n.str("perm_network")
        }
    }
}

// Permission status
enum PermissionStatus: CaseIterable, Hashable {
    case granted
    case denied
    case notRequested
    case unknown
    
    var localizedDescription: String {
        switch self {
        case .granted: return L10n.str("perm_status_granted")
        case .denied: return L10n.str("perm_status_denied")
        case .notRequested: return L10n.str("perm_status_not_requested")
        case .unknown: return L10n.str("perm_status_unknown")
        }
    }
    
    var color: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notRequested: return .yellow
        case .unknown: return .gray
        }
    }
}

// Permission manager class
class PermissionManager {
    static let shared = PermissionManager()
    
    private init() {}
    
    enum AutomationTarget: CaseIterable {
        case systemEvents
        case terminal
        
        var displayName: String {
            switch self {
            case .systemEvents: return "System Events"
            case .terminal: return "Terminal"
            }
        }
        
        var script: String {
            switch self {
            case .systemEvents:
                return """
                tell application "System Events"
                    get name of application processes
                end tell
                """
            case .terminal:
                return """
                tell application "Terminal"
                    get name of windows
                end tell
                """
            }
        }
    }
    
    // Check accessibility permission
    func checkAccessibilityPermission() -> PermissionStatus {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if isTrusted {
            return .granted
        } else {
            return .denied
        }
    }
    
    // Request accessibility permission
    func requestAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        return isTrusted
    }
    
    private struct AppleScriptResult {
        let terminationStatus: Int32
        let stdout: String
        let stderr: String
    }
    
    private func runAppleScript(_ script: String) -> AppleScriptResult? {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            
            return AppleScriptResult(
                terminationStatus: task.terminationStatus,
                stdout: out.trimmingCharacters(in: .whitespacesAndNewlines),
                stderr: err.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            return nil
        }
    }
    
    private func isAutomationDenied(_ result: AppleScriptResult) -> Bool {
        // -1743 is the common Apple Events "Not authorized" error code.
        // osascript typically prints something like:
        // "execution error: Not authorized to send Apple events to ... (-1743)"
        return result.stderr.contains("(-1743)") || result.stderr.contains("-1743") || result.stderr.localizedCaseInsensitiveContains("Not authorized")
    }
    
    // Check automation permission for a specific target (System Events / Terminal)
    func checkAutomationPermission(for target: AutomationTarget) -> PermissionStatus {
        guard let result = runAppleScript(target.script) else {
            return .unknown
        }
        
        if result.terminationStatus == 0 {
            return .granted
        }
        
        if isAutomationDenied(result) {
            return .denied
        }
        
        return .unknown
    }
    
    // Check aggregated automation permission (all targets must be granted)
    func checkAutomationPermission() -> PermissionStatus {
        let statuses = AutomationTarget.allCases.map { checkAutomationPermission(for: $0) }
        if statuses.allSatisfy({ $0 == .granted }) {
            return .granted
        }
        if statuses.contains(.denied) {
            return .denied
        }
        return .unknown
    }
    
    // Request automation permission (triggers prompts for all targets)
    func requestAutomationPermission() -> Bool {
        var allSucceeded = true
        for target in AutomationTarget.allCases {
            _ = runAppleScript(target.script)
            allSucceeded = allSucceeded && (checkAutomationPermission(for: target) == .granted)
        }
        return allSucceeded
    }
    
    // Check file system permission for a specific path
    func checkFileSystemPermission(for path: String) -> PermissionStatus {
        let fileManager = FileManager.default
        
        do {
            _ = try fileManager.attributesOfItem(atPath: path)
            return .granted
        } catch {
            return .denied
        }
    }
    
    // Check network permission
    func checkNetworkPermission() -> PermissionStatus {
        // Network permission is usually granted by default on macOS
        // This is a placeholder implementation
        return .granted
    }
    
    // Get status for all permissions
    func getAllPermissionStatuses() -> [PermissionType: PermissionStatus] {
        var statuses: [PermissionType: PermissionStatus] = [:]
        
        for permission in PermissionType.allCases {
            switch permission {
            case .accessibility:
                statuses[permission] = checkAccessibilityPermission()
            case .automation:
                statuses[permission] = checkAutomationPermission()
            case .fileSystem:
                statuses[permission] = checkFileSystemPermission(for: "/tmp")
            case .network:
                statuses[permission] = checkNetworkPermission()
            }
        }
        
        return statuses
    }
    
    // Request all necessary permissions
    func requestAllPermissions() -> Bool {
        var allGranted = true
        
        if checkAccessibilityPermission() != .granted {
            allGranted = allGranted && requestAccessibilityPermission()
        }
        
        if checkAutomationPermission() != .granted {
            allGranted = allGranted && requestAutomationPermission()
        }
        
        return allGranted
    }
}
