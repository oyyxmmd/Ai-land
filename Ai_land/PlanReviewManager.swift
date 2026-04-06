//
//  PlanReviewManager.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import Foundation
import Combine

// Plan model
struct Plan: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let author: String
    let createdAt: Date
    var status: PlanStatus
    var feedback: String?
}

// Plan status
enum PlanStatus: String, CaseIterable {
    case draft = "Draft"
    case review = "In Review"
    case approved = "Approved"
    case rejected = "Rejected"
    
    var color: String {
        switch self {
        case .draft: return "gray"
        case .review: return "blue"
        case .approved: return "green"
        case .rejected: return "red"
        }
    }
}

// Plan review manager class
final class PlanReviewManager: ObservableObject {
    static let shared = PlanReviewManager()
    
    @Published var plans: [Plan]
    
    private init() {
        // Initialize with sample plans
        plans = [
            Plan(
                title: "AI Assistant Integration Plan",
                content: "# AI Assistant Integration Plan\n\n## Overview\nThis plan outlines the integration of multiple AI assistants into the Ai-land ecosystem.\n\n## Goals\n- Seamless integration with Claude Code\n- Support for Codex and Gemini CLI\n- Terminal integration\n\n## Timeline\n- Phase 1: Initial setup (1 week)\n- Phase 2: Integration (2 weeks)\n- Phase 3: Testing (1 week)\n",
                author: "System",
                createdAt: Date().addingTimeInterval(-86400),
                status: .review,
                feedback: nil
            ),
            Plan(
                title: "Terminal Integration Plan",
                content: "# Terminal Integration Plan\n\n## Supported Terminals\n- iTerm2\n- Ghostty\n- Warp\n- Terminal.app\n- VS Code\n- Cursor\n\n## Features\n- Tab navigation\n- Split pane support\n- Command execution\n",
                author: "System",
                createdAt: Date().addingTimeInterval(-172800),
                status: .approved,
                feedback: "Looks good, proceed with implementation."
            )
        ]
    }
    
    // Create new plan
    func createPlan(title: String, content: String, author: String) -> Plan {
        let newPlan = Plan(
            title: title,
            content: content,
            author: author,
            createdAt: Date(),
            status: .draft,
            feedback: nil
        )
        
        plans.insert(newPlan, at: 0)
        return newPlan
    }
    
    // Update plan status
    func updatePlanStatus(_ planId: UUID, status: PlanStatus, feedback: String? = nil) {
        if let index = plans.firstIndex(where: { $0.id == planId }) {
            plans[index].status = status
            plans[index].feedback = feedback
        }
    }
    
    // Get plan by id
    func getPlan(_ planId: UUID) -> Plan? {
        return plans.first { $0.id == planId }
    }
    
    // Get plans by status
    func getPlansByStatus(_ status: PlanStatus) -> [Plan] {
        return plans.filter { $0.status == status }
    }
    
    // Get all plans
    func getAllPlans() -> [Plan] {
        return plans
    }
    
    // Delete plan
    func deletePlan(_ planId: UUID) {
        plans.removeAll { $0.id == planId }
    }
}
