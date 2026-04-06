//
//  MarkdownRenderer.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import SwiftUI

// Markdown renderer view
struct MarkdownRenderer: View {
    let markdown: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                renderMarkdown(markdown)
            }
            .padding()
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    // Simple markdown renderer
    @ViewBuilder
    private func renderMarkdown(_ text: String) -> some View {
        let lines = text.components(separatedBy: "\n")
        
        ForEach(lines, id: \.self) {
            line in
            if line.starts(with: "# ") {
                Text(line.dropFirst(2))
                    .font(.largeTitle)
                    .fontWeight(.bold)
            } else if line.starts(with: "## ") {
                Text(line.dropFirst(3))
                    .font(.title)
                    .fontWeight(.semibold)
            } else if line.starts(with: "- ") {
                HStack {
                    Text("•")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.trailing, 8)
                    Text(line.dropFirst(2))
                }
            } else if line.isEmpty {
                Spacer()
                    .frame(height: 16)
            } else {
                Text(line)
            }
        }
    }
}

// Markdown preview view
struct MarkdownPreviewView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Markdown Preview")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.bottom, 8)
            
            MarkdownRenderer(markdown: content)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
