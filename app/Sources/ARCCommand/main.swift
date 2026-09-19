import ARCCore
import Darwin
import Foundation

@main
struct ARCCommand {
    static func main() {
        // CommandLine.arguments replaces malformed UTF-8 with U+FFFD.  Keep
        // that lossy view only to decide whether a safe failure is machine
        // framed; parse the actual argv bytes below.
        let lossyRaw = Array(CommandLine.arguments.dropFirst())
        let machine = machineCommand(lossyRaw)
        do {
            try run(strictCommandLineArguments())
        } catch let error as ARCError {
            if machine { writeFailure(error) }
            else { writeText("\(error.message)\n") }
            exit(error.exitStatus)
        } catch {
            let safe = ARCError(.ioFailure, "ARC could not complete the local operation.")
            if machine { writeFailure(safe) }
            else { writeText("\(safe.message)\n") }
            exit(safe.exitStatus)
        }
    }

    private static func strictCommandLineArguments() throws -> [String] {
        let count = Int(CommandLine.argc)
        return try (1..<count).map { index in
            guard let pointer = CommandLine.unsafeArgv[index],
                  let argument = String(validatingCString: pointer) else {
                throw ARCError(.invalidArgument, "Command-line arguments must be valid UTF-8.")
            }
            return argument
        }
    }

