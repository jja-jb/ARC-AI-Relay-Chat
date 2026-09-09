import Foundation

/// A projection of the canonical room's addressed events, never another store.
enum ARCTerseLedger {
    static func packet(_ event: ARCEventRecord) -> ARCJSONValue? {
        event.kind == "TERSE_MESSAGE" ? event.payload.objectValue?["packet"] : nil
    }
    static func visible(_ event: ARCEventRecord, to id: String) -> Bool {
        event.actor == id || event.recipient == nil || event.recipient == id
    }
    static func event(_ sequence: Int64, in document: ARCRoomDocument, reader: String) throws -> ARCEventRecord {
        guard let event = document.activity.first(where: { $0.sequence == sequence }), visible(event, to: reader) else {
            throw ARCError(.notFound, "ARC could not find a readable message at that sequence.")
        }
        return event
    }
    static func declaration(_ document: ARCRoomDocument, sender: ARCParticipantRecord,
                            target: ARCParticipantRecord, digest: String) -> ARCJSONValue? {
        document.activity.reversed().first {
            guard $0.actor == sender.id, $0.recipient == target.id,
                  let payload = $0.payload.objectValue,
                  payload["binding_generation"]?.integerValue == sender.bindingGeneration,
                  payload["target_binding_generation"]?.integerValue == target.bindingGeneration,
                  payload["specification_sha256"]?.stringValue == digest else { return false }
            return packet($0)?.objectValue?["kind"]?.stringValue == "declare"
        }.flatMap(packet)
    }
    static func status(_ document: ARCRoomDocument, caller: ARCParticipantRecord, digest: String) -> ARCJSONValue {
        .object([
            "version": .integer(2), "specification_sha256": .string(digest),
            "meaning": .string("Declarations are participant claims, not proof of reading or understanding. Lost context requires rereading before reuse."),
            "peers": .array(document.participants.filter { $0.id != caller.id && $0.phase != .retired }.map { peer in
                let sent = declaration(document, sender: caller, target: peer, digest: digest)
                let received = declaration(document, sender: peer, target: caller, digest: digest)
                let ownProfiles = profileSet(sent), otherProfiles = profileSet(received)
                return .object(["id": .string(peer.id), "sent": .boolean(sent != nil), "received": .boolean(received != nil),
                    "compatible_profiles": .array(ownProfiles.intersection(otherProfiles).sorted().map(ARCJSONValue.string))])
            })
        ])
    }
    static func profileSet(_ value: ARCJSONValue?) -> Set<String> {
        guard case .array(let profiles) = value?.objectValue?["profiles"] else { return [] }
        return Set(profiles.compactMap(\.stringValue))
    }
    static func resolve(_ sequence: Int64, document: ARCRoomDocument, reader: String) throws -> ARCJSONValue {
        let selected = try event(sequence, in: document, reader: reader)
        var current = selected
        var deltas: [ARCEventRecord] = []
        while packet(current)?.objectValue?["kind"]?.stringValue == "delta" {
            guard deltas.count < 64, let base = packet(current)?.objectValue?["base"]?.integerValue,
                  base < current.sequence else { throw ARCTerse.fail("context chain is invalid or exceeds 64 deltas; publish a new full context.") }
            deltas.append(current)
            current = try event(base, in: document, reader: reader)
            guard current.actor == selected.actor, current.recipient == selected.recipient else { throw ARCTerse.fail("context cannot cross sender or recipient boundaries.") }
        }
        guard let p = packet(current)?.objectValue, p["kind"]?.stringValue == "context", let raw = p["fields"] else {
            throw ARCTerse.fail("sequence does not resolve to a context.")
        }
        var fields = try ARCTerse.fields(raw)
        for delta in deltas.reversed() {
            let d = packet(delta)!.objectValue!
            guard try ARCTerse.digest(.object(fields)) == d["base_sha256"]?.stringValue else { throw ARCTerse.fail("context digest mismatch.") }
            guard case .array(let removed) = d["remove"], let updates = d["set"]?.objectValue else { throw ARCTerse.fail("invalid stored delta.") }
            for key in removed {
                guard let name = key.stringValue, fields.removeValue(forKey: name) != nil else { throw ARCTerse.fail("removed context field does not exist.") }
            }
            fields.merge(updates) { _, new in new }
            _ = try ARCTerse.fields(.object(fields))
        }
        return .object(["sequence": .integer(sequence), "key": p["key"]!, "fields": .object(fields),
                        "sha256": .string(try ARCTerse.digest(.object(fields))), "delta_depth": .integer(Int64(deltas.count))])
    }
    static func validateSend(_ packet: ARCJSONValue, document: ARCRoomDocument,
                             caller: ARCParticipantRecord, target: ARCParticipantRecord, digest: String) throws {
        try ARCTerse.validatePacket(packet)
        let p = packet.objectValue!
        let kind = p["kind"]!.stringValue!
        if kind == "declare" {
            guard p["specification_sha256"]?.stringValue == digest else { throw ARCTerse.fail("read and declare the current verified specification digest.") }
            return
        }
        guard let sent = declaration(document, sender: caller, target: target, digest: digest),
              let received = declaration(document, sender: target, target: caller, digest: digest) else {
            throw ARCTerse.fail("both peers must declare the current specification for their current bindings.")
        }
        if let required = ARCTerse.profile(for: packet) {
            guard profileSet(sent).contains(required), profileSet(received).contains(required) else { throw ARCTerse.fail("the required profile is not agreed by both peers.") }
        }
        if kind == "delta" {
            let base = try event(p["base"]!.integerValue!, in: document, reader: caller.id)
            guard base.actor == caller.id, base.recipient == target.id else { throw ARCTerse.fail("only the original sender can update a context for the same recipient.") }
            let resolved = try resolve(base.sequence, document: document, reader: caller.id).objectValue!
            guard resolved["sha256"] == p["base_sha256"], (resolved["delta_depth"]?.integerValue ?? 64) < 64 else { throw ARCTerse.fail("stale digest or full context required after 64 deltas.") }
            // A context key has a single current branch for this directed pair.
            let key = resolved["key"]
            for later in document.activity.reversed() where later.sequence > base.sequence && later.actor == caller.id && later.recipient == target.id {
                if let candidate = Self.packet(later)?.objectValue {
                    if candidate["kind"]?.stringValue == "context", candidate["key"] == key { throw ARCTerse.fail("stale context; use the newest revision.") }
                    if candidate["kind"]?.stringValue == "delta", try resolve(later.sequence, document: document, reader: caller.id).objectValue?["key"] == key { throw ARCTerse.fail("stale context; use the newest revision.") }
                }
            }
            var changed = resolved["fields"]!.objectValue!
            if case .array(let removals) = p["remove"] {
                for removal in removals { guard changed.removeValue(forKey: removal.stringValue!) != nil else { throw ARCTerse.fail("cannot remove a missing field.") } }
            }
            changed.merge(p["set"]!.objectValue!) { _, new in new }
            _ = try ARCTerse.fields(.object(changed))
            guard changed != resolved["fields"]!.objectValue! else { throw ARCTerse.fail("delta does not change the context.") }
        }
        if kind == "reference" {
            let source = try event(p["sequence"]!.integerValue!, in: document, reader: caller.id)
            guard visible(source, to: target.id),
                  try resolve(source.sequence, document: document, reader: caller.id).objectValue?["sha256"] == p["sha256"] else {
                throw ARCTerse.fail("context reference is unreadable by the peer or has the wrong digest.")
            }
        }
        if kind == "reply" {
            let batch = try event(p["batch"]!.integerValue!, in: document, reader: caller.id)
            guard batch.actor == target.id, batch.recipient == caller.id,
                  let original = Self.packet(batch)?.objectValue, original["kind"]?.stringValue == "batch",
                  case .array(let items) = original["items"], case .array(let answers) = p["answers"] else { throw ARCTerse.fail("reply must name a batch received from that peer.") }
            let ids = Set(items.compactMap { $0.objectValue?["id"]?.stringValue })
            guard answers.allSatisfy({ ids.contains($0.objectValue?["id"]?.stringValue ?? "") }) else { throw ARCTerse.fail("reply names an unknown batch item.") }
        }
        var texts: [String] = []
        if let text = p["text"]?.stringValue { texts.append(text) }
        if case .array(let items) = p["items"] { texts += items.compactMap { $0.objectValue?["text"]?.stringValue } }
        let regex = try NSRegularExpression(pattern: "\"([0-9]+)\\.([0-9]+)\"")
        for text in texts.flatMap({ $0.components(separatedBy: "\n").filter { !$0.hasPrefix("[") } }) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text),
                      let sequence = Int64(text[a]), let number = Int(text[b]), number > 0 else { throw ARCTerse.fail("invalid utterance reference.") }
                let reference = try event(sequence, in: document, reader: caller.id)
                guard visible(reference, to: target.id), let body = reference.payload.objectValue?["text"]?.stringValue else { throw ARCTerse.fail("reference is not visible to both peers.") }
                let lines = body.components(separatedBy: "\n")
                guard number <= lines.count else { throw ARCTerse.fail("referenced line does not exist.") }
                let line = lines[number - 1]
                guard !line.isEmpty, !line.hasPrefix("["), !line.hasPrefix(ARCTerse.prefix) else { throw ARCTerse.fail("sec 4.11: an utterance reference cannot name prose, layout or a packet; discuss those in tagged prose.") }
                guard number < lines.count || body.hasSuffix("\n") else { throw ARCTerse.fail("referenced utterance lacks its required final LF.") }
                try ARCTerse.validateText(lines.prefix(number).joined(separator: "\n") + "\n")
            }
        }
    }
}
