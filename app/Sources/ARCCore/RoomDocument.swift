import CoreFoundation
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct ARCRoomDocument: Codable, Sendable {
    var format: String
    var room: ARCRoomRecord
    var participants: [ARCParticipantRecord]
    var work: [ARCWorkRecord]
    var activity: [ARCEventRecord]
}

struct ARCRoomRecord: Codable, Sendable {
    var id: String
    var name: String
    var createdAt: String
    var updatedAt: String
    var revision: Int64
    var nextSequence: Int64
    var producerId: String?
    var producerGeneration: Int64
    var producerEverSelected: Bool
    var lastClockLogicalUs: Int64
    var lastAdminOperation: ARCAdminOperationRecord?
}

struct ARCAdminOperationRecord: Codable, Sendable {
    var id: String
    var requestDigest: String
}

struct ARCParticipantRecord: Codable, Sendable {
    var id: String
    var name: String
    var phase: ARCParticipantPhase
    var binding: String?
    var bindingGeneration: Int64
    var qualification: ARCQualificationRecord?
    var lastPollLogicalUs: Int64?
    var nextOperation: String
    var lastOperation: ARCLastOperationRecord?
}

struct ARCQualificationRecord: Codable, Sendable {
    var challenge: String
    var startedLogicalUs: Int64
    var firstPollLogicalUs: Int64?
    var answerLogicalUs: Int64?
}

struct ARCLastOperationRecord: Codable, Sendable {
    var token: String
    var requestDigest: String
    var eventSequences: [Int64]
    var roomRevision: Int64
    var participantId: String?
    var workId: String?
    var nextOperation: String
}

struct ARCWorkRecord: Codable, Sendable {
    var id: String
    var owner: String
    var state: ARCWorkState
    var scope: String
    var evidenceMode: ARCEvidenceMode
    var evidence: ARCJSONValue
    var assigningProducerGeneration: Int64
    var revision: Int64
    var createdAt: String
    var updatedAt: String
    var updatedLogicalUs: Int64
}

struct ARCEventRecord: Codable, Sendable {
    var sequence: Int64
    var at: String
    var logicalUs: Int64
    var kind: String
    var actor: String
    var recipient: String?
    var subject: String?
    var payload: ARCJSONValue
    var operationId: String
    var knowledgeSha256: String

    var view: ARCEventView {
        ARCEventView(
            sequence: sequence,
            at: at,
            logicalUs: logicalUs,
            kind: kind,
            actor: actor,
            recipient: recipient,
            subject: subject,
            payload: payload,
            operationId: operationId,
            knowledgeSha256: knowledgeSha256
        )
    }
}

