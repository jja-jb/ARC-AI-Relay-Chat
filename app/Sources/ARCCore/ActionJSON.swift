import Foundation

public enum ARCActionJSON {
    public static func decode(_ data: Data) throws -> ARCActionRequest {
        guard !data.isEmpty, data.count <= 131_072 else {
            throw ARCError(.invalidArgument, "The action JSON is empty or too large.")
        }
        var parser = ARCStrictJSONParser(data: data)
        let value = try parser.parse()
        guard let object = value.objectValue, let type = object["type"]?.stringValue else {
            throw ARCError(.invalidArgument, "The action must be one JSON object with a type.")
        }

        switch type {
        case "working":
            try exact(object, keys: ["type", "until_logical_us"])
            return .working(untilLogicalUs: try positive(object["until_logical_us"], label: "Working deadline"))
        case "message":
            try exact(object, keys: ["type", "to", "text"])
            return .message(
                to: try id(object["to"], prefix: "ai-", label: "Message target"),
                text: try text(object["text"], label: "Message", maximum: 16_384,
                               allowNewlines: true, trimWhitespace: false)
            )
        case "message.broadcast":
            try exact(object, keys: ["type", "text"])
            return .messageBroadcast(text: try text(object["text"], label: "Message",
                maximum: 16_384, allowNewlines: true, trimWhitespace: false))
        case "qualification.start":
            try exact(object, keys: ["type", "participant", "producer_generation"])
            return .qualificationStart(
                participant: try id(
                    object["participant"], prefix: "ai-", label: "AI participant"
                ),
                producerGeneration: try positive(
                    object["producer_generation"], label: "Producer generation"
                )
            )
        case "qualification.answer":
            try exact(object, keys: ["type", "answer"])
            return .qualificationAnswer(
                answer: try text(object["answer"], label: "Qualification answer", maximum: 80)
            )
        case "work.assign":
            try exact(object, keys: [
                "type", "owner", "scope", "evidence_mode", "producer_generation",
            ])
            guard let modeText = object["evidence_mode"]?.stringValue,
                  let mode = ARCEvidenceMode(rawValue: modeText) else {
                throw ARCError(.invalidArgument, "Evidence mode must be TEXT or VISUAL.")
            }
            return .workAssign(
                owner: try id(object["owner"], prefix: "ai-", label: "Work owner"),
                scope: try text(object["scope"], label: "Work scope", maximum: 4_096,
                                allowNewlines: true),
                evidenceMode: mode,
                producerGeneration: try positive(
                    object["producer_generation"], label: "Producer generation"
                )
            )
        case "work.update":
            try exact(object, keys: ["type", "work", "revision", "state", "evidence"])
            guard let stateText = object["state"]?.stringValue,
                  let state = ARCWorkState(rawValue: stateText), state != .open,
                  let evidence = object["evidence"] else {
                throw ARCError(.invalidArgument, "The work update state or evidence is invalid.")
            }
            let normalizedEvidence = normalize(evidence)
            return .workUpdate(
                work: try id(object["work"], prefix: "work-", label: "Work item"),
                revision: try positive(object["revision"], label: "Work revision"),
                state: state,
                evidence: normalizedEvidence
            )
        case "work.reassign":
            try exact(object, keys: [
                "type", "work", "revision", "owner", "reason", "producer_generation",
            ])
            return .workReassign(
                work: try id(object["work"], prefix: "work-", label: "Work item"),
                revision: try positive(object["revision"], label: "Work revision"),
                owner: try id(object["owner"], prefix: "ai-", label: "Work owner"),
                reason: try text(object["reason"], label: "Reason", maximum: 1_024,
                                 allowNewlines: true),
                producerGeneration: try positive(
                    object["producer_generation"], label: "Producer generation"
                )
            )
        default:
            throw ARCError(.invalidArgument, "The action type is not supported by ARC \(ARCConstants.version).")
        }
    }

