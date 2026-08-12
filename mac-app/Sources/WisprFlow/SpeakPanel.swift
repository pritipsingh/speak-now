import AppKit
import SwiftUI

/// Actions the panel can trigger, wired up by the AppDelegate.
struct HistoryActions {
    let copy: (String) -> Void
    let clear: () -> Void
    let quit: () -> Void
    let startDictation: () -> Void
}

private let indigo = Color(red: 0.384, green: 0.341, blue: 0.902)
private let panelBG = Color(red: 0.098, green: 0.098, blue: 0.110)
private let successGreen = Color(red: 0.157, green: 0.722, blue: 0.373)

/// The "Speak" dropdown panel shown from the menu bar — branded header, search,
/// styled history rows with click-to-copy, and a footer.
struct HistoryPanelView: View {
    @ObservedObject var store: HistoryStore
    let actions: HistoryActions

    @State private var query = ""
    @State private var copied: String?

    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            divider
            list
            divider
            footer
        }
        .frame(width: 324)
        .background(panelBG)
    }

    private var divider: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(indigo).frame(width: 32, height: 32)
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Speak").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text("Hold Right Option to dictate")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button(action: actions.startDictation) {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold))
                    Text("Dictate").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(indigo).foregroundColor(.white).cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
            TextField("Search history", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private var list: some View {
        Group {
            if filtered.isEmpty {
                Text(store.items.isEmpty ? "No dictations yet" : "No matches")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.self) { item in
                            HistoryRow(item: item, copied: copied == item.text) {
                                actions.copy(item.text)
                                copied = item.text
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if copied == item.text { copied = nil }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: actions.clear) {
                HStack(spacing: 5) {
                    Image(systemName: "trash").font(.system(size: 11))
                    Text("Clear").font(.system(size: 12))
                }
            }
            .buttonStyle(.plain).foregroundColor(.white.opacity(0.55))
            .disabled(store.items.isEmpty)

            Spacer()

            Button(action: actions.quit) {
                Text("Quit Speak").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// A single history row: transcript preview + relative time, hover highlight, and a
/// copy affordance that flips to a green check on tap.
private struct HistoryRow: View {
    let item: HistoryItem
    let copied: Bool
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 13)).foregroundColor(.white)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(Self.relative(item.date))
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                }
                Spacer(minLength: 6)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        copied ? successGreen : .white.opacity(hover ? 0.5 : 0))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(hover ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