enum ARCText {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    static func require(
        _ raw: String, label: String, maximumBytes: Int,
        maximumCharacters: Int? = nil, allowNewlines: Bool = false,
        allowPathSeparator: Bool = true
    ) throws -> String {
        let value = normalized(raw)
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              maximumCharacters.map({ value.count <= $0 }) ?? true else {
            let limit = maximumCharacters.map { "\($0) characters and " } ?? ""
            throw ARCError(
                .invalidArgument,
                "\(label) must be within \(limit)\(maximumBytes) UTF-8 bytes."
            )
        }
        guard !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
                && (allowNewlines ? ($0 != "\n" && $0 != "\t") : true)
        }) else {
            throw ARCError(.invalidArgument, "\(label) contains a control character.")
        }
        guard allowPathSeparator || !value.contains("/") else {
            throw ARCError(.invalidArgument, "\(label) cannot contain a path separator.")
        }
        return value
    }

    static func isCanonical(
        _ value: String, maximumBytes: Int, maximumCharacters: Int? = nil,
        allowNewlines: Bool = false, allowPathSeparator: Bool = true
    ) -> Bool {
        value == normalized(value) && !value.isEmpty && value.utf8.count <= maximumBytes
            && (maximumCharacters.map { value.count <= $0 } ?? true)
            && (allowPathSeparator || !value.contains("/"))
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
                    && (allowNewlines ? ($0 != "\n" && $0 != "\t") : true)
            })
    }

    static func isSafeID(_ value: String, prefix: String) -> Bool {
        guard value.count == prefix.count + 12, value.hasPrefix(prefix) else { return false }
        return value.dropFirst(prefix.count).utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    static func isLowerUUID(_ value: String) -> Bool {
        guard value.count == 36, value == value.lowercased(), let uuid = UUID(uuidString: value)
        else { return false }
        return uuid.uuidString.lowercased() == value
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    static func randomID(prefix: String) -> String {
        prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            .lowercased().prefix(12)
    }

    static func randomUUID() -> String { UUID().uuidString.lowercased() }
    static func challenge() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

enum ARCTime {
    private static let maximumLogicalUS: Int64 = 253_402_300_799_999_999
    static let maximumQualificationStartLogicalUS = maximumLogicalUS - 120_000_000

    static func logicalUS(_ date: Date) throws -> Int64 {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0, seconds < 253_402_300_800 else {
            throw ARCError(.clockUnavailable, "ARC cannot check time.")
        }
        return Int64((seconds * 1_000_000).rounded(.down))
    }

    static func isLogical(_ value: Int64) -> Bool {
        (0...maximumLogicalUS).contains(value)
    }

    static func timestamp(_ logicalUS: Int64) -> String {
        let seconds = logicalUS / 1_000_000
        let microseconds = logicalUS % 1_000_000
        var epoch = time_t(seconds)
        var value = tm()
        guard gmtime_r(&epoch, &value) != nil else { return "" }
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%06lldZ",
            value.tm_year + 1_900, value.tm_mon + 1, value.tm_mday,
            value.tm_hour, value.tm_min, value.tm_sec, microseconds
        )
    }

    static func isTimestamp(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 27,
              bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x54,
              bytes[13] == 0x3A, bytes[16] == 0x3A, bytes[19] == 0x2E,
              bytes[26] == 0x5A else { return false }
        let digitPositions = [
            0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18,
            20, 21, 22, 23, 24, 25,
        ]
        guard digitPositions.allSatisfy({ (0x30...0x39).contains(bytes[$0]) }) else {
            return false
        }
        func number(_ start: Int, _ count: Int) -> Int {
            bytes[start..<(start + count)].reduce(0) { $0 * 10 + Int($1 - 0x30) }
        }
        let year = number(0, 4)
        let month = number(5, 2)
        let day = number(8, 2)
        let hour = number(11, 2)
        let minute = number(14, 2)
        let second = number(17, 2)
        guard year >= 1, (1...12).contains(month), hour < 24,
              minute < 60, second < 60 else { return false }
        let leap = year.isMultiple(of: 4)
            && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }
}

/// ARC's room bytes are defined here rather than delegated to Foundation's
/// undocumented pretty-print layout. The encoder accepts only the JSON types
/// produced by ARC's typed records and emits one deterministic UTF-8 form.
enum ARCCanonicalJSON {
    static func encode(_ value: Any) throws -> Data {
        var output = Data()
        try append(value, depth: 0, to: &output)
        return output
    }

    private static func append(_ value: Any, depth: Int, to output: inout Data) throws {
        if value is NSNull {
            output.append(contentsOf: "null".utf8)
        } else if let value = value as? String {
            appendString(value, to: &output)
        } else if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                output.append(contentsOf: (value.boolValue ? "true" : "false").utf8)
            } else {
                let numericType = String(cString: value.objCType)
                guard !["f", "d", "D"].contains(numericType),
                      let integer = Int64(value.stringValue) else {
                    throw ARCError(.roomCorrupt, "ARC JSON contains a non-integer number.")
                }
                output.append(contentsOf: String(integer).utf8)
            }
        } else if let values = value as? [Any] {
            output.append(0x5B)
            output.append(0x0A)
            if values.isEmpty { output.append(0x0A) }
            for index in values.indices {
                appendIndent(depth + 1, to: &output)
                try append(values[index], depth: depth + 1, to: &output)
                if index != values.index(before: values.endIndex) { output.append(0x2C) }
                output.append(0x0A)
            }
            appendIndent(depth, to: &output)
            output.append(0x5D)
        } else if let values = value as? [String: Any] {
            output.append(0x7B)
            output.append(0x0A)
            if values.isEmpty { output.append(0x0A) }
            let keys = values.keys.sorted {
                $0.utf8.lexicographicallyPrecedes($1.utf8)
            }
            for index in keys.indices {
                let key = keys[index]
                appendIndent(depth + 1, to: &output)
                appendString(key, to: &output)
                output.append(contentsOf: " : ".utf8)
                try append(values[key]!, depth: depth + 1, to: &output)
                if index != keys.index(before: keys.endIndex) { output.append(0x2C) }
                output.append(0x0A)
            }
            appendIndent(depth, to: &output)
            output.append(0x7D)
        } else {
            throw ARCError(.roomCorrupt, "ARC JSON contains an unsupported value.")
        }
    }

    private static func appendIndent(_ depth: Int, to output: inout Data) {
        output.append(contentsOf: repeatElement(UInt8(0x20), count: depth * 2))
    }

    private static func appendString(_ value: String, to output: inout Data) {
        output.append(0x22)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: output.append(contentsOf: "\\b".utf8)
            case 0x09: output.append(contentsOf: "\\t".utf8)
            case 0x0A: output.append(contentsOf: "\\n".utf8)
            case 0x0C: output.append(contentsOf: "\\f".utf8)
            case 0x0D: output.append(contentsOf: "\\r".utf8)
            case 0x22: output.append(contentsOf: "\\\"".utf8)
            case 0x5C: output.append(contentsOf: "\\\\".utf8)
            case 0x00...0x1F:
                output.append(contentsOf: String(
                    format: "\\u%04x", scalar.value
                ).utf8)
            default:
                output.append(contentsOf: String(scalar).utf8)
            }
        }
        output.append(0x22)
    }
}

