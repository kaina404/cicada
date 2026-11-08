import Foundation

/// The route through an open-ended question (a system design): the steps of the answer, which of them
/// our side has covered, and what to say next. Lives in memory for one meeting; not part of the record.
struct AnswerPlan: Equatable {
    enum Status: Equatable { case done, current, todo }
    struct Step: Equatable {
        var text: String
        var status: Status
        /// The current step's key point not said yet.
        var missing = ""
    }
    var goal: String
    var steps: [Step] = []
    /// What to say now, then the step after.
    var next: [String] = []
    /// The "say now" lines this plan showed before, newest first: an update replaced them while the
    /// user may still have been reading one.
    var earlier: [String] = []
    var contextID: String
    var question: String
    var at: Double

    /// The update, keeping what this plan said to say before it.
    func following(_ old: AnswerPlan) -> AnswerPlan {
        var plan = self
        plan.earlier = old.earlier
        if let said = old.next.first, said != next.first, said != plan.earlier.first {
            plan.earlier.insert(said, at: 0)
        }
        plan.earlier = Array(plan.earlier.prefix(30))
        return plan
    }

    var finished: Bool { !steps.isEmpty && steps.allSatisfy { $0.status == .done } }

    /// Our side has read the "say now" line out: it joins the earlier ones and the line after it
    /// moves up at once, instead of the reader waiting seconds for the model's update.
    func saying(_ said: String) -> AnswerPlan? {
        guard let hint = next.first, Self.covers(said, hint: hint) else { return nil }
        var plan = self
        if plan.earlier.first != hint { plan.earlier.insert(hint, at: 0) }
        plan.earlier = Array(plan.earlier.prefix(30))
        plan.next.removeFirst()
        return plan
    }