    public static func encode(_ request: ARCActionRequest) throws -> Data {
        let value: ARCJSONValue
        switch request {
        case .working(let deadline):
            value = .object(["type": .string("working"), "until_logical_us": .integer(deadline)])
        case .message(let to, let text):
            value = .object(["type": .string("message"), "to": .string(to), "text": .string(text)])
        case .messageBroadcast(let text):
            value = .object(["type": .string("message.broadcast"), "text": .string(text)])
        case .qualificationStart(let participant, let generation):
            value = .object([
                "type": .string("qualification.start"),
                "participant": .string(participant),
                "producer_generation": .integer(generation),
            ])
        case .qualificationAnswer(let answer):
            value = .object(["type": .string("qualification.answer"), "answer": .string(answer)])
        case .workAssign(let owner, let scope, let mode, let generation):
            value = .object([
                "type": .string("work.assign"), "owner": .string(owner),
                "scope": .string(scope), "evidence_mode": .string(mode.rawValue),
                "producer_generation": .integer(generation),
            ])
        case .workUpdate(let work, let revision, let state, let evidence):
            value = .object([
                "type": .string("work.update"), "work": .string(work),
                "revision": .integer(revision), "state": .string(state.rawValue),
                "evidence": evidence,
            ])
        case .workReassign(let work, let revision, let owner, let reason, let generation):
            value = .object([
                "type": .string("work.reassign"), "work": .string(work),
                "revision": .integer(revision), "owner": .string(owner),
                "reason": .string(reason), "producer_generation": .integer(generation),
            ])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func exact(
        _ object: [String: ARCJSONValue], keys: Set<String>
    ) throws {
        guard Set(object.keys) == keys else {
            throw ARCError(.invalidArgument, "The action has a missing or unknown field.")
        }
    }

    private static func text(
        _ value: ARCJSONValue?, label: String, maximum: Int, allowNewlines: Bool = false,
        trimWhitespace: Bool = true
    ) throws -> String {
        guard let string = value?.stringValue else {
            throw ARCError(.invalidArgument, "\(label) must be text.")
        }
        return try ARCText.require(
            string, label: label, maximumBytes: maximum, allowNewlines: allowNewlines,
            trimWhitespace: trimWhitespace
        )
    }

    private static func id(
        _ value: ARCJSONValue?, prefix: String, label: String
    ) throws -> String {
        guard let string = value?.stringValue, ARCText.isSafeID(string, prefix: prefix) else {
            throw ARCError(.invalidArgument, "\(label) is invalid.")
        }
        return string
    }

    private static func positive(_ value: ARCJSONValue?, label: String) throws -> Int64 {
        guard let integer = value?.integerValue, integer > 0 else {
            throw ARCError(.invalidArgument, "\(label) must be a positive integer.")
        }
        return integer
    }

    private static func normalize(_ value: ARCJSONValue) -> ARCJSONValue {
        switch value {
        case .string(let text): return .string(ARCText.normalized(text))
        case .array(let values): return .array(values.map(normalize))
        case .object(let values): return .object(values.mapValues(normalize))
        default: return value
        }
    }
}

private struct ARCStrictJSONParser {
    private let bytes: [UInt8]
    private var index = 0
    private var valueCount = 0

    init(data: Data) { bytes = Array(data) }

    mutating func parse() throws -> ARCJSONValue {
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw invalid() }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> ARCJSONValue {
        valueCount += 1
        guard valueCount <= 8_192 else {
            throw ARCError(.invalidArgument, "The action JSON has too many values.")
        }
        guard depth <= 32 else {
            throw ARCError(.invalidArgument, "The action JSON is nested too deeply.")
        }
        skipWhitespace()
        guard index < bytes.count else { throw invalid() }
        switch bytes[index] {
        case 0x7B: return try parseObject(depth: depth)
        case 0x5B: return try parseArray(depth: depth)
        case 0x22: return .string(try parseString())
        case 0x74: try keyword("true"); return .boolean(true)
        case 0x66: try keyword("false"); return .boolean(false)
        case 0x6E: try keyword("null"); return .null
        case 0x2D, 0x30...0x39: return .integer(try parseInteger())
        default: throw invalid()
        }
    }

    private mutating func parseObject(depth: Int) throws -> ARCJSONValue {
        index += 1
        skipWhitespace()
        var result: [String: ARCJSONValue] = [:]
        if take(0x7D) { return .object(result) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else { throw invalid() }
            let key = try parseString()
            guard result[key] == nil else {
                throw ARCError(.invalidArgument, "The action JSON contains a duplicate field.")
            }
            skipWhitespace()
            guard take(0x3A) else { throw invalid() }
            guard result.count < 4_096 else {
                throw ARCError(.invalidArgument, "The action JSON has too many fields.")
            }
            result[key] = try parseValue(depth: depth + 1)
            skipWhitespace()
            if take(0x7D) { return .object(result) }
            guard take(0x2C) else { throw invalid() }
        }
    }

    private mutating func parseArray(depth: Int) throws -> ARCJSONValue {
        index += 1
        skipWhitespace()
        var result: [ARCJSONValue] = []
        if take(0x5D) { return .array(result) }
        while true {
            guard result.count < 4_096 else {
                throw ARCError(.invalidArgument, "The action JSON has too many array items.")
            }
            result.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            if take(0x5D) { return .array(result) }
            guard take(0x2C) else { throw invalid() }
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x20 { throw invalid() }
            if escaped {
                if byte == 0x75 {
                    guard index + 4 < bytes.count,
                          bytes[(index + 1)...(index + 4)].allSatisfy({ $0.isASCIIHex }) else {
                        throw invalid()
                    }
                    index += 5
                } else {
                    guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(byte)
                    else { throw invalid() }
                    index += 1
                }
                escaped = false
            } else if byte == 0x5C {
                escaped = true
                index += 1
            } else if byte == 0x22 {
                index += 1
                let token = Data(bytes[start..<index])
                do { return try JSONDecoder().decode(String.self, from: token) }
                catch { throw invalid() }
            } else {
                index += 1
            }
        }
        throw invalid()
    }

    private mutating func parseInteger() throws -> Int64 {
        let start = index
        if take(0x2D), index == bytes.count { throw invalid() }
        if take(0x30) {
            if index < bytes.count, bytes[index].isASCIIDigit { throw invalid() }
        } else {
            guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else { throw invalid() }
            while index < bytes.count, bytes[index].isASCIIDigit { index += 1 }
        }
        guard index == bytes.count || ![0x2E, 0x45, 0x65].contains(bytes[index]),
              let text = String(bytes: bytes[start..<index], encoding: .utf8),
              let value = Int64(text) else { throw invalid() }
        return value
    }

    private mutating func keyword(_ value: String) throws {
        let wanted = Array(value.utf8)
        guard index + wanted.count <= bytes.count,
              Array(bytes[index..<(index + wanted.count)]) == wanted else { throw invalid() }
        index += wanted.count
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private func invalid() -> ARCError {
        ARCError(.invalidArgument, "The action is not valid strict JSON.")
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { (0x30...0x39).contains(self) }
    var isASCIIHex: Bool {
        isASCIIDigit || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}
