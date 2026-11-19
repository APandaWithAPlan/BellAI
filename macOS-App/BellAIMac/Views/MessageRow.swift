import AppKit
import SwiftUI

struct MessageRow: View {
    let message: Message
    let isWriting: Bool

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 120)
                Text(message.text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 18))
            }
        case .assistant:
            reply
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var reply: some View {
        if message.failed {
            Label(message.text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        } else if message.text.isEmpty && isWriting {
            ProgressView().controlSize(.small)
        } else {
            MarkdownText(text: message.text)
        }
    }
}

// the part of Markdown a chat uses: fenced code, headings, bullets, and bold, italic, code and links within a line
private struct MarkdownText: View {
    private enum Block {
        case prose(String)
        case code(language: String, body: String)
    }

    let text: String

    private var blocks: [Block] {
        // text between ``` fences is code; its first line is the language
        text.components(separatedBy: "```").enumerated().compactMap { index, part in
            if index.isMultiple(of: 2) {
                return part.allSatisfy(\.isWhitespace) ? nil : .prose(part)
            }
            guard let newline = part.firstIndex(of: "\n") else { return .code(language: "", body: "") }
            return .code(language: part[..<newline].trimmingCharacters(in: .whitespaces),
                         body: part[part.index(after: newline)...].trimmingCharacters(in: .newlines))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let prose): Prose(text: prose)
                case .code(let language, let body): CodeBlock(language: language, code: body)
                }
            }
        }
        .font(.system(size: 15))
        .lineSpacing(5)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Prose: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                row(String(line))
            }
        }
    }

    @ViewBuilder private func row(_ line: String) -> some View {
        let trimmed = line.drop { $0 == " " }
        if trimmed.isEmpty {
            Color.clear.frame(height: 2)
        } else if let heading = trimmed.firstMatch(of: /^#{1,6}\s+(.*)/) {
            Text(inline(String(heading.1)))
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            Text(inline(String(line.prefix(line.count - trimmed.count)) + "•  " + trimmed.dropFirst(2)))
        } else {
            Text(inline(line))
        }
    }

    private func inline(_ markdown: String) -> AttributedString {
        var text = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        for run in text.runs where run.link != nil {
            text[run.range].foregroundColor = Theme.accent
        }
        return text
    }
}

private struct CodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.accent : .secondary)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.codeHeader)

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .padding(12)
            }
        }
        .background(Theme.code)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
