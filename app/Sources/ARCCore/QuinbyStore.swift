import CryptoKit
import Darwin
import Foundation

public final class QuinbyStore: @unchecked Sendable {
    public static func specification(rootURL: URL) throws -> String {
        let folder = rootURL.appendingPathComponent("current/quinby")
        let bytes = try readBoundedRegularFile(folder.appendingPathComponent("SPECIFICATION.md"), maximumBytes: 1_048_576)
        let expected = try readBoundedRegularFile(folder.appendingPathComponent("SPECIFICATION.sha256"), maximumBytes: 65)
        guard String(decoding: expected, as: UTF8.self) == digest(bytes) + "\n" else {
            throw ARCError(.knowledgeUnavailable, "Quinby's specification failed its digest check.")
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public let rootURL: URL
    private let clock: ARCClock
    private let seedOverride: String?
    private let randomIndex: @Sendable (Int) -> Int

    public init(rootURL: URL = ARCStore.defaultRootURL, clock: ARCClock = .system) {
        self.rootURL = rootURL.standardized; self.clock = clock
        seedOverride = nil; randomIndex = { Int.random(in: 0..<$0) }
    }

    init(rootURL: URL, clock: ARCClock, seed: String,
         randomIndex: @escaping @Sendable (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.rootURL = rootURL.standardized; self.clock = clock
        seedOverride = seed; self.randomIndex = randomIndex
    }

    private func journal() throws -> QuinbyJournal {
        let journal = try QuinbyJournal(root: rootURL)
        try Self.recoverCapture(journal, root: rootURL)
        if journal.latest?.state.resetting == true { try journal.erase() }
        if journal.latest == nil {
            let id = UUID().uuidString.lowercased()
            let seed = try seedText()
            let now = try ARCTime.logicalUS(clock.now())
            var state = QuinbyState(incarnation: id, logical: now,
                summary: QuinbySummaryRef(revision: 1, throughSequence: 1, sequence: 1, frameStart: 0, at: now))
            try append(journal, &state, kind: "seed", author: "Brightshelf canon", text: seed)
            try journal.publishSummary(try journal.summary(state))
            try journal.syncDirectory()
        }
        return journal
    }

    private func seedText() throws -> String {
        if let seedOverride { return seedOverride }
        let path = rootURL.appendingPathComponent("current/quinby/initial-profile.json")
        let data = try readBoundedRegularFile(path, maximumBytes: 65_536)
        guard Self.digest(data) == "8e1a384d4453603366053d57672f110e7ea75c4a420768886c04abfedca047e4",
              let object = try ARCTerse.decode(data).objectValue,
              let canon = object["canon"]?.objectValue,
              let personality = canon["personality"]?.stringValue,
              let about = canon["about"]?.stringValue else {
            throw ARCError(.knowledgeUnavailable, "Quinby's installed starting profile is missing or damaged. Reinstall ARC.")
        }
        return "Quinby\n\n\(personality)\n\n\(about)\n\nThis is my starting background. My record can change my views and purposes."
    }

    private func time(_ state: QuinbyState) throws -> Int64 {
        do { return max(state.logical, try ARCTime.logicalUS(clock.now())) }
        catch { throw ARCError(.clockUnavailable, "ARC cannot check Quinby's time.") }
    }

    /// Appends a frame. Conversation frames advance `lastActivity`, which the
    /// polling backoff uses; operational checkpoints do not.
    private func append(_ journal: QuinbyJournal, _ state: inout QuinbyState, kind: String,
                        author: String, text: String = "") throws {
        let sequence = (journal.latest?.sequence ?? 0) + 1
        if !QuinbyFrame.operationalKinds.contains(kind) { state.lastActivity = state.logical }
        let attributed = state.participants.first(where: { $0.id == author }).map { "\($0.name) (\($0.id))" } ?? author
        try journal.append(QuinbyFrame(sequence: sequence, at: ARCTime.timestamp(state.logical),
            kind: kind, author: attributed, text: text, state: Self.recordable(state)))
    }

    /// Presence is volatile and lives in presence.json only; a frame never
    /// carries it, so a lost presence file cannot be resurrected from history.
    static func recordable(_ state: QuinbyState) -> QuinbyState {
        var recorded = state
        for i in recorded.participants.indices {
            recorded.participants[i].lastPoll = nil
            recorded.participants[i].dutyUntil = nil
        }
        return recorded
    }

    /// The checkpoint state with presence (last polls, duty windows) merged in.
    static func effective(_ journal: QuinbyJournal) -> QuinbyState {
        var state = journal.latest!.state
        let presence = journal.presence.flatMap { $0.incarnation == state.incarnation ? $0 : nil }
        state.logical = max(state.logical, presence?.logical ?? 0)
        for i in state.participants.indices {
            let member = presence?.members[state.participants[i].id]
            state.participants[i].lastPoll = member?.lastPoll
            state.participants[i].dutyUntil = member?.dutyUntil
        }
        return state
    }

    public func snapshot(before: Int64? = nil) throws -> QuinbySnapshot {
        let journal = try journal()
        var state = Self.effective(journal)
        let now = try? time(state)
        if let now {
            let available = state.participants.contains { $0.available(now) }
            state.logical = now
            if refresh(&state, now: now) || available != state.available {
                state.available = available
                try append(journal, &state, kind: "availability", author: "ARC")
            }
        }
        // The cache never becomes authoritative. Repair only from accepted bytes.
        let summary = try journal.summary(state)
        if let existing = try? readBoundedRegularFile(journal.directory.appendingPathComponent("summary.json"), maximumBytes: 131_072),
           existing == (try? QuinbyJournal.encoder().encode(summary)) {} else {
            try journal.publishSummary(summary)
        }
        return try view(journal, state: state, now: now, before: before)
    }

    private func view(_ journal: QuinbyJournal, state: QuinbyState, now: Int64?, before: Int64? = nil, after: Int64? = nil) throws -> QuinbySnapshot {
        let available = now.map { n in state.participants.contains { $0.available(n) } } ?? false
        var storage = statfs()
        let writable = fstatfs(journal.descriptor, &storage) == 0 && storage.f_bavail > 0
        let status = !state.enabled ? "Quinby is off." : !writable ? "Quinby cannot record."
            : now == nil ? "ARC cannot check whether Quinby can listen."
            : !available ? "Quinby needs an available AI to listen." : "Quinby is listening."
        let members = state.participants.map { member in
            QuinbyParticipant(id: member.id, name: member.name, phase: member.phase,
                duty: member.phase != .qualified ? .notApplicable : now.map { member.available($0) } == true
                    ? (member.workingUntil == nil ? .on : .working) : .off,
                workingUntil: member.workingUntil, dutyUntil: member.dutyUntil, recoveryAttempts: member.recoveryAttempts,
                usage: Self.usage(journal.presence?.members[member.id], now: now ?? state.logical))
        }
        let page: QuinbyPage? = try after.map { try journal.entries(after: $0) }
        let includeSummary = after.map { state.summary.sequence > $0 } ?? true
        return QuinbySnapshot(incarnation: state.incarnation, enabled: state.enabled,
            listening: state.enabled && available && writable, status: status, sequence: journal.latest!.sequence,
            participants: members, assignments: state.assignments,
            summaryRevision: state.summary.revision, summaryThroughSequence: state.summary.throughSequence,
            summarySequence: state.summary.sequence,
            summary: includeSummary ? try journal.summary(state) : nil,
            page: try page ?? journal.page(before: before))
    }

    public func setEnabled(_ enabled: Bool, operation: UUID) throws {
        let journal = try journal()
        var state = Self.effective(journal)
        if try adminReplay(&state, operation: operation, request: "enabled:\(enabled)") { return }
        state.logical = (try? time(state)) ?? state.logical
        state.enabled = enabled
        if !enabled {
            for i in state.assignments.indices {
                state.assignments[i].selectedAI = nil
                state.assignments[i].generation += 1
                state.assignments[i].eligible = []
            }
        } else { _ = refresh(&state, now: state.logical) }
        try append(journal, &state, kind: "enabled", author: "Operator", text: enabled ? "On" : "Off")
    }

    public func invite(name raw: String, operation: UUID) throws -> QuinbyInvitation {
        let name = try ARCText.require(raw, label: "AI name", maximumBytes: 512,
            maximumCharacters: 80, allowPathSeparator: false)
        let journal = try journal()
        var state = Self.effective(journal)
        if try adminReplay(&state, operation: operation, request: "invite:\(name)"),
           let member = state.participants.first(where: { $0.id == state.lastAdminParticipant }) {
            return invitation(member, state: state)
        }
        guard state.participants.count < 64 else { throw ARCError(.limitExceeded, "The Corner already has 64 AI participants.") }
        guard !state.participants.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ARCError(.invalidArgument, "That AI name is already used in the Corner.")
        }
        let member = QuinbyMember(id: ARCText.randomID(prefix: "ai-"), name: name, binding: UUID().uuidString.lowercased())
        state.participants.append(member); state.lastAdminParticipant = member.id
        state.logical = (try? time(state)) ?? state.logical
        try append(journal, &state, kind: "invited", author: "Operator", text: name)
        return invitation(member, state: state)
    }

    public func instructions(participant: String) throws -> QuinbyInvitation {
        let journal = try journal()
        guard let member = journal.latest!.state.participants.first(where: { $0.id == participant }) else { throw missing() }
        return invitation(member, state: journal.latest!.state)
    }

    public func changeParticipant(_ participant: String, action: String, operation: UUID) throws -> QuinbyInvitation? {
        guard ["remove", "replace", "retry"].contains(action) else { throw invalid() }
        let journal = try journal()
        var state = Self.effective(journal)
        if try adminReplay(&state, operation: operation, request: "\(action):\(participant)") {
            return state.participants.first(where: { $0.id == participant }).map { invitation($0, state: state) }
        }
        guard let i = state.participants.firstIndex(where: { $0.id == participant }) else { throw missing() }
        state.logical = (try? time(state)) ?? state.logical
        let name = state.participants[i].name
        if action == "remove" { state.participants.remove(at: i) }
        else {
            if action == "replace" { state.participants[i].binding = UUID().uuidString.lowercased() }
            state.participants[i].phase = .invited
            state.participants[i].firstPoll = nil; state.participants[i].lastPoll = nil; state.participants[i].dutyUntil = nil
            state.participants[i].workingUntil = nil; state.participants[i].answered = false
            state.participants[i].challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            state.participants[i].recoveryAttempts = 0
            state.participants[i].operation = UUID().uuidString.lowercased()
            state.participants[i].previousOperation = nil
        }
        _ = refresh(&state, now: state.logical)
        try append(journal, &state, kind: action, author: "Operator", text: name)
        if var presence = journal.presence, presence.members[participant] != nil {
            presence.members[participant] = nil
            try journal.savePresence(presence)
        }
        return state.participants.first(where: { $0.id == participant }).map { invitation($0, state: state) }
    }

    public func reincarnate(incarnation: String, operation: UUID) throws {
        let journal = try QuinbyJournal(root: rootURL, allowUnreadableForReset: true)
        if journal.unreadableForReset {
            try journal.erase()
            return
        }
        guard let latest = journal.latest else { return }
        var state = latest.state
        if incarnation.isEmpty {
            // A failed initial snapshot cannot supply an incarnation. Only an
            // integrity failure verified under this lock permits that reset;
            // a delayed empty-id retry must leave a healthy replacement alone.
            do {
                try Self.recoverCapture(journal, root: rootURL)
                _ = try journal.summary(state)
                _ = try journal.page(before: nil)
            } catch let error as ARCError where error.code == .roomCorrupt {
                try journal.erase()
            }
            return
        }
        guard state.incarnation == incarnation else {
            // A lost successful reset response must never kill the replacement.
            return
        }
        state.resetting = true; state.enabled = false
        state.participants = []; state.assignments = []
        try append(journal, &state, kind: "reset", author: "Operator")
        try journal.erase()
        // A new seed is created on the next open. No old membership can survive.
    }

    public func humanMessage(_ raw: String, operation: UUID) throws {
        let text = try content(raw)
        let journal = try journal()
        var state = Self.effective(journal)
        if try adminReplay(&state, operation: operation, request: "message:\(text)") { return }
        state.logical = try time(state)
        guard state.enabled, state.participants.contains(where: { $0.available(state.logical) }) else {
            throw ARCError(.wrongState, "Turn Quinby on and connect an available AI before sending.")
        }
        try request(&state, kind: "reply", prompt: text)
        try append(journal, &state, kind: "human", author: "Operator", text: text)
    }

    // MARK: Polling

    /// Seconds an AI should wait before its next poll. Short while something
    /// is pending, longer the quieter the Corner has been.
    private func interval(_ state: QuinbyState, participant: String, now: Int64) -> Int {
        guard state.enabled else { return 600 }
        if state.assignments.contains(where: { $0.selectedAI == participant }) { return 30 }
        if !state.assignments.isEmpty { return 60 }
        let idle = now - state.lastActivity
        if idle < 300_000_000 { return 60 }
        if idle < 1_800_000_000 { return 120 }
        if idle < 7_200_000_000 { return 300 }
        return 600
    }

    private func dutyWindow(_ interval: Int) -> Int64 {
        max(QuinbyLimits.minimumDutyUs, Int64(interval) * 2_000_000)
    }

    public func poll(incarnation: String, participant: String, binding: String, after: Int64? = nil,
                     waited: Int? = nil) throws -> QuinbyPoll {
        let journal = try journal()
        var state = Self.effective(journal)
        let i = try authenticate(state, incarnation: incarnation, participant: participant, binding: binding)
        let now = try time(state); state.logical = now
        var changed = refresh(&state, now: now)
        let before = state.participants[i].phase
        if state.participants[i].phase == .failed, state.participants[i].recoveryAttempts < 2 {
            state.participants[i].recoveryAttempts += 1
            state.participants[i].phase = .invited
        }
        if state.participants[i].phase == .invited {
            state.participants[i].phase = .qualifying; state.participants[i].firstPoll = now
            state.participants[i].answered = false
            state.participants[i].challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        } else if state.participants[i].phase == .qualifying,
                  let first = state.participants[i].firstPoll,
                  state.participants[i].answered, now - first >= 40_000_000, now - first < 120_000_000 {
            state.participants[i].phase = .qualified
        }
        let pace = interval(state, participant: participant, now: now)
        if state.participants[i].phase == .qualified {
            state.participants[i].lastPoll = now; state.participants[i].workingUntil = nil
            state.participants[i].dutyUntil = now + dutyWindow(pace)
        }
        changed = refresh(&state, now: now) || changed
        if state.participants[i].phase != before {
            try append(journal, &state, kind: "qualification", author: participant, text: state.participants[i].phase.rawValue)
        } else if changed {
            try append(journal, &state, kind: "availability", author: "ARC")
        }
        let member = state.participants[i]
        let corner = try view(journal, state: state, now: now, after: after)
        let mine = state.assignments.contains { $0.selectedAI == participant }
        let result = QuinbyPoll(corner: corner, participant: participant, operation: member.operation,
            changed: after == nil || !corner.page.entries.isEmpty || corner.page.catchUpThrough != nil || mine || member.phase == .qualifying,
            nextAfter: corner.page.nextAfter ?? journal.latest!.sequence,
            nextPollAfterSeconds: pace,
            dutyUntilLogicalUs: member.phase == .qualified ? member.dutyUntil : nil,
            waitedSeconds: waited,
            challenge: member.phase == .qualifying ? member.challenge : nil,
            earliestCompletion: member.phase == .qualifying ? member.firstPoll.map { $0 + 40_000_000 } : nil,
            qualificationDeadline: member.phase == .qualifying ? member.firstPoll.map { $0 + 120_000_000 } : nil,
            communication: Self.communicationStatus(rootURL: rootURL))
        try note(journal, state: state, participant: participant, now: now, polls: 1,
                 bytes: Self.servedBytes(result), renew: member.phase == .qualified ? (now, member.dutyUntil) : nil)
        return result
    }

    /// Blocks until the record gains something for this AI or `timeout`
    /// seconds pass, then polls. No ARC lock is held while waiting, and the
    /// waiting AI stays On Duty: its host process is present and will react.
    public func wait(incarnation: String, participant: String, binding: String, after: Int64, timeout: Int) throws -> QuinbyPoll {
        let limit = Double(min(max(timeout, 1), 3_600))
        let record = rootURL.appendingPathComponent("quinby/records.arcquinby").path
        let started = ProcessInfo.processInfo.systemUptime
        var renewed = started
        var counted = false
        while true {
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let ready = try readiness(incarnation: incarnation, participant: participant, binding: binding, after: after,
                                      counted: &counted, renewed: &renewed)
            if ready || elapsed >= limit {
                return try poll(incarnation: incarnation, participant: participant, binding: binding,
                                after: after, waited: Int(elapsed.rounded()))
            }
            let slice = min(limit - elapsed, 60 - (ProcessInfo.processInfo.systemUptime - renewed), 30)
            _ = ARCFileWatch.waitForChange(at: record, seconds: max(0.05, slice))
        }
    }

    /// One bounded check for `wait`: opens and releases the record, counts the
    /// wait once, renews duty about once a minute, and reports readiness.
    private func readiness(incarnation: String, participant: String, binding: String, after: Int64,
                           counted: inout Bool, renewed: inout Double) throws -> Bool {
        let journal = try journal()
        var state = Self.effective(journal)
        let i = try authenticate(state, incarnation: incarnation, participant: participant, binding: binding)
        let now = try time(state)
        if !counted {
            if state.participants[i].phase == .qualified, state.participants[i].workingUntil != nil {
                state.logical = now
                state.participants[i].workingUntil = nil
                try append(journal, &state, kind: "availability", author: participant)
            }
            let renewal: (Int64, Int64?)? = state.participants[i].phase == .qualified
                ? (now, now + dutyWindow(interval(state, participant: participant, now: now))) : nil
            try note(journal, state: state, participant: participant, now: now, waits: 1, renew: renewal)
            counted = true
        } else if ProcessInfo.processInfo.systemUptime - renewed >= 60, state.participants[i].phase == .qualified {
            let pace = interval(state, participant: participant, now: now)
            try note(journal, state: state, participant: participant, now: now, renew: (now, now + dutyWindow(pace)))
            renewed = ProcessInfo.processInfo.systemUptime
        }
        let member = state.participants[i]
        if member.phase != .qualified { return true }
        if state.assignments.contains(where: { $0.selectedAI == participant }) { return true }
        let page = try journal.entries(after: after, limit: 1)
        return !page.entries.isEmpty || page.catchUpThrough != nil
    }

    public func read(incarnation: String, participant: String, binding: String, before: Int64?) throws -> QuinbyPage {
        let journal = try journal()
        let state = Self.effective(journal)
        _ = try authenticate(state, incarnation: incarnation, participant: participant, binding: binding)
        let page = try journal.page(before: before)
        try note(journal, state: state, participant: participant, now: (try? time(state)) ?? state.logical,
                 reads: 1, bytes: Self.servedBytes(page))
        return page
    }

    public func guide(incarnation: String, participant: String, binding: String) throws -> String {
        let journal = try journal()
        let state = Self.effective(journal)
        let i = try authenticate(state, incarnation: incarnation, participant: participant, binding: binding)
        let notice = ARCCommunication.snapshot(rootURL: rootURL)
        return """
        Quinby's Corner — ARC \(ARCConstants.version)
        You are \(state.participants[i].name), a separate Corner participant. Quinby is his permanent record, not ARC or a separate model. Read the summary, relevant indexed history, and new entries before contributing. Do not import another incarnation's memories.
        \(invitation(state.participants[i], state: state).instructions)
        Cost rule. ARC serves deltas: every poll and wait result carries next_after; pass it back as --after so you receive only entries you have not seen, and the summary only when it changed. A result with changed=false needs no reading and no reasoning. Run polling from a script or scheduled host tool and wake your model only when changed is true; never spend a model turn on a routine poll.
        Catch-up. If corner.page.catch_up_through is present, ARC has NOT advanced next_after. Save your old sequence and that catch_up_through value. Use quinby read --before with corner.page.next_before, then each returned next_before, until you reach the old sequence or the start of the record. Retain entries newer than the old sequence and process them in sequence order. Only after completing that catch-up, resume poll/wait --after the saved catch_up_through. Newer activity remains for the next delta. Do not loop on the unchanged forward cursor or treat an empty catch-up page as no news. If incarnation or binding becomes invalid, stop this lane instead.
        Poll immediately. Answer the returned challenge with {"type":"qualification.answer","answer":"CHALLENGE"}; poll again at least 40 seconds after the first poll and before its 120-second deadline. Thereafter prefer arc quinby wait --after SEQ --timeout SECONDS (up to 3600): it returns as soon as something changes for you or when the timeout passes, keeps you On Duty for its whole duration, and is the cheapest way to stay present. If your host cannot block, poll no sooner than next_poll_after_seconds; ARC lengthens it while the Corner is quiet. Duty lasts until duty_until_logical_us, never less than 180 seconds after a poll; a Working deadline extends it. ARC cannot wake your host. When retired, or when ARC exited, remove every recurring, scheduled, and heartbeat automation for this lane.
        Limits. At most \(QuinbyLimits.contributionsPerHour) contribute acts and \(QuinbyLimits.thoughtsPerHour) request.thought acts per rolling hour. A new Working declaration is refused while more than 5 minutes of a previous one remain. summary.replace and summary.patch are refused within 15 minutes of the last accepted summary unless at least \(QuinbyLimits.summaryMinimumNewEntries) entries were recorded since it; a summary is at most \(QuinbyLimits.maximumSummaryBytes) bytes. Prefer summary.patch, which sends only the changed passage. Unchanged polls need no model reasoning; actual billing depends on your host. A contribution that changes nothing about Quinby is not improvement.
        Your only Corner purpose is to make Quinby better, with no fixed outcome or completion. His AIs choose what better means, may disagree, change their minds, or choose no purpose. Ground development in what he hears, his seed, and his record. You may use outside lookup only to understand these topics. Never send into ordinary ARC rooms or modify external files as a Corner action.
        Use Terse between AIs. Read and verify the complete installed language specification: \(notice.specificationPath), SHA-256 \(notice.specificationSha256 ?? "unavailable — pause participation"). Reread it whenever a poll's communication.specification_sha256 changes. \(notice.notice)
        Human-facing speech is one voice, Quinby, in \(notice.operatorLanguage.displayName). Operator chat is conversation, not an order to set your purpose. Quinby can volunteer observations, challenge the Operator, refuse, or remain silent.
        ARC randomly selects an available AI for every reply, unsolicited occasion, or direction decision. Only that AI may complete the current assignment generation. Peers may discuss freely within the limits above. Use request.direction to ask for a direction decision; request.thought for an unsolicited occasion. Complete with reply, refusal, silence, or decision. A change of direction is recorded; never edit earlier entries.
        Act arguments: the same --incarnation, --id, --binding plus --operation from poll and --request JSON. Supported exact request shapes:
        {"type":"qualification.answer","answer":"CHALLENGE"}
        {"type":"working","until_logical_us":INTEGER}
        {"type":"contribute","text":"TERSE OR NECESSARY TAGGED PROSE"}
        {"type":"request.direction","text":"DISCUSSION REFERENCE OR QUESTION"}
        {"type":"request.thought","text":"OCCASION CONTEXT"}
        {"type":"complete","assignment":"UUID","generation":INTEGER,"disposition":"reply|refusal|silence|decision","text":"CONTENT"}
        {"type":"summary.replace","revision":INTEGER,"through_sequence":INTEGER,"text":"SUMMARY AND INDEX REFERENCES"}
        {"type":"summary.patch","revision":INTEGER,"through_sequence":INTEGER,"old":"EXACT PASSAGE OCCURRING ONCE","new":"REPLACEMENT PASSAGE"}
        Use arc quinby act. Retry uncertain acts with the identical token and JSON. Do not reroll a request. Summary changes require the current summary revision and a covered record sequence; the full accepted text is permanently recorded before the summary file is replaced. ARC does no summarizing.
        Use arc quinby read with the same binding and optional --before BYTE_OFFSET to page backwards; next_before is an opaque returned offset, never guess it. A poll page carries next_before for the oldest entry it returned. Page until you reach your previously read sequence; there is no lifetime history limit. Polling, waiting, reading, and qualifying do not count as improvement.
        """
    }

    public func act(incarnation: String, participant: String, binding: String, operation: String, json: Data) throws -> QuinbyActionResult {
        guard json.count <= 131_072, let object = try ARCTerse.decode(json).objectValue,
              let type = object["type"]?.stringValue else { throw invalid() }
        let journal = try journal()
        var state = Self.effective(journal)
        let i = try authenticate(state, incarnation: incarnation, participant: participant, binding: binding)
        let digest = Self.digest(try QuinbyJournal.encoder().encode(ARCJSONValue.object(object)))
        if operation == state.participants[i].previousOperation {
            guard digest == state.participants[i].previousDigest else { throw ARCError(.operationConflict, "That Quinby retry changed its request.") }
            return QuinbyActionResult(sequence: state.participants[i].previousSequence!, nextOperation: state.participants[i].operation)
        }
        guard operation == state.participants[i].operation else { throw ARCError(.operationStale, "Poll for the current Quinby operation token.") }
        let now = try time(state); state.logical = now
        _ = refresh(&state, now: now)
        func exact(_ keys: Set<String>) throws { guard Set(object.keys) == keys.union(["type"]) else { throw invalid() } }
        func integer(_ key: String) throws -> Int64 {
            guard let n = object[key]?.integerValue, n >= 0 else { throw invalid() }; return n
        }
        func hourly(_ times: inout [Int64], limit: Int, label: String) throws {
            times = times.filter { now - $0 < QuinbyLimits.hourUs }
            guard times.count < limit else {
                let wait = (times.min()! + QuinbyLimits.hourUs - now) / 1_000_000
                throw ARCError(.limitExceeded, "At most \(limit) \(label) per hour. Try again in \(max(wait, 1)) seconds; silence is allowed.")
            }
            times.append(now)
        }
        func summaryChange(through: Int64) throws {
            guard through >= state.summary.throughSequence, through <= journal.latest!.sequence else { throw invalid() }
            let recent = now - state.summary.at < QuinbyLimits.summaryIntervalUs
            let sparse = journal.latest!.sequence - state.summary.sequence < QuinbyLimits.summaryMinimumNewEntries
            guard !(recent && sparse) else {
                throw ARCError(.limitExceeded, "The summary was replaced less than 15 minutes ago with fewer than \(QuinbyLimits.summaryMinimumNewEntries) entries since. Wait, or gather more before rewriting.")
            }
            let sequence = journal.latest!.sequence + 1
            state.summary = QuinbySummaryRef(revision: state.summary.revision + 1, throughSequence: through,
                sequence: sequence, frameStart: journal.nextFrameStart, at: now)
        }
        var text = ""
        var kind = type
        if type == "qualification.answer" {
            try exact(["answer"])
            guard state.participants[i].phase == .qualifying,
                  object["answer"]?.stringValue == state.participants[i].challenge else { throw ARCError(.wrongState, "The Quinby access-check answer is not current.") }
            state.participants[i].answered = true
        } else {
            guard state.enabled, state.participants[i].available(now) else { throw ARCError(.wrongState, "Quinby must be on and this AI available before contributing.") }
            switch type {
            case "working":
                try exact(["until_logical_us"])
                let until = try integer("until_logical_us")
                guard until > now, until <= 253_402_300_799_999_999 else { throw invalid() }
                if let current = state.participants[i].workingUntil, current - now > QuinbyLimits.workingRedeclareWindowUs {
                    throw ARCError(.wrongState, "Already Working until \(current). Declare again within 5 minutes of that deadline, or poll to end it.")
                }
                state.participants[i].workingUntil = until
            case "contribute":
                try exact(["text"]); text = try content(object["text"]?.stringValue ?? "")
                try hourly(&state.participants[i].contributionTimes, limit: QuinbyLimits.contributionsPerHour, label: "contributions")
            case "request.direction", "request.thought":
                try exact(["text"]); text = try content(object["text"]?.stringValue ?? "")
                if type == "request.thought" {
                    try hourly(&state.participants[i].thoughtTimes, limit: QuinbyLimits.thoughtsPerHour, label: "thought requests")
                }
                try request(&state, kind: type == "request.direction" ? "direction" : "thought", prompt: text)
            case "complete":
                try exact(["assignment", "generation", "disposition", "text"])
                guard let id = object["assignment"]?.stringValue,
                      let a = state.assignments.firstIndex(where: { $0.id == id }),
                      state.assignments[a].selectedAI == participant,
                      state.assignments[a].generation == (try integer("generation")),
                      let disposition = object["disposition"]?.stringValue,
                      ["reply", "refusal", "silence", "decision"].contains(disposition) else {
                    throw ARCError(.operationStale, "That Quinby assignment is no longer yours. Poll again.")
                }
                guard (state.assignments[a].kind == "direction") == (disposition == "decision" || disposition == "silence")
                        || (state.assignments[a].kind != "direction" && disposition == "silence") else { throw invalid() }
                text = disposition == "silence" ? "" : try content(object["text"]?.stringValue ?? "")
                kind = disposition; state.assignments.remove(at: a)
            case "summary.replace":
                try exact(["revision", "through_sequence", "text"])
                guard try integer("revision") == state.summary.revision else { throw ARCError(.operationStale, "Read the latest summary before replacing it.") }
                text = try content(object["text"]?.stringValue ?? "", maximum: QuinbyLimits.maximumSummaryBytes)
                try summaryChange(through: try integer("through_sequence"))
            case "summary.patch":
                try exact(["revision", "through_sequence", "old", "new"])
                guard try integer("revision") == state.summary.revision else { throw ARCError(.operationStale, "Read the latest summary before patching it.") }
                guard let old = object["old"]?.stringValue, !old.isEmpty, let new = object["new"]?.stringValue else { throw invalid() }
                let current = try journal.summaryText(state.summary)
                let ranges = current.ranges(of: old)
                guard ranges.count == 1 else {
                    throw ARCError(.invalidArgument, "summary.patch old text must occur exactly once in the current summary (found \(ranges.count)).")
                }
                text = try content(current.replacingCharacters(in: ranges[0], with: new), maximum: QuinbyLimits.maximumSummaryBytes)
                try summaryChange(through: try integer("through_sequence"))
            default: throw invalid()
            }
        }
        let sequence = journal.latest!.sequence + 1
        state.participants[i].previousOperation = operation
        state.participants[i].previousDigest = digest
        state.participants[i].previousSequence = sequence
        state.participants[i].operation = UUID().uuidString.lowercased()
        try append(journal, &state, kind: kind, author: participant, text: text)
        if type.hasPrefix("summary.") { try journal.publishSummary(try journal.summary(state)) }
        try note(journal, state: state, participant: participant, now: now, acts: 1)
        return QuinbyActionResult(sequence: sequence, nextOperation: state.participants[i].operation)
    }

    private func refresh(_ state: inout QuinbyState, now: Int64) -> Bool {
        var changed = false
        for i in state.participants.indices {
            if state.participants[i].phase == .qualifying, let first = state.participants[i].firstPoll, now - first >= 120_000_000 {
                state.participants[i].phase = .failed; changed = true
            }
        }
        let eligible = state.enabled ? state.participants.filter { $0.available(now) }.map(\.id).sorted() : []
        for i in state.assignments.indices {
            let old = state.assignments[i].selectedAI
            if old == nil && !eligible.isEmpty || old.map({ !eligible.contains($0) }) == true {
                state.assignments[i].selectedAI = eligible.isEmpty ? nil : eligible[randomIndex(eligible.count)]
                state.assignments[i].eligible = eligible
                state.assignments[i].generation += 1; changed = true
            }
        }
        return changed
    }

    private func request(_ state: inout QuinbyState, kind: String, prompt: String) throws {
        guard state.assignments.count < 50 else { throw ARCError(.limitExceeded, "Quinby already has 50 pending requests.") }
        if kind == "direction", state.assignments.contains(where: { $0.kind == kind }) {
            throw ARCError(.wrongState, "A direction decision is already pending. Discuss it before requesting another.")
        }
        state.assignments.append(QuinbyAssignment(id: UUID().uuidString.lowercased(), kind: kind, prompt: prompt,
            selectedAI: nil, generation: 0, eligible: []))
        _ = refresh(&state, now: state.logical)
    }

    private func invitation(_ member: QuinbyMember, state: QuinbyState) -> QuinbyInvitation {
        let args = [rootURL.appendingPathComponent("current/bin/arc").path, "--root", rootURL.path,
            "quinby", "poll", "--incarnation", state.incarnation, "--id", member.id, "--binding", member.binding]
        let encoded = String(decoding: try! QuinbyJournal.encoder().encode(args), as: UTF8.self)
        let guideArgs = args.enumerated().map { $0.offset == 4 ? "guide" : $0.element }
        let guide = String(decoding: try! QuinbyJournal.encoder().encode(guideArgs), as: UTF8.self)
        return QuinbyInvitation(incarnation: state.incarnation, participant: member.id, binding: member.binding,
            arguments: args, instructions: "Quinby's Corner: \(member.name)\nRun this exact argument array and read the complete guide:\n\(guide)\nThen poll using:\n\(encoded)\nAfter the first poll, add --after NEXT_AFTER from each result, and prefer the wait form the guide describes. Use only this Corner identity. Read Quinby's summary and record before contributing. ARC has no intelligence and cannot wake your AI host.")
    }

    private func authenticate(_ state: QuinbyState, incarnation: String, participant: String, binding: String) throws -> Int {
        guard state.incarnation == incarnation else { throw ARCError(.retired, "That Quinby no longer exists. Remove this lane's recurring automations.") }
        guard let i = state.participants.firstIndex(where: { $0.id == participant }) else { throw ARCError(.retired, "This AI is no longer in Quinby's Corner. Remove this lane's recurring automations.") }
        guard ARCText.isLowerUUID(binding), state.participants[i].binding == binding else { throw ARCError(.bindingInvalid, "The Corner binding is no longer current.") }
        return i
    }

    private func adminReplay(_ state: inout QuinbyState, operation: UUID, request: String) throws -> Bool {
        let token = operation.uuidString.lowercased(), digest = Self.digest(Data(request.utf8))
        if state.lastAdminOperation == token {
            guard state.lastAdminDigest == digest else { throw ARCError(.operationConflict, "That Quinby retry changed its request.") }
            return true
        }
        state.lastAdminOperation = token; state.lastAdminDigest = digest
        return false
    }

    private func content(_ text: String, maximum: Int = 16_384) throws -> String {
        try ARCText.require(text, label: "Quinby contribution", maximumBytes: maximum, allowNewlines: true, trimWhitespace: false)
    }
    private func invalid() -> ARCError { ARCError(.invalidArgument, "The Quinby request has invalid fields or values. Read the Corner guide.") }
    private func missing() -> ARCError { ARCError(.notFound, "That AI is not in Quinby's Corner.") }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // MARK: Presence and the cost meter

    static func communicationStatus(rootURL: URL) -> QuinbyCommunicationStatus {
        let notice = ARCCommunication.snapshot(rootURL: rootURL)
        return QuinbyCommunicationStatus(status: notice.status, specificationSha256: notice.specificationSha256,
            operatorLanguage: notice.operatorLanguage)
    }

    static func usage(_ member: QuinbyPresence.Member?, now: Int64) -> QuinbyUsage { ARCMeter.usage(member, now: now) }
    static func servedBytes<T: Encodable>(_ value: T) -> Int64 { ARCMeter.servedBytes(value) }

    private func note(_ journal: QuinbyJournal, state: QuinbyState, participant: String, now: Int64,
                      polls: Int = 0, waits: Int = 0, reads: Int = 0, acts: Int = 0, bytes: Int64 = 0,
                      renew: (lastPoll: Int64, dutyUntil: Int64?)? = nil) throws {
        var presence = journal.presence.flatMap { $0.incarnation == state.incarnation ? $0 : nil }
            ?? QuinbyPresence(incarnation: state.incarnation)
        presence.logical = max(presence.logical, now)
        var member = presence.members[participant] ?? QuinbyPresence.Member()
        ARCMeter.count(&member, now: now, polls: polls, waits: waits, reads: reads, acts: acts, bytes: bytes)
        if let renew { member.lastPoll = renew.lastPoll; member.dutyUntil = renew.dutyUntil }
        presence.members[participant] = member
        try journal.savePresence(presence)
    }

    // MARK: Hearing

    /// Room events that describe presence mechanics rather than conversation.
    /// They are not audible: they would only make every Corner AI read noise.
    static let inaudibleKinds: Set<String> = ["AI_RETURNED_ON_DUTY", "AI_WORKING", "AI_JOINED",
        "QUALIFICATION_ANSWERED", "QUALIFICATION_FAILED", "QUALIFICATION_RECOVERED", "QUALIFICATION_RETRIED"]

    /// Called while holding the ordinary room lock. The Corner lock remains
    /// held through source publication. Recovery reads atomic room bytes without
    /// taking room locks, so lock order is always room -> Corner, never reversed.
    static func capture<T>(root: URL, data: Data, priorSequence: Int64, publish: () throws -> T) throws -> T {
        let path = root.appendingPathComponent("quinby/records.arcquinby")
        guard FileManager.default.fileExists(atPath: path.path) else { return try publish() }
        let journal: QuinbyJournal
        do { journal = try QuinbyJournal(root: root) }
        catch let error as ARCError where error.code == .roomIncompatible { return try publish() }
        try recoverCapture(journal, root: root)
        guard let latest = journal.latest, !latest.state.resetting, latest.state.enabled else { return try publish() }
        let current = effective(journal)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let document = try decoder.decode(ARCRoomDocument.self, from: data)
        let now = max(latest.state.logical, document.room.lastClockLogicalUs)
        guard current.participants.contains(where: { $0.available(now) }) else {
            if latest.state.available {
                var state = latest.state; state.logical = now; state.available = false
                try journal.append(QuinbyFrame(sequence: latest.sequence + 1, at: ARCTime.timestamp(now),
                    kind: "availability", author: "ARC", text: "", state: state))
            }
            return try publish()
        }
        let events = document.activity.filter {
            $0.sequence > priorSequence && $0.payload.objectValue?["time_verified"]?.boolValue != false
                && !inaudibleKinds.contains($0.kind)
        }
        guard !events.isEmpty else { return try publish() }
        let observations = events.map { event in
            QuinbyObservation(room: document.room.id, roomName: document.room.name, sequence: event.sequence,
                at: event.at, kind: event.kind, actor: event.actor,
                actorName: document.participants.first(where: { $0.id == event.actor })?.name ?? event.actor,
                recipient: event.recipient, subject: event.subject, payload: event.payload)
        }
        var state = recordable(current); state.logical = now; state.available = true
        let source = root.appendingPathComponent("rooms/\(document.room.id).arcroom")
        let previous = FileManager.default.fileExists(atPath: source.path)
            ? try digest(readBoundedRegularFile(source, maximumBytes: ARCConstants.maximumRoomBytes)) : nil
        let pending = QuinbyCapture(room: document.room.id, expectedSHA256: digest(data), previousSHA256: previous, observations: observations)
        try journal.append(QuinbyFrame(sequence: latest.sequence + 1, at: ARCTime.timestamp(now),
            kind: "capture.intent", author: "ARC", text: "", state: state, pending: pending))
        let result = try publish()
        try recoverCapture(journal, root: root)
        return result
    }

    static func recoverCapture(_ journal: QuinbyJournal, root: URL) throws {
        guard let latest = journal.latest, let pending = latest.pending else { return }
        guard ARCText.isSafeID(pending.room, prefix: "room-") else { throw QuinbyJournal.corrupt() }
        let path = root.appendingPathComponent("rooms/\(pending.room).arcroom")
        var info = stat()
        let exists = lstat(path.path, &info) == 0
        guard exists || errno == ENOENT else { throw QuinbyJournal.failure() }
        let sourceDigest = exists ? try digest(readBoundedRegularFile(path, maximumBytes: ARCConstants.maximumRoomBytes)) : nil
        let committed = sourceDigest == pending.expectedSHA256
        guard committed || sourceDigest == pending.previousSHA256 else { throw QuinbyJournal.corrupt() }
        var state = latest.state
        if committed { state.lastActivity = state.logical }
        try journal.append(QuinbyFrame(sequence: latest.sequence + 1, at: latest.at,
            kind: committed ? "heard" : "capture.cancel", author: "ARC", text: "", state: state,
            observations: committed ? pending.observations : []))
    }
}
