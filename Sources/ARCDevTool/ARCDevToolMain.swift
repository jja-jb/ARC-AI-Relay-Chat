import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct ARCDevTool {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("ARC developer tool: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw usage() }
        switch command {
        case "knowledge-build":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--source", "--output"],
                flags: ["--release-notes"]
            )
            let root = try requiredURL("--source", values)
            let output = try requiredURL("--output", values)
            let members = try KnowledgeContainer.sourceMembers(
                root: root,
                includeReleaseNotes: values["--release-notes"] == "true"
            )
            let container = try KnowledgeContainer.build(members)
            try KnowledgeContainer.writeNew(container, to: output)
            print("sha256=\(KnowledgeContainer.hex(KnowledgeContainer.sha256(container)))")
            print("bytes=\(container.count)")
        case "knowledge-validate":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--container"]
            )
            let container = try requiredURL("--container", values)
            let data = try KnowledgeContainer.readBounded(
                container,
                maximum: KnowledgeContainer.maxContainerBytes
            )
            let parsed = try KnowledgeContainer.parse(data)
            try KnowledgeContainer.validateWithC(data, digest: parsed.digest)
            print("sha256=\(KnowledgeContainer.hex(parsed.digest))")
            print("members=\(parsed.members.count)")
            print("omitted=\(parsed.omitted.count)")
        case "knowledge-deconstruct":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--container", "--destination"]
            )
            let container = try requiredURL("--container", values)
            let destination = try requiredURL("--destination", values)
            let data = try KnowledgeContainer.readBounded(
                container,
                maximum: KnowledgeContainer.maxContainerBytes
            )
            let parsed = try KnowledgeContainer.parse(data)
            try KnowledgeContainer.validateWithC(data, digest: parsed.digest)
            try KnowledgeContainer.deconstruct(parsed, destination: destination)
            print("sha256=\(KnowledgeContainer.hex(parsed.digest))")
            print("members=\(parsed.members.count)")
            print("omitted=\(parsed.omitted.count)")
        case "knowledge-reconstruct":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--source", "--output"]
            )
            let source = try requiredURL("--source", values)
            let output = try requiredURL("--output", values)
            let expected = try KnowledgeContainer.readTextTree(source)
            let container = try KnowledgeContainer.build(expected.members)
            guard KnowledgeContainer.sha256(container) == expected.digest else {
                throw DevToolError.message("text tree does not reconstruct its stated container")
            }
            try KnowledgeContainer.validateWithC(container, digest: expected.digest)
            try KnowledgeContainer.writeNew(container, to: output)
            print("sha256=\(KnowledgeContainer.hex(expected.digest))")
            print("bytes=\(container.count)")
        case "install-manifest":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--contents", "--version", "--knowledge-sha256", "--output"]
            )
            try ARCReleaseSupport.writeInstallManifest(
                contents: try requiredURL("--contents", values),
                version: try requiredString("--version", values),
                knowledgeSHA256: try requiredString("--knowledge-sha256", values),
                output: try requiredURL("--output", values)
            )
            print("install-manifest=ok")
        case "source-check":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--source"]
            )
            try ARCReleaseSupport.checkSource(try requiredURL("--source", values))
            print("source=ok")
        case "app-check":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--app", "--version"],
                flags: ["--release"]
            )
            try ARCReleaseSupport.checkApp(
                try requiredURL("--app", values),
                version: try requiredString("--version", values),
                release: values["--release"] == "true"
            )
            print("app=ok")
        case "candidate-manifest":
            let values = try options(
                Array(arguments.dropFirst()),
                values: [
                    "--version", "--tag", "--revision", "--dmg", "--literature",
                    "--source",
                    "--knowledge-sha256", "--output",
                ]
            )
            try ARCReleaseSupport.writeCandidateManifest(
                version: try requiredString("--version", values),
                tag: try requiredString("--tag", values),
                revision: try requiredString("--revision", values),
                dmg: try requiredURL("--dmg", values),
                literature: try requiredURL("--literature", values),
                source: try requiredURL("--source", values),
                knowledgeSHA256: try requiredString("--knowledge-sha256", values),
                output: try requiredURL("--output", values)
            )
            print("candidate-manifest=ok")
        case "dvt-check":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--report", "--candidate-manifest"]
            )
            try ARCReleaseSupport.checkDVT(
                report: try requiredURL("--report", values),
                candidateManifest: try requiredURL("--candidate-manifest", values)
            )
            print("dvt=ok")
        case "release-metadata":
            let values = try options(
                Array(arguments.dropFirst()),
                values: [
                    "--candidate-manifest", "--dvt-report", "--signing-identity",
                    "--app-notarization-id", "--dmg-notarization-id", "--output",
                ]
            )
            try ARCReleaseSupport.writeReleaseMetadata(
                candidateManifest: try requiredURL("--candidate-manifest", values),
                dvtReport: try requiredURL("--dvt-report", values),
                signingIdentity: try requiredString("--signing-identity", values),
                appNotarizationID: try requiredString("--app-notarization-id", values),
                dmgNotarizationID: try requiredString("--dmg-notarization-id", values),
                output: try requiredURL("--output", values)
            )
            print("release-metadata=ok")
        case "checksums":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--directory", "--version", "--output"]
            )
            try ARCReleaseSupport.writeChecksums(
                directory: try requiredURL("--directory", values),
                version: try requiredString("--version", values),
                output: try requiredURL("--output", values)
            )
            print("checksums=ok")
        case "release-check":
            let values = try options(
                Array(arguments.dropFirst()),
                values: ["--directory", "--version"]
            )
            try ARCReleaseSupport.checkRelease(
                directory: try requiredURL("--directory", values),
                version: try requiredString("--version", values)
            )
            print("release=ok")
        default:
            throw usage()
        }
    }

    static func options(
        _ arguments: [String],
        values: Set<String>,
        flags: Set<String> = []
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let name = arguments[index]
            guard (values.contains(name) || flags.contains(name)), result[name] == nil else {
                throw usage()
            }
            if flags.contains(name) {
                result[name] = "true"
                index += 1
            } else {
                guard index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else { throw usage() }
                result[name] = arguments[index + 1]
                index += 2
            }
        }
        return result
    }

    static func requiredURL(_ name: String, _ options: [String: String]) throws -> URL {
        guard let value = options[name], value != "true", value.hasPrefix("/") else {
            throw usage()
        }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    static func requiredString(_ name: String, _ options: [String: String]) throws -> String {
        guard let value = options[name], value != "true", !value.isEmpty else {
            throw usage()
        }
        return value
    }

    static func usage() -> DevToolError {
        .message(
            "usage: arc-dev knowledge-build --source ROOT --output FILE [--release-notes]\n" +
            "       arc-dev knowledge-validate --container FILE\n" +
            "       arc-dev knowledge-deconstruct --container FILE --destination DIRECTORY\n" +
            "       arc-dev knowledge-reconstruct --source DIRECTORY --output FILE\n" +
            "       arc-dev install-manifest --contents DIRECTORY --version VERSION " +
                "--knowledge-sha256 HEX --output FILE\n" +
            "       arc-dev source-check --source ROOT\n" +
            "       arc-dev app-check --app ARC.app --version VERSION [--release]\n" +
            "       arc-dev candidate-manifest --version VERSION --tag TAG " +
                "--revision COMMIT --dmg FILE --literature FILE --source FILE " +
                "--knowledge-sha256 HEX " +
                "--output FILE\n" +
            "       arc-dev dvt-check --report FILE --candidate-manifest FILE\n" +
            "       arc-dev release-metadata --candidate-manifest FILE --dvt-report FILE " +
                "--signing-identity TEXT --app-notarization-id UUID " +
                "--dmg-notarization-id UUID --output FILE\n" +
            "       arc-dev checksums --directory DIRECTORY --version VERSION --output FILE\n" +
            "       arc-dev release-check --directory DIRECTORY --version VERSION"
        )
    }
}
