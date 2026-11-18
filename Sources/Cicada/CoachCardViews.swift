import SwiftUI
import MermaidRender

/// Walkthrough card chrome around the reading script (docs/walkthrough-coach-plan.md §7):
/// above it the problem, what was heard and a correction mark; below it the step to type or draw,
/// what comes next, an optional reason, and earlier cards kept apart from the current one.
struct CoachCardHeader: View {
    @ObservedObject var cards: CoachCards
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let problem = cards.memory.problem {
                HStack(spacing: 4) {
                    Text(verbatim: problem.goal).foregroundStyle(Palette.ink).lineLimit(1)
                    if let next = problem.pending.first {
                        Text("· 接下来：\(next)").foregroundStyle(Palette.secondary).lineLimit(1)
                    }
                }.font(.system(size: 12))
            }
            if let heard = cards.card?.heard, !heard.isEmpty {
                Text("听到：\(heard)").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            if let fix = cards.card?.fix, !fix.isEmpty {
                Text("先纠正一句").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.accent.opacity(0.7)))
            }
            if cards.busy, cards.card == nil {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("正在想第一步") }
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct CoachCardFooter: View {
    @ObservedObject var cards: CoachCards
    var fontSize: CGFloat = 20
    var onNext: () -> Void
    var onRetry: () -> Void
    /// Off only for the debug snapshot: ImageRenderer draws selectable text as blank.
    var selectable = true
    @State private var showsPast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let card = cards.card {
                if let edit = card.edit { CoachEditCard(edit: edit, writing: cards.phase == .write, seen: cards.written, fontSize: fontSize, selectable: selectable) }
                if !card.then.isEmpty {
                    Text("然后：\(card.then)").font(.system(size: max(13, fontSize * 0.65))).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !card.reason.isEmpty {
                    Text(verbatim: card.reason).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The debug snapshot leaves the controls out: ImageRenderer draws a native button as a 🚫 placeholder.
            if selectable { HStack(spacing: 10) {
                Button("下一步", action: onNext).disabled(cards.busy && cards.card == nil)
                    .help("按实际进展给出下一步（⌃⌥A）")
                if cards.busy, cards.card != nil {
                    ProgressView().controlSize(.small)
                    Text("正在更新").foregroundStyle(Palette.secondary)
                }
                if cards.failed {
                    Text("这一步没生成出来").foregroundStyle(Palette.accent)
                    Button("重试", action: onRetry)
                }
            }.font(.system(size: 12)) }
            if !cards.past.isEmpty {
                DisclosureGroup(isExpanded: $showsPast) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cards.past.reversed()) { past in
                            Text(verbatim: past.card.say).font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 4)
                } label: {
                    Text("之前的卡片（\(cards.past.count)）").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }
}

private struct CoachEditCard: View {
    var edit: CoachCard.Edit
    var writing: Bool
    var seen: Bool
    var fontSize: CGFloat
    var selectable = true

    private var title: String {
        switch edit.action {
        case "replace": return L("替换")
        case "delete": return L("删除")
        case "draw": return L("画")
        default: return L("新增")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: title).font(.system(size: 11, weight: .semibold)).foregroundStyle(writing ? Palette.accent : Palette.secondary)
                if !edit.at.isEmpty { Text("位置：\(edit.at)").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1) }
                Spacer(minLength: 0)
                if seen { Text("屏幕上已看到").font(.system(size: 11)).foregroundStyle(Palette.tertiary) }
                else if writing { Text("现在写").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent) }
            }
            if edit.isDiagram, edit.closed, !edit.code.isEmpty {
                // The picture to copy onto the board; MermaidView falls back to the source text if it can't parse.
                CoachDiagram(source: edit.diagramSource)
            } else if !edit.code.isEmpty {
                // Wrapped, not a horizontal scroller: the panel never takes focus, and snippets are short.
                let code = Text(verbatim: edit.code).font(.system(size: max(12, fontSize * 0.65), design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                if selectable { code.textSelection(.enabled) } else { code }
            }
        }
        .padding(10)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(writing ? Palette.accent.opacity(0.6) : Palette.line))
    }
}

/// A walkthrough diagram filling the card's width. MermaidView keeps a chart at its natural size, which
/// read as a few tiny boxes in the card (seen live); this draws larger text and lets the picture grow.
private struct CoachDiagram: View {
    var source: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let image = MermaidRenderer.image(source: source, theme: DiagramTheme(prefersDark: scheme == .dark),
                                             spacing: .init(textScale: 1.6)) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width * 1.5, maxHeight: 560)
                .frame(maxWidth: .infinity)
        } else {
            MermaidView(source)  // its own fallback: the source as text
        }
    }
}