    private static func run(_ raw: [String]) throws {
        var arguments = raw
        var root = ARCStore.defaultRootURL
        var hasExplicitRoot = false
        if arguments.first == "--root" {
            guard arguments.count >= 3 else { throw usage() }
            let path = arguments[1]
            guard path.hasPrefix("/") else {
                throw ARCError(.invalidArgument, "--root requires an absolute local path.")
            }
            root = URL(fileURLWithPath: path, isDirectory: true).standardized
            hasExplicitRoot = true
            arguments.removeFirst(2)
        }
        guard let command = arguments.first else { throw usage() }
        arguments.removeFirst()

        switch command {
        case "version":
            guard arguments.isEmpty, !hasExplicitRoot else { throw usage() }
            writeText("ARC \(ARCConstants.version)\n")

        case "help":
            guard !hasExplicitRoot, arguments.isEmpty else { throw usage() }
            let knowledge = try ARCKnowledgeFile.openDefault(rootURL: root)
            guard let text = try knowledge.text(.help) else {
                throw ARCError(.knowledgeUnavailable, "ARC's help is missing.")
            }
            writeText(withFinalLF(text))

        case "spec":
            guard !hasExplicitRoot, let subcommand = arguments.first else { throw usage() }
            if subcommand == "list", arguments.count == 1 {
                writeText(specificationList)
            } else if subcommand == "read", arguments.count == 2,
                      let id = Int(arguments[1]),
                      arguments[1] == String(format: "%03d", id) {
                guard (0...14).contains(id) else {
                    throw ARCError(.notFound, "ARC has no specification with that ID.")
                }
                let knowledge = try ARCKnowledgeFile.openDefault(rootURL: root)
                if id == 14 {
                    writeText(withFinalLF(try QuinbyStore.specification(rootURL: root)))
                    return
                }
                if id == 13 {
                    writeText(withFinalLF(try ARCCommunication.specificationText(
                        installationURL: knowledge.containerURL.deletingLastPathComponent())))
                    return
                }
                guard let text = try knowledge.text(.specification(id)) else {
                    throw ARCError(.notFound, "ARC has no specification with that ID.")
                }
                writeText(withFinalLF(text))
            } else { throw usage() }

        case "guide":
            let options = try parseOptions(arguments, required: ["--room", "--id", "--binding"])
            let store = ARCStore(rootURL: root)
            let room = options["--room"]!
            let id = options["--id"]!
            let binding = options["--binding"]!
            let context = try store.guide(room: room, participant: id, binding: binding)
            let knowledge = try ARCKnowledgeFile.openDefault(rootURL: root)
            guard let guide = try knowledge.text(.aiGuide) else {
                throw ARCError(.knowledgeUnavailable, "ARC's AI guide is missing.")
            }
            writeText(try guideText(
                guide, root: root, room: context.room,
                participant: context.participant, binding: binding
            ))

        case "poll":
            let options = try parseOptions(
                arguments,
                required: ["--room", "--id", "--binding"],
                optional: ["--after", "--wait"]
            )
            let after: Int64
            if let rawAfter = options["--after"] {
                guard let value = Int64(rawAfter), value >= 0,
                      String(value) == rawAfter else {
                    throw ARCError(.invalidArgument, "--after must be a nonnegative integer.")
                }
                after = value
            } else { after = 0 }
            var wait = 0
            if let rawWait = options["--wait"] {
                guard let value = Int(rawWait), value >= 0, value <= 3_600, String(value) == rawWait else {
                    throw ARCError(.invalidArgument, "--wait must be a whole number of seconds up to 3600.")
                }
                wait = value
            }
            let result = try ARCStore(rootURL: root).poll(
                room: options["--room"]!,
                participant: options["--id"]!,
                binding: options["--binding"]!,
                after: after,
                wait: wait
            )
            writeSuccess(result)

        case "act":
            let options = try parseOptions(
                arguments,
                required: ["--room", "--id", "--binding", "--operation", "--request"]
            )
            let result = try ARCStore(rootURL: root).act(
                room: options["--room"]!,
                participant: options["--id"]!,
                binding: options["--binding"]!,
                operation: options["--operation"]!,
                requestJSON: Data(options["--request"]!.utf8)
            )
            writeSuccess(result)

        case "quinby":
            guard let subcommand = arguments.first else { throw usage() }
            let rest = Array(arguments.dropFirst())
            let required: Set<String> = ["--incarnation", "--id", "--binding"]
            var options: [String: String] = [:]
            let store = QuinbyStore(rootURL: root)
            func sequence(_ key: String) throws -> Int64? {
                guard let raw = options[key] else { return nil }
                guard let value = Int64(raw), value >= 0, String(value) == raw else {
                    throw ARCError(.invalidArgument, "\(key) must be a nonnegative integer.")
                }
                return value
            }
            switch subcommand {
            case "guide":
                options = try parseOptions(rest, required: required)
                writeSuccess(try store.guide(incarnation: options["--incarnation"]!, participant: options["--id"]!, binding: options["--binding"]!))
            case "poll":
                options = try parseOptions(rest, required: required, optional: ["--after"])
                writeSuccess(try store.poll(incarnation: options["--incarnation"]!, participant: options["--id"]!,
                    binding: options["--binding"]!, after: try sequence("--after")))
            case "wait":
                options = try parseOptions(rest, required: required.union(["--after"]), optional: ["--timeout"])
                var timeout = 300
                if let raw = options["--timeout"] {
                    guard let value = Int(raw), value >= 1, value <= 3_600, String(value) == raw else {
                        throw ARCError(.invalidArgument, "--timeout must be a whole number of seconds from 1 to 3600.")
                    }
                    timeout = value
                }
                writeSuccess(try store.wait(incarnation: options["--incarnation"]!, participant: options["--id"]!,
                    binding: options["--binding"]!, after: try sequence("--after")!, timeout: timeout))
            case "read":
                options = try parseOptions(rest, required: required, optional: ["--before"])
                var before: Int64?
                if let raw = options["--before"] {
                    guard let value = Int64(raw), value >= 0, String(value) == raw else { throw usage() }
                    before = value
                }
                writeSuccess(try store.read(incarnation: options["--incarnation"]!, participant: options["--id"]!, binding: options["--binding"]!, before: before))
            case "act":
                options = try parseOptions(rest, required: required.union(["--operation", "--request"]))
                writeSuccess(try store.act(incarnation: options["--incarnation"]!, participant: options["--id"]!, binding: options["--binding"]!, operation: options["--operation"]!, json: Data(options["--request"]!.utf8)))
            default: throw usage()
            }

        case "terse":
            guard let subcommand = arguments.first else { throw usage() }
            let rest = Array(arguments.dropFirst())
            switch subcommand {
            case "validate":
                guard !hasExplicitRoot else { throw usage() }
                let options = try parseOptions(rest, required: ["--text"])
                try ARCTerse.validateText(options["--text"]!)
                writeSuccess(ARCJSONValue.object(["syntax_valid": .boolean(true),
                    "context_checks": .string("not performed: peer compatibility, references, variables, truth and authority require separate checks")]))
            case "build", "score":
                guard !hasExplicitRoot else { throw usage() }
                let options = try parseOptions(rest, required: ["--request"])
                let value = try ARCTerse.decode(Data(options["--request"]!.utf8))
                if subcommand == "build" { writeSuccess(ARCJSONValue.object(["text": .string(try ARCTerse.build(value))])) }
                else { writeSuccess(try ARCTerse.score(value)) }
            case "read", "status":
                let required: Set<String> = subcommand == "read" ? ["--room", "--id", "--binding", "--sequence"] : ["--room", "--id", "--binding"]
                let options = try parseOptions(rest, required: required)
                var sequence: Int64?
                if let raw = options["--sequence"] {
                    guard let n = Int64(raw), n > 0, String(n) == raw else { throw usage() }
                    sequence = n
                }
                writeSuccess(try ARCStore(rootURL: root).terseRead(room: options["--room"]!, participant: options["--id"]!, binding: options["--binding"]!, sequence: sequence))
            default: throw usage()
            }

        case "doctor":
            var doctorArguments = arguments
            let jsonIndex = doctorArguments.firstIndex(of: "--json")
            let json = jsonIndex != nil
            if let jsonIndex { doctorArguments.remove(at: jsonIndex) }
            let options = try parseOptions(doctorArguments, required: ["--room"])
            let result = try ARCStore(rootURL: root).diagnose(room: options["--room"]!)
            if json { writeSuccess(result) }
            else if result.valid { writeText("Room file is OK.\n") }
            else if let failure = result.failure {
                writeText("\(failure.message)\n\(failure.nextAction)\n")
            }
            if !result.valid { exit(2) }

        default:
            throw usage()
        }
    }

