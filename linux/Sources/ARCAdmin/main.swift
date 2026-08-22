import ARCCore
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The local Administrator interface used by ARC for Linux. Its JSON-only
/// contract gives the GTK frontend a narrow, testable boundary to ARCCore.
@main
struct ARCAdmin {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch let error as ARCError {
            write(ARCFailure(error: error))
            exit(error.exitStatus)
        } catch {
            let safe = ARCError(.ioFailure, "ARC could not complete the local administration request.")
            write(ARCFailure(error: safe))
            exit(safe.exitStatus)
        }
    }

    private static func run(_ raw: [String]) throws {
        var arguments = raw
        var root = ARCStore.defaultRootURL
        if arguments.first == "--root" {
            guard arguments.count >= 3, arguments[1].hasPrefix("/") else { throw usage() }
            root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardized
            arguments.removeFirst(2)
        }
        guard let domain = arguments.first else { throw usage() }
        arguments.removeFirst()
        let store = ARCStore(rootURL: root)

        switch (domain, arguments.first) {
        case ("room", "list"):
            guard arguments.count == 1 else { throw usage() }
            write(ARCSuccess(result: try store.roomList()))
        case ("room", "create"):
            let options = try options(Array(arguments.dropFirst()), ["--name"])
            write(ARCSuccess(result: try store.roomCreate(
                displayName: options["--name"]!, operationID: UUID()
            )))
        case ("room", "open"):
            let options = try options(Array(arguments.dropFirst()), ["--room"])
            write(ARCSuccess(result: try store.roomOpen(room: options["--room"]!)))
        case ("room", "rename"):
            let options = try options(Array(arguments.dropFirst()), ["--room", "--name"])
            write(ARCSuccess(result: try store.roomRename(
                room: options["--room"]!, displayName: options["--name"]!, operationID: UUID()
            )))
        case ("room", "delete"):
            let options = try options(Array(arguments.dropFirst()), ["--room"])
            write(ARCSuccess(result: try store.roomDelete(room: options["--room"]!)))
        case ("room", "tick"):
            let options = try options(Array(arguments.dropFirst()), ["--room"])
            write(ARCSuccess(result: try store.roomTick(room: options["--room"]!)))
        case ("activity", "read"):
            let options = try options(Array(arguments.dropFirst()), ["--room"])
            write(ARCSuccess(result: try store.activityRead(room: options["--room"]!)))
        case ("participant", "invite"):
            let options = try options(Array(arguments.dropFirst()), ["--room", "--name"])
            let result = try store.participantInvite(
                room: options["--room"]!, name: options["--name"]!, operationID: UUID()
            )
            write(ARCSuccess(result: ARCInstructionOutput(result)))
        case ("participant", "replace"):
            let options = try options(Array(arguments.dropFirst()), ["--room", "--id"])
            let result = try store.participantReplaceInstructions(
                room: options["--room"]!, participant: options["--id"]!, operationID: UUID()
            )
            write(ARCSuccess(result: ARCInstructionOutput(result)))
        case ("participant", "retry"):
            let options = try options(Array(arguments.dropFirst()), ["--room", "--id"])
            write(ARCSuccess(result: try store.participantTryAgain(
                room: options["--room"]!, participant: options["--id"]!, operationID: UUID()
            )))
        case ("participant", "retire"):
            let options = try options(Array(arguments.dropFirst()), ["--room", "--id"])
            write(ARCSuccess(result: try store.participantRetire(
                room: options["--room"]!, participant: options["--id"]!, operationID: UUID()
            )))
        case ("producer", "select"):
            let options = try options(Array(arguments.dropFirst()), ["--room", "--id"])
            write(ARCSuccess(result: try store.producerSelect(
                room: options["--room"]!, participant: options["--id"]!, operationID: UUID()
            )))
        default:
            throw usage()
        }
    }

    private static func options(_ arguments: [String], _ required: Set<String>) throws -> [String: String] {
        guard arguments.count == required.count * 2 else { throw usage() }
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard required.contains(key), values[key] == nil else { throw usage() }
            values[key] = arguments[index + 1]
            index += 2
        }
        return values
    }

    private static func write<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(value) else { exit(4) }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static func usage() -> ARCError {
        ARCError(.invalidArgument, "Usage: arc-admin [--root PATH] room|participant|producer|activity COMMAND")
    }
}

private struct ARCSuccess<T: Encodable>: Encodable {
    let ok = true
    let result: T
}

private struct ARCFailure: Encodable {
    struct Body: Encodable { let code: ARCErrorCode; let message: String; let retryable: Bool }
    let ok = false
    let error: Body
    init(error: ARCError) { self.error = Body(code: error.code, message: error.message, retryable: error.retryable) }
}

private struct ARCInstructionOutput: Encodable {
    let participant: ARCParticipantView
    let binding: String
    let bindingGeneration: Int64
    init(_ value: ARCInstructionResult) {
        participant = value.participant
        binding = value.instructions.bindingReference
        bindingGeneration = value.instructions.bindingGeneration
    }
}
