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
                guard (0...12).contains(id) else {
                    throw ARCError(.notFound, "ARC has no specification with that ID.")
                }
                let knowledge = try ARCKnowledgeFile.openDefault(rootURL: root)
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
                optional: ["--after"]
            )
            let after: Int64
            if let rawAfter = options["--after"] {
                guard let value = Int64(rawAfter), value >= 0,
                      String(value) == rawAfter else {
                    throw ARCError(.invalidArgument, "--after must be a nonnegative integer.")
                }
                after = value
            } else { after = 0 }
            let result = try ARCStore(rootURL: root).poll(
                room: options["--room"]!,
                participant: options["--id"]!,
                binding: options["--binding"]!,
                after: after
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
        return command == "poll" || command == "act"
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
            "Usage: arc version | help | spec list | spec read ID | guide | poll | act | doctor"
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