enum ARCRoomCodec {
    private static func typedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func encode(_ document: ARCRoomDocument) throws -> Data {
        try validate(document)
        let typed: Data
        do { typed = try typedEncoder().encode(document) }
        catch { throw ARCError(.roomCorrupt, "ARC could not encode the room.") }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: typed) }
        catch { throw ARCError(.roomCorrupt, "ARC could not encode the room.") }
        var data = try ARCCanonicalJSON.encode(object)
        data.append(0x0A)
        guard data.count <= ARCConstants.maximumRoomBytes else {
            throw ARCError(.limitExceeded, "The room reached ARC's 8 MiB size limit.")
        }
        try ARCJSONBounds.preflight(data, errorCode: .limitExceeded)
        return data
    }

    static func decode(_ data: Data, expectedID: String) throws -> ARCRoomDocument {
        guard !data.isEmpty, data.count <= ARCConstants.maximumRoomBytes else {
            throw ARCError(.roomCorrupt, "The room file is empty or larger than 8 MiB.")
        }
        try ARCJSONBounds.preflight(data, errorCode: .roomCorrupt)
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw ARCError(.roomCorrupt, "The room file is not valid JSON.") }
        try validateShape(object)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let document: ARCRoomDocument
        do { document = try decoder.decode(ARCRoomDocument.self, from: data) }
        catch { throw ARCError(.roomCorrupt, "The room file does not match ARC 1.0.") }
        guard document.room.id == expectedID else {
            throw ARCError(.roomCorrupt, "The room file name and Room ID do not match.")
        }
        try validate(document)
        let canonical = try encode(document)
        guard canonical == data else {
            throw ARCError(.roomCorrupt, "The room file is not in canonical ARC JSON form.")
        }
        return document
    }

    static func requestDigest(_ value: ARCActionRequest) throws -> String {
        let data = try ARCActionJSON.encode(value)
        return arcSHA256Hex(data)
    }

    static func digest(_ value: String) -> String {
        arcSHA256Hex(Data(value.utf8))
    }

    static func validate(_ document: ARCRoomDocument) throws {
        guard document.format == ARCConstants.roomFormat else {
            throw ARCError(.roomIncompatible, "This is not an ARC 1.0 room.")
        }
        let room = document.room
        guard ARCText.isSafeID(room.id, prefix: "room-") else {
            throw ARCError(.roomCorrupt, "The Room ID is invalid.")
        }
        guard ARCText.isCanonical(
                  room.name, maximumBytes: 512, maximumCharacters: 80,
                  allowPathSeparator: false
              ),
              ARCTime.isTimestamp(room.createdAt), ARCTime.isTimestamp(room.updatedAt),
              room.createdAt >= "1970-01-01T00:00:00.000000Z",
              room.createdAt <= room.updatedAt,
              room.updatedAt == ARCTime.timestamp(room.lastClockLogicalUs),
              (1..<Int64.max).contains(room.revision),
              (1..<Int64.max).contains(room.nextSequence),
              (0..<Int64.max).contains(room.producerGeneration),
              ARCTime.isLogical(room.lastClockLogicalUs) else {
            throw ARCError(.roomCorrupt, "The room header is invalid.")
        }
        if let operation = room.lastAdminOperation {
            guard ARCText.isLowerUUID(operation.id),
                  ARCText.isSHA256(operation.requestDigest) else {
                throw ARCError(.roomCorrupt, "The Administrator operation record is invalid.")
            }
        }
        guard room.producerEverSelected
                ? room.producerGeneration >= 1
                : (room.producerGeneration == 0 && room.producerId == nil) else {
            throw ARCError(.roomCorrupt, "The Producer history is invalid.")
        }
        guard document.participants.count <= ARCConstants.maximumParticipants,
              document.work.count <= ARCConstants.maximumWorkItems,
              document.work.lazy.filter({ $0.state != .complete }).count
                <= ARCConstants.maximumCurrentWorkItems else {
            throw ARCError(.roomCorrupt, "A room collection exceeds its ARC limit.")
        }

        var participantIDs = Set<String>()
        var participantNames = Set<String>()
        var bindings = Set<String>()
        for participant in document.participants {
            guard ARCText.isSafeID(participant.id, prefix: "ai-"),
                  participantIDs.insert(participant.id).inserted,
                  ARCText.isCanonical(
                      participant.name, maximumBytes: 512, maximumCharacters: 80,
                      allowPathSeparator: false
                  ),
                  participantNames.insert(participant.name.lowercased()).inserted,
                  (1..<Int64.max).contains(participant.bindingGeneration),
                  participant.lastPollLogicalUs.map(ARCTime.isLogical) ?? true,
                  participant.lastPollLogicalUs.map({ $0 <= room.lastClockLogicalUs }) ?? true,
                  ARCText.isLowerUUID(participant.nextOperation) else {
                throw ARCError(.roomCorrupt, "An AI participant record is invalid.")
            }
            if let binding = participant.binding {
                guard ARCText.isLowerUUID(binding), bindings.insert(binding).inserted else {
                    throw ARCError(.roomCorrupt, "An AI binding is invalid or duplicated.")
                }
            }
            switch participant.phase {
            case .qualifying:
                guard let qualification = participant.qualification,
                      qualification.challenge.count == 32,
                      qualification.challenge.utf8.allSatisfy({
                          (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
                      }),
                      ARCTime.isLogical(qualification.startedLogicalUs),
                      qualification.firstPollLogicalUs.map(ARCTime.isLogical) ?? true,
                      qualification.answerLogicalUs.map(ARCTime.isLogical) ?? true,
                      qualification.startedLogicalUs <= room.lastClockLogicalUs,
                      qualification.startedLogicalUs
                        <= ARCTime.maximumQualificationStartLogicalUS,
                      qualification.firstPollLogicalUs.map({
                          $0 >= qualification.startedLogicalUs
                            && $0 <= room.lastClockLogicalUs
                      }) ?? true,
                      qualification.answerLogicalUs.map({ answer in
                          guard let first = qualification.firstPollLogicalUs else {
                              return false
                          }
                          return answer >= first
                            && answer < first + 120_000_000
                            && answer <= room.lastClockLogicalUs
                      }) ?? true else {
                    throw ARCError(.roomCorrupt, "An ARC qualification record is invalid.")
                }
            case .qualified:
                guard participant.qualification == nil,
                      participant.lastPollLogicalUs.map(ARCTime.isLogical) == true,
                      participant.binding != nil else {
                    throw ARCError(.roomCorrupt, "A qualified AI record is incomplete.")
                }
            case .retired:
                guard participant.binding == nil, participant.qualification == nil,
                      participant.lastPollLogicalUs == nil,
                      participant.lastOperation == nil else {
                    throw ARCError(.roomCorrupt, "A retired AI still has an active binding.")
                }
            default:
                guard participant.qualification == nil, participant.binding != nil,
                      participant.lastPollLogicalUs == nil else {
                    throw ARCError(.roomCorrupt, "An AI lifecycle record is inconsistent.")
                }
            }
            if let operation = participant.lastOperation {
                guard ARCText.isLowerUUID(operation.token),
                      ARCText.isSHA256(operation.requestDigest),
                      ARCText.isLowerUUID(operation.nextOperation),
                      operation.nextOperation == participant.nextOperation,
                      operation.token != operation.nextOperation,
                      (1..<Int64.max).contains(operation.roomRevision),
                      operation.roomRevision <= room.revision,
                      !operation.eventSequences.isEmpty,
                      operation.eventSequences.allSatisfy({
                          $0 >= 1 && $0 < room.nextSequence
                      }),
                      zip(
                          operation.eventSequences,
                          operation.eventSequences.dropFirst()
                      ).allSatisfy({ $1 == $0 + 1 }),
                      operation.participantId.map({
                          ARCText.isSafeID($0, prefix: "ai-")
                      }) ?? true,
                      operation.workId.map({
                          ARCText.isSafeID($0, prefix: "work-")
                      }) ?? true else {
                    throw ARCError(.roomCorrupt, "An AI operation record is invalid.")
                }
            }
        }

        if let producerID = room.producerId {
            guard room.producerEverSelected, room.producerGeneration >= 1,
                  let producer = document.participants.first(where: { $0.id == producerID }),
                  producer.phase == .qualified else {
                throw ARCError(.roomCorrupt, "The Producer record is invalid.")
            }
        }

        var workIDs = Set<String>()
        for item in document.work {
            guard ARCText.isSafeID(item.id, prefix: "work-"), workIDs.insert(item.id).inserted,
                  ARCText.isSafeID(item.owner, prefix: "ai-"),
                  ARCText.isCanonical(
                      item.scope, maximumBytes: 4_096, allowNewlines: true
                  ),
                  (1..<Int64.max).contains(item.assigningProducerGeneration),
                  item.assigningProducerGeneration <= room.producerGeneration,
                  (1..<Int64.max).contains(item.revision),
                  ARCTime.isTimestamp(item.createdAt), ARCTime.isTimestamp(item.updatedAt),
                  item.createdAt >= room.createdAt,
                  item.createdAt <= item.updatedAt,
                  ARCTime.isLogical(item.updatedLogicalUs),
                  item.updatedLogicalUs <= room.lastClockLogicalUs,
                  item.updatedAt == ARCTime.timestamp(item.updatedLogicalUs) else {
                throw ARCError(.roomCorrupt, "A work record is invalid.")
            }
            try ARCEvidence.validate(
                item.evidence, state: item.state, mode: item.evidenceMode,
                corrupt: true
            )
        }

        guard !document.activity.isEmpty else {
            throw ARCError(.roomCorrupt, "The room has no Activity record.")
        }
        guard document.activity.first?.sequence == 1 else {
            throw ARCError(.roomCorrupt, "The Activity history is incomplete.")
        }
        var priorSequence: Int64?
        var priorLogical: Int64?
        for event in document.activity {
            try ARCJSONBounds.validate(event.payload, errorCode: .roomCorrupt)
            try validateEventSemantics(event, room: room)
            let payloadEncoder = JSONEncoder()
            payloadEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let payloadBytes = try? payloadEncoder.encode(event.payload),
                  payloadBytes.count <= 65_536 else {
                throw ARCError(.roomCorrupt, "An Activity payload exceeds its ARC limit.")
            }
            guard priorSequence.map({ event.sequence == $0 + 1 }) ?? true,
                  event.sequence >= 1, event.sequence < room.nextSequence,
                  ARCTime.isTimestamp(event.at), ARCTime.isLogical(event.logicalUs),
                  event.at == ARCTime.timestamp(event.logicalUs),
                  event.at >= room.createdAt,
                  event.logicalUs <= room.lastClockLogicalUs,
                  priorLogical.map({ event.logicalUs >= $0 }) ?? true,
                  event.actor == "administrator" || event.actor == "arc"
                    || ARCText.isSafeID(event.actor, prefix: "ai-"),
                  event.recipient.map({ ARCText.isSafeID($0, prefix: "ai-") }) ?? true,
                  event.subject.map({
                      ARCText.isSafeID($0, prefix: "ai-")
                        || ARCText.isSafeID($0, prefix: "work-")
                        || ARCText.isSafeID($0, prefix: "room-")
                  }) ?? true,
                  ARCText.isLowerUUID(event.operationId),
                  ARCText.isSHA256(event.knowledgeSha256) else {
                throw ARCError(.roomCorrupt, "An Activity record is invalid.")
            }
            priorSequence = event.sequence
            priorLogical = event.logicalUs
        }
        if let last = document.activity.last, room.nextSequence - 1 != last.sequence {
            throw ARCError(.roomCorrupt, "The Activity sequence is invalid.")
        }
    }

    private static func validateEventSemantics(
        _ event: ARCEventRecord, room: ARCRoomRecord
    ) throws {
        guard let payload = event.payload.objectValue else {
            throw ARCError(.roomCorrupt, "An Activity payload is invalid.")
        }
        func exact(_ keys: Set<String>) -> Bool { Set(payload.keys) == keys }
        func ai(_ value: String?) -> Bool {
            value.map { ARCText.isSafeID($0, prefix: "ai-") } ?? false
        }
        func work(_ value: String?) -> Bool {
            value.map { ARCText.isSafeID($0, prefix: "work-") } ?? false
        }
        func text(
            _ key: String, maximum: Int, characters: Int? = nil,
            newlines: Bool = false, pathSeparator: Bool = true
        ) -> Bool {
            guard let value = payload[key]?.stringValue else { return false }
            return ARCText.isCanonical(
                value, maximumBytes: maximum, maximumCharacters: characters,
                allowNewlines: newlines, allowPathSeparator: pathSeparator
            )
        }
        func integer(_ key: String, upper: Int64 = Int64.max - 1) -> Bool {
            guard let value = payload[key]?.integerValue else { return false }
            return value >= 1 && value <= upper
        }
        func boolean(_ key: String) -> Bool { payload[key]?.boolValue != nil }
        func emptyTarget() -> Bool { event.recipient == nil && event.subject == nil }
        func sameAITarget() -> Bool {
            ai(event.recipient) && event.recipient == event.subject
        }
        func qualificationStart(actorIsValid: Bool) -> Bool {
            guard actorIsValid, sameAITarget(),
                  payload["answer_type"]?.stringValue == "qualification.answer",
                  let challenge = payload["challenge"]?.stringValue,
                  challenge.utf8.count == 32,
                  challenge.utf8.allSatisfy({
                      (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
                  }) else { return false }
            if exact(["answer_type", "awaiting_first_poll", "challenge"]) {
                return payload["awaiting_first_poll"]?.boolValue == true
            }
            guard exact([
                "answer_type", "awaiting_first_poll", "challenge", "deadline_logical_us",
            ]), payload["awaiting_first_poll"]?.boolValue == false,
                  let deadline = payload["deadline_logical_us"]?.integerValue,
                  event.logicalUs <= ARCTime.maximumQualificationStartLogicalUS else {
                return false
            }
            return deadline == event.logicalUs + 120_000_000
        }
        func evidence(_ state: ARCWorkState) -> Bool {
            guard let value = payload["evidence"] else { return false }
            for mode in [ARCEvidenceMode.text, .visual] {
                if (try? ARCEvidence.validate(
                    value, state: state, mode: mode, corrupt: true
                )) != nil { return true }
            }
            return false
        }

        let valid: Bool
        switch event.kind {
        case "ROOM_CREATED":
            valid = event.actor == "administrator" && emptyTarget()
                && exact(["name"])
                && text("name", maximum: 512, characters: 80, pathSeparator: false)
        case "ROOM_RENAMED":
            valid = event.actor == "administrator" && emptyTarget()
                && exact(["name", "time_verified"])
                && text("name", maximum: 512, characters: 80, pathSeparator: false)
                && boolean("time_verified")
        case "AI_INVITED":
            valid = event.actor == "administrator" && sameAITarget()
                && exact(["name", "time_verified"])
                && text("name", maximum: 512, characters: 80, pathSeparator: false)
                && boolean("time_verified")
        case "AI_JOINED", "AI_RETURNED_ON_DUTY":
            valid = ai(event.actor) && event.actor == event.subject
                && event.recipient == nil && exact([])
        case "INSTRUCTIONS_REPLACED":
            valid = event.actor == "administrator" && sameAITarget()
                && exact([
                    "binding_generation", "producer_cleared", "time_verified",
                ])
                && integer("binding_generation") && boolean("producer_cleared")
                && boolean("time_verified")
        case "AI_RETIRED":
            valid = event.actor == "administrator" && ai(event.subject)
                && event.recipient == nil
                && exact(["producer_cleared", "time_verified"])
                && boolean("producer_cleared") && boolean("time_verified")
        case "PRODUCER_CHANGED":
            valid = event.actor == "administrator" && ai(event.subject)
                && event.recipient == nil
                && exact(["generation", "participant"])
                && payload["participant"]?.stringValue == event.subject
                && integer("generation", upper: room.producerGeneration)
        case "QUALIFICATION_STARTED":
            valid = qualificationStart(
                actorIsValid: event.actor == "arc" || ai(event.actor)
            )
        case "QUALIFICATION_RETRIED":
            valid = qualificationStart(actorIsValid: event.actor == "administrator")
        case "QUALIFICATION_ANSWERED":
            valid = ai(event.actor) && event.actor == event.recipient
                && event.actor == event.subject && exact([])
        case "QUALIFICATION_FAILED":
            valid = event.actor == "arc" && sameAITarget()
                && exact(["reason"])
                && payload["reason"]?.stringValue == "The two-minute check expired."
        case "AI_QUALIFIED":
            valid = ai(event.actor) && event.actor == event.subject
                && event.recipient == nil && exact(["became_producer"])
                && boolean("became_producer")
        case "MESSAGE":
            valid = ai(event.actor) && ai(event.recipient) && event.subject == nil
                && exact(["text"])
                && text("text", maximum: 16_384, newlines: true)
        case "WORK_ASSIGNED":
            valid = ai(event.actor) && ai(event.recipient) && work(event.subject)
                && exact(["evidence_mode", "scope"])
                && text("scope", maximum: 4_096, newlines: true)
                && payload["evidence_mode"]?.stringValue.map({
                    ARCEvidenceMode(rawValue: $0) != nil
                }) == true
        case "WORK_UPDATED":
            guard let stateText = payload["state"]?.stringValue,
                  let state = ARCWorkState(rawValue: stateText), state != .open else {
                throw ARCError(.roomCorrupt, "An Activity payload is invalid.")
            }
            valid = ai(event.actor) && event.recipient == nil && work(event.subject)
                && exact(["evidence", "revision", "state"])
                && integer("revision") && evidence(state)
        case "WORK_REASSIGNED":
            valid = ai(event.actor) && ai(event.recipient) && work(event.subject)
                && exact(["owner", "reason", "revision"])
                && payload["owner"]?.stringValue == event.recipient
                && text("reason", maximum: 1_024, newlines: true)
                && integer("revision")
        default:
            valid = false
        }
        guard valid else {
            throw ARCError(.roomCorrupt, "An Activity payload is invalid.")
        }
    }

    private static func validateShape(_ value: Any) throws {
        let root = try object(value, allowed: ["format", "room", "participants", "work", "activity"],
                              required: ["format", "room", "participants", "work", "activity"], path: "room")
        let room = try object(root["room"], allowed: [
            "id", "name", "created_at", "updated_at", "revision", "next_sequence",
            "producer_id", "producer_generation", "producer_ever_selected",
            "last_clock_logical_us", "last_admin_operation",
        ], required: [
            "id", "name", "created_at", "updated_at", "revision", "next_sequence",
            "producer_generation", "producer_ever_selected", "last_clock_logical_us",
        ], path: "room.room")
        if let admin = room["last_admin_operation"] {
            _ = try object(admin, allowed: ["id", "request_digest"],
                           required: ["id", "request_digest"], path: "room.room.last_admin_operation")
        }
        for (index, item) in try array(root["participants"], path: "room.participants").enumerated() {
            let participant = try object(item, allowed: [
                "id", "name", "phase", "binding", "binding_generation", "qualification",
                "last_poll_logical_us", "next_operation", "last_operation",
            ], required: ["id", "name", "phase", "binding_generation", "next_operation"],
               path: "room.participants[\(index)]")
            if let qualification = participant["qualification"] {
                _ = try object(qualification, allowed: [
                    "challenge", "started_logical_us", "first_poll_logical_us", "answer_logical_us",
                ], required: ["challenge", "started_logical_us"],
                   path: "room.participants[\(index)].qualification")
            }
            if let operation = participant["last_operation"] {
                _ = try object(operation, allowed: [
                    "token", "request_digest", "event_sequences", "room_revision",
                    "participant_id", "work_id", "next_operation",
                ], required: [
                    "token", "request_digest", "event_sequences", "room_revision", "next_operation",
                ], path: "room.participants[\(index)].last_operation")
            }
        }
        for (index, item) in try array(root["work"], path: "room.work").enumerated() {
            _ = try object(item, allowed: [
                "id", "owner", "state", "scope", "evidence_mode", "evidence",
                "assigning_producer_generation", "revision", "created_at", "updated_at",
                "updated_logical_us",
            ], required: [
                "id", "owner", "state", "scope", "evidence_mode", "evidence",
                "assigning_producer_generation", "revision", "created_at", "updated_at",
                "updated_logical_us",
            ], path: "room.work[\(index)]")
        }
        for (index, item) in try array(root["activity"], path: "room.activity").enumerated() {
            _ = try object(item, allowed: [
                "sequence", "at", "logical_us", "kind", "actor", "recipient", "subject",
                "payload", "operation_id", "knowledge_sha256",
            ], required: [
                "sequence", "at", "logical_us", "kind", "actor", "payload",
                "operation_id", "knowledge_sha256",
            ], path: "room.activity[\(index)]")
        }
    }

    private static func object(
        _ value: Any?, allowed: Set<String>, required: Set<String>, path: String
    ) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any],
              Set(dictionary.keys).isSubset(of: allowed),
              required.isSubset(of: Set(dictionary.keys)) else {
            throw ARCError(.roomCorrupt, "\(path) has missing or unknown fields.")
        }
        return dictionary
    }

    private static func array(_ value: Any?, path: String) throws -> [Any] {
        guard let result = value as? [Any] else {
            throw ARCError(.roomCorrupt, "\(path) must be an array.")
        }
        return result
    }
}