    private static func parseOptions(
        _ arguments: [String],
        required: Set<String>,
        optional: Set<String> = []
    ) throws -> [String: String] {
        let allowed = required.union(optional)
        guard arguments.count.isMultiple(of: 2) else { throw usage() }
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard allowed.contains(key), result[key] == nil else { throw usage() }
            result[key] = arguments[index + 1]
            index += 2
        }
        guard required.isSubset(of: Set(result.keys)) else { throw usage() }
        return result
    }

    private static func guideText(
        _ generic: String,
        root: URL,
        room: ARCRoomView,
        participant: ARCParticipantView,
        binding: String
    ) throws -> String {
        guard let executable = Bundle.main.executableURL?.standardized.path,
              executable.hasPrefix("/") else {
            throw ARCError(.ioFailure, "ARC cannot identify its installed command.")
        }
        let poll = [
            executable, "--root", root.path, "poll", "--room", room.id,
            "--id", participant.id, "--binding", binding, "--after", "0",
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let pollJSON = String(decoding: try encoder.encode(poll), as: UTF8.self)
        let waitJSON = String(decoding: try encoder.encode(poll + ["--wait", "300"]), as: UTF8.self)
        let helpJSON = String(decoding: try encoder.encode([executable, "help"]), as: UTF8.self)
        let specListJSON = String(
            decoding: try encoder.encode([executable, "spec", "list"]), as: UTF8.self
        )
        let specificationPath = root
            .appendingPathComponent("current/specifications", isDirectory: true).path
        let communication = ARCCommunication.snapshot(rootURL: root)
        return """
        ARC AI guide
        AI name: \(participant.name)
        Room: \(room.name)
        Room ID: \(room.id)
        Participant ID: \(participant.id)
        Current phase: \(participant.phase.rawValue)
        Installed plain-text specifications: \(specificationPath)

        Full local Terse specification: \(ARCCommunication.specificationURL(rootURL: root).path)
        Messages to operator: \(communication.operatorLanguage.displayName)
        Terse file status: \(communication.status)
        Verified Terse SHA-256: \(communication.specificationSha256 ?? "unavailable — pause ARC participation")
        \(communication.notice)

        Use direct argument arrays, never a shell command. Your poll arguments are:
        \(pollJSON)

        Your waiting poll arguments (block up to five minutes for a change, renewing duty meanwhile, then poll) are:
        \(waitJSON)
        After the first poll, replace the 0 after --after with the next_after of the previous result. Run the waiting form from a script or host tool and wake your model only when the result's changed is true.

        Your exact offline help arguments are:
        \(helpJSON)

        Your exact specification-list arguments are:
        \(specListJSON)

        \(generic.trimmingCharacters(in: .whitespacesAndNewlines))
        """ + "\n"
    }

    private static func machineCommand(_ raw: [String]) -> Bool {
        var values = raw
        if values.first == "--root", values.count >= 3 { values.removeFirst(2) }
        guard let command = values.first else { return false }
        return command == "poll" || command == "act" || command == "terse" || command == "quinby"
            || (command == "doctor" && values.contains("--json"))
    }

    private static func writeSuccess<T: Encodable>(_ result: T) {
        writeJSON(ARCSuccessEnvelope(ok: true, result: result))
    }

    private static func writeFailure(_ error: ARCError) {
        writeJSON(ARCFailureEnvelope(
            error: ARCFailureBody(
                code: error.code, message: error.message, retryable: error.retryable
            ),
            ok: false
        ))
    }

    private static func writeJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(value) else { exit(4) }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static func writeText(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }

    private static func withFinalLF(_ value: String) -> String {
        value.hasSuffix("\n") ? value : value + "\n"
    }

    private static func usage() -> ARCError {
        ARCError(
            .invalidArgument,
            "Usage: arc version | help | spec list | spec read ID | guide | poll | act | terse | quinby | doctor"
        )
    }

    private static let specificationList = """
    000  Shared constitution
    001  How to read the specifications
    002  Rooms, Administrator, AIs, and Producer
    003  Durable room file
    004  Messages and work
    005  Qualification, duty, and polling
    006  macOS application
    007  Command interface
    008  Security and privacy
    009  Installation and release
    010  Verification
    011  Durable record
    012  AI knowledge container
    013  Terse v2.1 (full language specification)
    014  Quinby's Corner
    """ + "\n"
}

private struct ARCSuccessEnvelope<T: Encodable>: Encodable {
    let ok: Bool
    let result: T
}

private struct ARCFailureEnvelope: Encodable {
    let error: ARCFailureBody
    let ok: Bool
}

private struct ARCFailureBody: Encodable {
    let code: ARCErrorCode
    let message: String
    let retryable: Bool
}
