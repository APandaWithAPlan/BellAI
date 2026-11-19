import SwiftUI

// the frame every screen but chat shares: a title, optional buttons beside it, and a column of content
struct Page<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 22, weight: .semibold))
                        if let subtitle {
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    trailing
                }
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: Theme.columnWidth + 56, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(title)
        .toolbarBackground(Theme.background, for: .windowToolbar)
    }
}

extension Page where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

extension View {
    // a quiet surface for a group of related rows
    func panel() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
}

// a problem, in words, with the way out beside it
struct ProblemLine: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red)
            Spacer()
            if let retry { Button("Try Again", action: retry) }
        }
    }
}

// what a screen shows when there is nothing in it yet
struct EmptyNote: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// a list of rows with a hairline between them
struct Rows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id { Divider().padding(.leading, 14) }
            }
        }
        .panel()
    }
}