    /// Half the hint's words of three letters or more were said: read aloud, recognition drops or
    /// mishears some words, and the reader rephrases a few.
    static func covers(_ said: String, hint: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
        }
        let wanted = words(hint)
        guard wanted.count >= 3 else { return false }
        return Double(wanted.intersection(words(said)).count) / Double(wanted.count) >= 0.5
    }

    /// The plan as the model writes it, sent back so an update keeps the steps and their wording.
    var text: String {
        (["Q: " + goal] + steps.map { step in
            let mark = switch step.status { case .done: "[x]"; case .current: "[>]"; case .todo: "[ ]" }
            return "- \(mark) \(step.text)" + (step.missing.isEmpty ? "" : " | " + step.missing)
        } + next.map { "> " + $0 }).joined(separator: "\n")
    }

    /// The steps numbered for an update, which answers with numbers instead of rewriting them.
    var numbered: String {
        steps.enumerated().map { i, step in
            let mark = switch step.status { case .done: "[x]"; case .current: "[>]"; case .todo: "[ ]" }
            return "\(i + 1) \(mark) \(step.text)"
        }.joined(separator: "\n")
    }

    /// An update: "- Done: 1, 2", "- Now: 3 | missing point" (or a new phrase, or "done"), then "> " hints.
    /// A small model rewriting the whole plan turns our sentences into steps; numbers keep the steps.
    /// Nil without a Now: line, so a broken update keeps the plan as it was.
    func applying(_ reply: String) -> AnswerPlan? {
        var plan = self
        var now: String?
        var hints: [String] = []
        for raw in reply.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            let body = line.replacingOccurrences(of: #"^[-*•]\s*"#, with: "", options: .regularExpression)
            if let r = body.range(of: #"^(?i:done)\s*[:：]\s*"#, options: .regularExpression) {
                for n in body[r.upperBound...].split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) })
                where (1...plan.steps.count).contains(n) {
                    plan.steps[n - 1].status = .done
                }
            } else if let r = body.range(of: #"^(?i:now)\s*[:：]\s*"#, options: .regularExpression) {
                now = String(body[r.upperBound...])
            } else if line.hasPrefix(">") {
                let hint = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !hint.isEmpty, hints.count < 2 { hints.append(hint) }
            }
        }
        guard let now else { return nil }
        let parts = now.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let target = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: ".。 "))
        for i in plan.steps.indices {
            plan.steps[i].missing = ""
            if plan.steps[i].status == .current { plan.steps[i].status = .todo }
        }
        if target.lowercased() == "done" || target == "none" {
            for i in plan.steps.indices { plan.steps[i].status = .done }
        } else {
            let index: Int
            let name = target.lowercased()
            if let n = Int(target.prefix { $0.isNumber }), (1...plan.steps.count).contains(n) {
                index = n - 1
            } else if let same = plan.steps.firstIndex(where: { $0.text.lowercased() == name }) {
                // Models name a step instead of numbering it: a second copy would never be covered.
                index = same
            } else if !target.isEmpty {
                // Their deep dive no step covers: it goes after what we have covered.
                index = (plan.steps.lastIndex { $0.status == .done } ?? -1) + 1
                plan.steps.insert(.init(text: target, status: .todo), at: index)
                if plan.steps.count > 8, let drop = plan.steps.lastIndex(where: { $0.status == .todo }), drop != index {
                    plan.steps.remove(at: drop)
                }
            } else { return nil }
            plan.steps[index].status = .current
            let missing = parts.dropFirst().joined(separator: " ")
            // Models fill the slot with the step's own name.
            plan.steps[index].missing = missing.lowercased() == plan.steps[index].text.lowercased() ? "" : missing
        }
        plan.next = hints
        return plan
    }

    /// What a design round's clarifying questions usually settle, in the order they come up, with the
    /// words that show it has come up. On a mock interview the 4B model judged a question about offline
    /// use as the offline step covered, and kept proposing "read/write ratios" after the scale was given.
    static let clarifyingQuestions: [(keys: [String], ask: String)] = [
        (["scale", "daily active", "how many users", "million", "规模", "日活"], "What scale should we design for, roughly how many daily active users?"),
        (["text", "image", "video", "media", "content type", "图片", "视频"], "Which content types do we need: text, images, video, or a mix?"),
        (["infinite", "paginat", "scroll", "load more", "分页", "滚动"], "Is it an infinite list that keeps loading as the user reaches the bottom?"),
        (["creat", "posting", "upload", "发布"], "Is creating content in scope, or only viewing and interacting with it?"),
        (["real time", "real-time", "realtime", "push", "实时", "推送"], "Do new items and comments need to show up in real time?"),
        (["offline", "connectivity", "离线"], "Should it work offline, both for reading and for actions like comments?"),
        (["global", "geograph", "region", "countr", "network condition", "全球", "地区"], "Are the users global, so we plan for slow and unreliable networks?"),
        (["latency", "fast", "performance", "battery", "延迟", "性能"], "What latency should the first screen load within?"),
    ]

    /// The plan while our side is still on its requirements step: the next question nobody has
    /// brought up yet, then the one after, without the model. Replayed on the mock interview, the 4B
    /// model ticked the requirements off at the first stated one ("we also want to support user
    /// interactions"); so the step ends only when our side says it is moving on, or everything has
    /// come up, and the model judges from there.
    func clarifying(talk: [String]) -> AnswerPlan? {
        guard let first = steps.first, first.status == .current,
              first.text.lowercased().range(of: #"requirement|scope|clarif|需求|范围"#, options: .regularExpression) != nil else { return nil }
        let ours = talk.last { $0.hasPrefix("Me: ") }.map { $0.dropFirst(4).lowercased() } ?? ""
        let movesOn = #"\b(?:covers?|covered|that'?s (?:it|all) for|move on|moving on|let'?s (?:start|begin|go) with|high[- ]level (?:design|architecture|diagram)|apis?|endpoints?|architecture|data model|schema|let me (?:draw|sketch))\b|需求就这些|就这些需求|架构|接口|数据模型"#
        guard ours.range(of: movesOn, options: .regularExpression) == nil else { return nil }
        let said = (talk + [question]).joined(separator: " ").lowercased()
        let open = Self.clarifyingQuestions.filter { !$0.keys.contains(where: said.contains) }.map(\.ask)
        guard !open.isEmpty else { return nil }
        var plan = self
        plan.steps[0].missing = ""
        plan.next = Array(open.prefix(2))
        return plan
    }

    /// Open-ended questions that take several steps to answer, or the other side setting such a task.
    /// Only the other side counts, and "the team reviewed the design" is a statement.
    static func starts(_ text: String, speaker: String) -> Bool {
        guard speaker == "them" else { return false }
        let lower = text.lowercased()
        // Interviewers set the problem as a statement: "So we need to design an app that has 2 screens."
        if ["来设计", "请设计", "请你设计", "题目是设计"].contains(where: lower.contains)
            || lower.range(of: #"\b(?:(?:need|want|like|going|have|ask) (?:you )?to|let'?s|let us|you'?ll|you will) (?:design|build|architect)\b"#,
                           options: .regularExpression) != nil { return true }
        guard CopilotRules.needsResponse(text, speaker: speaker) else { return false }
        if ["设计一个", "设计一下", "怎么设计", "如何设计", "架构", "方案", "怎么实现", "如何实现", "从零"].contains(where: lower.contains) { return true }
        return lower.range(of: #"\b(?:design|architect\w*|system design|how would you (?:build|implement|approach|structure|scale))\b"#,
                           options: .regularExpression) != nil
    }

    /// Nil unless the reply has a goal and at least two steps: a broken update keeps the old plan.
    static func parse(_ reply: String, contextID: String, question: String, at: Double) -> AnswerPlan? {
        var plan = AnswerPlan(goal: "", contextID: contextID, question: question, at: at)
        for raw in reply.components(separatedBy: "\n") {
            var line = raw.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            if let range = line.range(of: #"^(?:Q:|Q：)\s*"#, options: .regularExpression) {
                plan.goal = String(line[range.upperBound...])
                continue
            }
            if line.hasPrefix(">") {
                let hint = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !hint.isEmpty, plan.next.count < 2 { plan.next.append(hint) }
                continue
            }
            // Models number or star the steps despite the format.
            if let range = line.range(of: #"^(?:[-*•]\s*)?(?:\d+[.)、]\s*)?"#, options: .regularExpression) {
                line = String(line[range.upperBound...])
            }
            guard let mark = line.range(of: #"^\[([xX✓>\s]?)\]\s*"#, options: .regularExpression) else { continue }
            let symbol = line[mark].trimmingCharacters(in: .whitespaces).dropFirst().first
            let status: Status = symbol == ">" ? .current : symbol.map { "xX✓".contains($0) } == true ? .done : .todo
            let parts = line[mark.upperBound...].components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let text = parts.first, !text.isEmpty, plan.steps.count < 7 else { continue }
            plan.steps.append(.init(text: text, status: status, missing: parts.dropFirst().joined(separator: " ")))
        }
        guard !plan.goal.isEmpty || !question.isEmpty, plan.steps.count >= 2 else { return nil }
        if plan.goal.isEmpty { plan.goal = String(question.prefix(80)) }
        // Exactly one current step: the first marked, else the first not done.
        if let first = plan.steps.firstIndex(where: { $0.status == .current }) {
            for i in plan.steps.indices where i != first && plan.steps[i].status == .current { plan.steps[i].status = .todo }
        } else if let first = plan.steps.firstIndex(where: { $0.status != .done }) {
            plan.steps[first].status = .current
        }
        for i in plan.steps.indices where plan.steps[i].status != .current { plan.steps[i].missing = "" }
        return plan
    }
}