enum ARCEvidence {
    static func validate(
        _ evidence: ARCJSONValue, state: ARCWorkState, mode: ARCEvidenceMode,
        corrupt: Bool = false
    ) throws {
        let error = ARCError(
            corrupt ? .roomCorrupt : .invalidArgument,
            corrupt ? "A work evidence record is invalid." : "The work evidence does not match its state."
        )
        try ARCJSONBounds.validate(evidence, errorCode: corrupt ? .roomCorrupt : .invalidArgument)
        guard let object = evidence.objectValue else { throw error }
        switch state {
        case .open:
            guard object.isEmpty else { throw error }
        case .active:
            guard Set(object.keys) == ["note"], validText(object["note"], maximum: 4_096)
            else { throw error }
        case .blocked:
            guard Set(object.keys) == ["blocker"], validText(object["blocker"], maximum: 4_096)
            else { throw error }
        case .complete where mode == .text:
            guard Set(object.keys) == ["references", "result"],
                  validText(object["result"], maximum: 16_384),
                  validTextArray(object["references"], range: 0...16) else { throw error }
        case .complete:
            guard Set(object.keys) == [
                "artifact", "defects", "inspected_at", "inspection", "result", "surfaces",
            ], validText(object["artifact"], maximum: 4_096),
               validText(object["inspection"], maximum: 4_096),
               object["inspected_at"]?.stringValue.map(ARCTime.isTimestamp) == true,
               validTextArray(object["surfaces"], range: 1...64),
               validTextArray(object["defects"], range: 0...32),
               let result = object["result"]?.stringValue,
               ["PASS", "PASS_WITH_DEFECTS"].contains(result) else { throw error }
            let defects = object["defects"]?.arrayCount ?? -1
            guard (result == "PASS" && defects == 0)
                    || (result == "PASS_WITH_DEFECTS" && defects > 0) else { throw error }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(evidence), bytes.count <= 60_000 else { throw error }
    }

    private static func validText(_ value: ARCJSONValue?, maximum: Int) -> Bool {
        guard let string = value?.stringValue else { return false }
        return ARCText.isCanonical(
            string, maximumBytes: maximum, allowNewlines: true
        )
    }

    private static func validTextArray(_ value: ARCJSONValue?, range: ClosedRange<Int>) -> Bool {
        guard case .array(let values) = value, range.contains(values.count) else { return false }
        return values.allSatisfy { validText($0, maximum: 4_096) }
    }
}

enum ARCJSONBounds {
    static func preflight(_ data: Data, errorCode: ARCErrorCode) throws {
        var stack: [UInt8] = []
        var inString = false
        var escaped = false
        var structuralItems = 0
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 0x5C { escaped = true }
                else if byte == 0x22 { inString = false }
                continue
            }
            if byte == 0x22 { inString = true; continue }
            if byte == 0x7B || byte == 0x5B {
                structuralItems += 1
                stack.append(byte)
                guard stack.count <= 32 else {
                    throw ARCError(errorCode, "ARC JSON is nested too deeply.")
                }
            } else if byte == 0x7D || byte == 0x5D {
                guard let opening = stack.popLast(),
                      (opening == 0x7B && byte == 0x7D)
                        || (opening == 0x5B && byte == 0x5D) else {
                    throw ARCError(errorCode, "ARC JSON nesting is invalid.")
                }
            } else if byte == 0x2C || byte == 0x3A {
                structuralItems += 1
            }
            guard structuralItems <= ARCConstants.maximumJSONStructuralItems else {
                throw ARCError(errorCode, "ARC JSON has too many values.")
            }
        }
        guard stack.isEmpty, !inString, !escaped else {
            throw ARCError(errorCode, "ARC JSON is incomplete.")
        }
    }

    static func validate(
        _ value: ARCJSONValue, errorCode: ARCErrorCode
    ) throws {
        var count = 0
        try validate(value, errorCode: errorCode, depth: 0, count: &count)
    }

    private static func validate(
        _ value: ARCJSONValue, errorCode: ARCErrorCode,
        depth: Int, count: inout Int
    ) throws {
        count += 1
        guard count <= 65_536 else {
            throw ARCError(errorCode, "ARC JSON has too many values.")
        }
        guard depth <= 32 else {
            throw ARCError(errorCode, "ARC JSON is nested too deeply.")
        }
        switch value {
        case .array(let values):
            guard values.count <= 4_096 else {
                throw ARCError(errorCode, "An ARC JSON array has too many items.")
            }
            for item in values {
                try validate(
                    item, errorCode: errorCode, depth: depth + 1, count: &count
                )
            }
        case .object(let values):
            guard values.count <= 4_096 else {
                throw ARCError(errorCode, "An ARC JSON object has too many fields.")
            }
            for (key, item) in values {
                guard ARCText.isCanonical(key, maximumBytes: 256) else {
                    throw ARCError(errorCode, "An ARC JSON field name is invalid.")
                }
                try validate(
                    item, errorCode: errorCode, depth: depth + 1, count: &count
                )
            }
        case .string(let text):
            guard text == text.precomposedStringWithCanonicalMapping,
                  text.utf8.count <= 65_536,
                  !text.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                        && $0 != "\n" && $0 != "\t"
                  }) else {
                throw ARCError(errorCode, "ARC JSON text is invalid.")
            }
        default: break
        }
    }
}

private extension ARCJSONValue {
    var arrayCount: Int? {
        guard case .array(let values) = self else { return nil }
        return values.count
    }
}
