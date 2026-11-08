import SwiftUI

/// A bounded, in-memory feed; the surrounding NotesPanel owns focus and screen-sharing behavior.
struct CopilotFeed: View {
    @ObservedObject var copilot: Copilot
    @ObservedObject var asker: AskEngine
    @ObservedObject var settings: AppSettings
    var expanded = false
    /// Above the transcript in a narrow window: leave the transcript most of the height.
    var compactHeight: CGFloat = 250

    var body: some View {
        if expanded || !copilot.cards.isEmpty || copilot.plan != nil || asker.state != .idle {
            VStack(alignment: .leading, spacing: 6) {
                Text("助手").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 24)
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if let plan = copilot.plan {
                            PlanCard(plan: plan, gloss: asker.gloss, showGloss: settings.askGloss,
                                     updating: copilot.active?.kind == .plan) { copilot.dropPlan() }
                                .padding(.bottom, 12)
                        }
                        if copilot.active == nil, asker.state != .idle, asker.state != .done {
                            AskCard(asker: asker, showGloss: settings.askGloss, emphasized: false)
                        }
                        ForEach(copilot.groups) { group in
                            Section {
                                if !copilot.collapsedGroups.contains(group.id) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(group.cards) { card in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(label(card.kind)).font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(card.emphasized ? Palette.accent : Palette.tertiary)
                                                AnswerLines(reply: card.reply, gloss: asker.gloss, showGloss: settings.askGloss,
                                                            emphasized: card.emphasized, spoken: card.kind == .response || card.kind == .manual)
                                            }
                                        }
                                        if copilot.active?.contextID == group.id, copilot.active?.kind != .plan {
                                            AskCard(asker: asker, showGloss: settings.askGloss, emphasized: copilot.emphasized,
                                                    title: label(copilot.active?.kind), embedded: true,
                                                    spoken: copilot.active?.kind == .response || copilot.active?.kind == .manual)
                                        }
                                        // Planning needs the assistant running: its updates come from the transcript.
                                        if settings.continuousAssistant, copilot.plan?.contextID != group.id,
                                           group.cards.contains(where: { $0.kind == .response || $0.kind == .manual }) {
                                            Button {
                                                copilot.startPlan(question: group.question, contextID: group.id, at: group.at,
                                                                  now: copilot.clock?() ?? group.at)
                                            } label: {
                                                Label("按此规划", systemImage: "list.number").font(.system(size: 11, weight: .semibold))
                                            }.buttonStyle(.plain).foregroundStyle(Palette.accentInk)
                                        }
                                    }
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(Palette.surface))
                                    .padding(.bottom, 12)
                                }
                            } header: {
                                Button { copilot.toggleGroup(group.id) } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(group.question)
                                                .font(.system(size: 13, weight: .semibold))
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(String(format: "%02d:%02d", Int(max(0, group.at)) / 60, Int(max(0, group.at)) % 60))
                                                .font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: copilot.collapsedGroups.contains(group.id) ? "chevron.down" : "chevron.up")
                                            .font(.system(size: 10, weight: .semibold))
                                    }.foregroundStyle(Palette.body).padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(UnevenRoundedRectangle(topLeadingRadius: 12,
                                            bottomLeadingRadius: copilot.collapsedGroups.contains(group.id) ? 12 : 0,
                                            bottomTrailingRadius: copilot.collapsedGroups.contains(group.id) ? 12 : 0,
                                            topTrailingRadius: 12).fill(Palette.surface))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .accessibilityLabel(Text(group.question + " · " + (copilot.collapsedGroups.contains(group.id) ? L("展开") : L("收起"))))
                            }
                        }
                    }.padding(.horizontal, 24)
                }
                .frame(maxHeight: expanded ? .infinity : compactHeight)
            }.padding(.bottom, 8)
        }
    }
    private func label(_ kind: CopilotRules.Kind?) -> String {
        kind == .plan ? L("答题路线") : L("参考回答")
    }
}

