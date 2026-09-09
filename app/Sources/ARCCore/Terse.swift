import CryptoKit
import Foundation

/// Terse is data. These helpers never execute it, fetch a file, change work,
/// infer authority, or claim that syntax proves comprehension or truth.
public enum ARCTerse {
    public static let version = 2
    public static let prefix = "@terse/2 "
    public static let profiles = ["batch/1", "context/1", "dependency/1", "results/1"]
    static let maximumBytes = 16_384

    static func fail(_ message: String) -> ARCError { ARCError(.invalidArgument, "Terse: " + message) }
    static func exact(_ object: [String: ARCJSONValue], _ keys: Set<String>) throws {
        guard Set(object.keys) == keys else { throw fail("missing or unknown fields.") }
    }
    static func object(_ value: ARCJSONValue) throws -> [String: ARCJSONValue] {
        guard let result = value.objectValue else { throw fail("expected an object.") }
        return result
    }
    static func string(_ value: ARCJSONValue?) throws -> String {
        guard let value = value?.stringValue else { throw fail("expected text.") }
        return value
    }
    static func positive(_ value: ARCJSONValue?) throws -> Int64 {
        guard let n = value?.integerValue, n > 0 else { throw fail("expected a positive integer.") }
        return n
    }
    static func name(_ value: ARCJSONValue?) throws -> String {
        let value = try string(value)
        guard value.range(of: "^[a-z][a-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            throw fail("keys must be 1–64 lowercase ASCII letters, digits, underscores or hyphens, starting with a letter.")
        }
        return value
    }
    public static func decode(_ data: Data) throws -> ARCJSONValue {
        guard !data.isEmpty, data.count <= 131_072 else { throw fail("input exceeds 131072 bytes.") }
        var parser = ARCStrictJSONParser(data: data)
        return try parser.parse()
    }
    public static func canonical(_ value: ARCJSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    public static func digest(_ value: ARCJSONValue) throws -> String {
        SHA256.hash(data: Data(try canonical(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public static func build(_ packet: ARCJSONValue) throws -> String {
        try validatePacket(packet)
        return prefix + (try canonical(packet)) + "\n"
    }
    static func fields(_ value: ARCJSONValue) throws -> [String: ARCJSONValue] {
        let values = try object(value)
        guard !values.isEmpty, values.count <= 64 else { throw fail("context needs 1–64 fields.") }
        for (key, value) in values {
            _ = try name(.string(key))
            switch value {
            case .string(let text):
                guard text.utf8.count <= 4096,
                      !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" }) else {
                    throw fail("context text is too long or contains controls.")
                }
            case .integer, .boolean, .null: break
            default: throw fail("context values must be strings, integers, booleans or null.")
            }
        }
        guard try canonical(value).utf8.count <= 12_288 else { throw fail("resolved context exceeds 12288 bytes.") }
        return values
    }
    static func array(_ value: ARCJSONValue?, maximum: Int = 32) throws -> [ARCJSONValue] {
        guard case .array(let values) = value, !values.isEmpty, values.count <= maximum else {
            throw fail("expected 1–\(maximum) entries.")
        }
        return values
    }
    static func choice(_ value: ARCJSONValue?, _ choices: Set<String>) throws {
        guard choices.contains(try string(value)) else { throw fail("unsupported value.") }
    }

    public static func validatePacket(_ packet: ARCJSONValue) throws {
        guard try canonical(packet).utf8.count <= maximumBytes - prefix.utf8.count - 1 else {
            throw fail("packet exceeds the message size limit.")
        }
        let p = try object(packet)
        switch try string(p["kind"]) {
        case "declare":
            try exact(p, ["kind", "version", "specification_sha256", "profiles"])
            guard p["version"]?.integerValue == 2, ARCText.isSHA256(try string(p["specification_sha256"])) else {
                throw fail("declaration requires version 2 and the full specification digest.")
            }
            guard case .array(let values) = p["profiles"], values.count <= profiles.count else { throw fail("invalid profiles.") }
            let names = try values.map { try string($0) }
            guard names == names.sorted(), Set(names).count == names.count,
                  Set(names).isSubset(of: Set(profiles)) else { throw fail("profiles must be unique, sorted and supported.") }
        case "context":
            try exact(p, ["kind", "key", "fields"])
            _ = try name(p["key"]); _ = try fields(p["fields"]!)
        case "reference":
            try exact(p, ["kind", "sequence", "sha256"])
            _ = try positive(p["sequence"])
            guard ARCText.isSHA256(try string(p["sha256"])) else { throw fail("invalid context digest.") }
        case "delta":
            try exact(p, ["kind", "base", "base_sha256", "set", "remove"])
            _ = try positive(p["base"])
            guard ARCText.isSHA256(try string(p["base_sha256"])) else { throw fail("invalid base digest.") }
            let updates = try object(p["set"]!)
            if !updates.isEmpty { _ = try fields(.object(updates)) }
            guard case .array(let removals) = p["remove"], removals.count <= 64 else { throw fail("invalid removals.") }
            let keys = try removals.map { try name($0) }
            guard Set(keys).count == keys.count, Set(keys).isDisjoint(with: updates.keys),
                  !keys.isEmpty || !updates.isEmpty else { throw fail("delta has duplicate, overlapping or no changes.") }
        case "batch":
            try exact(p, ["kind", "items"])
            let items = try array(p["items"])
            var names = Set<String>()
            for item in items {
                let v = try object(item)
                try exact(v, ["id", "text"])
                guard names.insert(try name(v["id"])).inserted else { throw fail("duplicate batch item ID.") }
                let text = try string(v["text"])
                guard text.hasSuffix("\n"), text.filter({ $0 == "\n" }).count == 1 else { throw fail("a batch item is one complete line.") }
                try validateText(text)
                guard text.hasPrefix("ASK ") || text.hasPrefix("TELL ") || text.hasPrefix("SEE TELL ") || text.hasPrefix("THINK TELL ") else {
                    throw fail("batches carry independent questions and reports, not directives or commitments.")
                }
            }
        case "reply":
            try exact(p, ["kind", "batch", "answers"])
            _ = try positive(p["batch"])
            let answers = try array(p["answers"])
            var ids = Set<String>()
            for answer in answers {
                let v = try object(answer)
                try exact(v, ["id", "status"])
                guard ids.insert(try name(v["id"])).inserted else { throw fail("duplicate reply ID.") }
                try choice(v["status"], ["received", "understood", "agree", "disagree", "blocked"])
            }
        case "results":
            try exact(p, ["kind", "subject", "checks"])
            _ = try name(p["subject"])
            var ids = Set<String>()
            for check in try array(p["checks"]) {
                let v = try object(check)
                try exact(v, ["id", "status", "basis"])
                guard ids.insert(try name(v["id"])).inserted else { throw fail("duplicate check ID.") }
                try choice(v["status"], ["pass", "fail", "blocked", "not_run"])
                try choice(v["basis"], ["verified", "inferred", "unmarked"])
                if v["status"]?.stringValue == "not_run", v["basis"]?.stringValue == "verified" {
                    throw fail("a not-run result cannot claim direct verification.")
                }
            }
        case "dependency":
            try exact(p, ["kind", "subject", "requires"])
            let subject = try name(p["subject"])
            let dependencies = try array(p["requires"]).map { try name($0) }
            guard Set(dependencies).count == dependencies.count, !dependencies.contains(subject) else {
                throw fail("duplicate or self dependency.")
            }
        case "lines":
            try exact(p, ["kind", "text"])
            try validateText(try string(p["text"]))
        default: throw fail("unknown packet kind; extensions cannot be invented at runtime.")
        }
    }

    static func profile(for packet: ARCJSONValue) -> String? {
        switch packet.objectValue?["kind"]?.stringValue {
        case "context", "delta", "reference": "context/1"
        case "batch", "reply": "batch/1"
        case "results": "results/1"
        case "dependency": "dependency/1"
        default: nil
        }
    }

    /// Appendix C syntax plus locally decidable constraints. References, role,
    /// binding, evidence, variables and meaning still need their own checks.
    public static func validateText(_ text: String) throws {
        guard !text.isEmpty, text.utf8.count <= maximumBytes, text.hasSuffix("\n") else {
            throw fail("sec 5.10: use a final LF and at most 16384 bytes.")
        }
        var focus = Set<String>()
        for line in text.dropLast().components(separatedBy: "\n") {
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                guard line.hasPrefix("[en] ") || line.hasPrefix("[de] ") else { throw fail("sec 14.9: use [en] or [de].") }
                guard line.count > 5, line.dropFirst(5).unicodeScalars.allSatisfy({ $0.value >= 0x20 && !($0.value >= 0x7f && $0.value < 0xa0) }) else {
                    throw fail("sec 14.6: prose requires nonempty text without controls.")
                }
                continue
            }
            var parser = try TerseLineParser(line)
            try parser.parse()
            let tokens = parser.tokens
            if tokens.contains("THIS"), focus.count != 1 { throw fail("sec 4.14: THIS needs one explicit prior target in this message.") }
            for token in tokens where token.range(of: "^(room|ai|work)-[a-f0-9]{12}$", options: .regularExpression) != nil || token.range(of: "^\"[0-9]+\\.[0-9]+\"$", options: .regularExpression) != nil {
                focus.insert(token)
            }
            if let i = tokens.firstIndex(of: "FILE"), tokens.indices.contains(i + 1) { focus.insert(tokens[i + 1]) }
            if tokens.count >= 4, tokens[0] == "TELL", tokens[1].hasPrefix("\""), tokens[2] == "SAME" { focus.insert(tokens[1]) }
        }
    }
}

private struct TerseLineParser {
    let tokens: [String]
    var offset = 0
    let acts: Set<String> = ["MAKE", "GIVE", "TAKE", "ASK", "TELL", "DO"]
    let referents: Set<String> = ["ME", "YOU", "THIS", "WORK", "WORD", "FILE"]
    let arguments: Set<String> = ["ME", "YOU", "THIS", "WORK", "WORD", "FILE", "GOOD", "BAD", "DONE", "STOP", "HEAR", "NOT", "WHEN", "SAME", "MORE", "LESS", "AND", "OR", "ALL", "SOME", "SEE", "THINK"]
    init(_ line: String) throws {
        guard line.unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else { throw ARCTerse.fail("Appendix C: classic lines are ASCII.") }
        let regex = try NSRegularExpression(pattern: "\"[^\"]*\"|[()]|[^ ()\"]+")
        tokens = regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).map { String(line[Range($0.range, in: line)!]) }
        var reconstructed = ""
        for token in tokens {
            if !reconstructed.isEmpty && token != ")" && !reconstructed.hasSuffix("(") { reconstructed += " " }
            reconstructed += token
        }
        guard reconstructed == line else { throw ARCTerse.fail("sec 5.11: noncanonical spacing or quote.") }
    }
    mutating func parse() throws {
        if take("WHEN") {
            if take("(") { try clause(depth: 1); try require(")") }
            else { guard offset < tokens.count, tokens[offset].hasPrefix("\"") || tokens[offset].range(of: "^-?[0-9]+$", options: .regularExpression) != nil else { throw ARCTerse.fail("sec 5.14: condition needs a time or parenthesized clause.") }; offset += 1 }
        }
        try clause(depth: 0)
        guard offset == tokens.count else { throw ARCTerse.fail("Appendix C: unexpected tokens.") }
        for i in tokens.indices where tokens[i] == "FILE" {
            guard tokens.indices.contains(i + 1), tokens[i + 1].hasPrefix("\"/"), tokens[i + 1].hasSuffix("\"") else { throw ARCTerse.fail("sec 11.2: FILE needs an absolute quoted path.") }
            if i > 0, tokens[i - 1] == "GIVE" {
                guard tokens.indices.contains(i + 3), tokens[i + 2].hasPrefix("\"sha256:"), referents.contains(tokens[i + 3]) else { throw ARCTerse.fail("sec 11.3: GIVE FILE needs a digest and addressee.") }
            }
        }
        if let i = tokens.firstIndex(of: "DO") {
            var rest = Array(tokens.dropFirst(i + 1))
            if rest.first == "ALL" { rest.removeFirst() }
            guard rest.first == "YOU" else { throw ARCTerse.fail("sec 15.5: DO requires YOU or ALL YOU.") }
            rest.removeFirst()
            if rest.first == "ALL" || rest.first == "SOME" { rest.removeFirst() }
            guard rest.count == 2 || rest.count == 3,
                  !["THIS", "FILE"].contains(rest[0]),
                  referents.contains(rest[0]) || rest[0] == "STOP" || rest[0].range(of: "^(ai|work|room)-[a-f0-9]{12}$", options: .regularExpression) != nil,
                  let generation = Int64(rest[1]), generation > 0 else { throw ARCTerse.fail("sec 15: invalid DO target or generation.") }
            if rest.count == 3, rest[2].range(of: "^\"[1-9][0-9]*\\.[1-9][0-9]*\"$", options: .regularExpression) == nil { throw ARCTerse.fail("sec 15.21: retry needs the original utterance reference.") }
        }
        if tokens.starts(with: ["TELL", "NOT", "HEAR"]), tokens.count != 4 || !tokens[3].hasPrefix("\"") || tokens[3].count <= 2 { throw ARCTerse.fail("sec 10.4: name the failed token or section.") }
    }
    mutating func clause(depth: Int) throws {
        guard depth <= 16 else { throw ARCTerse.fail("nesting exceeds 16.") }
        let hasEvidence = take("SEE") || take("THINK")
        _ = take("WAS") || take("WILL")
        if offset < tokens.count, referents.contains(tokens[offset]) { offset += 1 }
        guard offset < tokens.count, acts.contains(tokens[offset]) else { throw ARCTerse.fail("Appendix C: expected one act after ordered markers.") }
        if tokens[offset] == "DO", hasEvidence { throw ARCTerse.fail("sec 15.17: DO cannot carry fronted evidence.") }
        offset += 1
        while offset < tokens.count && tokens[offset] != ")" { try argument(depth: depth) }
    }
    mutating func argument(depth: Int) throws {
        if take("(") {
            guard depth < 16, offset < tokens.count, tokens[offset] != ")" else { throw ARCTerse.fail("invalid group.") }
            repeat { try argument(depth: depth + 1) } while offset < tokens.count && tokens[offset] != ")"
            try require(")")
        } else {
            guard offset < tokens.count, arguments.contains(tokens[offset]) || literal(tokens[offset]) else { throw ARCTerse.fail("Appendix C: unknown word, misplaced act or invalid literal.") }
            offset += 1
        }
    }
    func literal(_ value: String) -> Bool {
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            if value.hasPrefix("\"sha256:") { return ARCText.isSHA256(String(value.dropFirst(8).dropLast())) }
            return true
        }
        return value.range(of: "^-?[0-9]+$", options: .regularExpression) != nil ||
            (value.range(of: "^[A-Za-z0-9]+-[A-Za-z0-9]+$", options: .regularExpression) != nil && value.rangeOfCharacter(from: .letters) != nil)
    }
    mutating func take(_ value: String) -> Bool {
        guard offset < tokens.count, tokens[offset] == value else { return false }
        offset += 1; return true
    }
    mutating func require(_ value: String) throws { guard take(value) else { throw ARCTerse.fail("unbalanced parentheses.") } }
}