/// The one thing the assistant is for: the sentence to say now, then what follows it. The steps
/// behind it stay in the model's update; listing them was more to read than to say.
struct PlanCard: View {
    let plan: AnswerPlan
    @ObservedObject var gloss: AskGloss
    var showGloss = true
    var updating = false
    var onClose: () -> Void
    @State private var showEarlier = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(plan.goal).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary).lineLimit(1)
                if updating { Spinner(size: 10) }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Palette.tertiary).accessibilityLabel(Text("结束规划"))
            }
            if plan.next.isEmpty {
                Text("正在规划").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            }
            ForEach(Array(plan.next.enumerated()), id: \.offset) { i, hint in
                VStack(alignment: .leading, spacing: 2) {
                    Text(i == 0 ? L("现在说") : L("接着说")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(i == 0 ? Palette.accent : Palette.tertiary)
                    Text(hint).font(.system(size: i == 0 ? 14 : 13, weight: i == 0 ? .semibold : .regular))
                        .foregroundStyle(i == 0 ? Palette.ink : Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if showGloss, let zh = gloss.translations[hint] {
                        Text(zh).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !plan.earlier.isEmpty {
                DisclosureGroup(isExpanded: $showEarlier) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(plan.earlier.enumerated()), id: \.offset) { _, hint in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint).font(.system(size: 12)).foregroundStyle(Palette.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                if showGloss, let zh = gloss.translations[hint] {
                                    Text(zh).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }.padding(.top, 4)
                } label: {
                    Text("之前的提示 \(plan.earlier.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.tertiary)
                }
            }
        }
        .textSelection(.enabled)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .task(id: plan.next) { if showGloss { gloss.enqueue(plan.next + plan.earlier) } }
    }
}

struct AskCard: View {
    @ObservedObject var asker: AskEngine
    var showGloss = true
    var emphasized = false
    var title = L("刚才的问题")
    var embedded = false
    var spoken = false
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble").font(.system(size: 11))
                Text(status).font(.system(size: 11)).lineLimit(1)
                if asker.isBusy { Spinner(size: 10) }
                Spacer(minLength: 0)
                Button { if let onClose { onClose() } else { asker.dismiss() } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text("关闭"))
            }.foregroundStyle(emphasized ? Palette.accent : Palette.tertiary)
            if case .failed(let why) = asker.state {
                Text(why).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            AnswerLines(reply: .init(understood: asker.understood, points: asker.points, suggestions: asker.suggestions),
                        gloss: asker.gloss, showGloss: showGloss, emphasized: emphasized, spoken: spoken)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(embedded ? 0 : 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.fill))
        .padding(.horizontal, embedded ? 0 : 24)
    }
    private var status: String {
        switch asker.state {
        case .loading: L("正在载入本机模型")
        case .answering: L("正在回答")
        default: title
        }
    }
}

private struct AnswerLines: View {
    let reply: AskPrompt.Reply
    @ObservedObject var gloss: AskGloss
    let showGloss: Bool
    let emphasized: Bool
    var spoken = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !spoken, !reply.understood.isEmpty {
                bilingual(reply.understood, weight: .semibold)
            }
            ForEach(Array(reply.points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !spoken { Text("•").foregroundStyle(Palette.tertiary) }
                    bilingual(point, uncertain: AskPrompt.isUncertain(point))
                }
            }
            ForEach(Array(reply.suggestions.enumerated()), id: \.offset) { _, suggestion in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("→").foregroundStyle(emphasized ? Palette.accent : Palette.tertiary)
                    bilingual(suggestion)
                }
            }
        }.textSelection(.enabled).font(.system(size: 13))
    }
    private func bilingual(_ text: String, weight: Font.Weight = .regular, uncertain: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 13, weight: weight)).foregroundStyle(uncertain ? Palette.tertiary : Palette.body)
                .fixedSize(horizontal: false, vertical: true)
            if showGloss, let zh = gloss.translations[text] {
                Text(zh).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
