import ARCCore
import Darwin
import SwiftUI
import UniformTypeIdentifiers

struct TerseCostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var busy = false
    @State private var report: ARCJSONValue?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Terse Cost Comparison").font(.title2.bold())
            Text("Compare the same tasks with Terse and concise English. Ask your testing AIs for a comparison JSON file using Terse specification section 26. Include setup, context, repairs and failed attempts.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Comparison File…") { importing = true }.disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            if let report, let totals = report.objectValue?["totals"]?.objectValue {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(["reported_actual", "estimate"], id: \.self) { basis in
                            if totals[basis + ":terse"] != nil {
                                Text(basis == "reported_actual" ? "Reported actual usage" : "Estimates — not measured savings").font(.headline)
                                ForEach(["terse", "english"], id: \.self) { variant in
                                    if let row = totals[basis + ":" + variant]?.objectValue {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(variant == "terse" ? "Terse" : "Concise English").bold()
                                            Text("\(row["correct"]?.integerValue ?? 0) of \(row["runs"]?.integerValue ?? 0) tasks correct · \(row["calls"]?.integerValue ?? 0) calls")
                                            Text("Total: \(money(row["cost_microusd"])) · Per correct task: \(money(row["cost_per_correct_microusd"]))")
                                        }.textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        Text("These imported figures are not independently verified. A cheaper result is not a saving if correctness suffers. This comparison does not establish statistical significance or future savings.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No comparison loaded. ARC does not collect usage or connect to your AI accounts.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 650, height: 550)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .failure: failure = "The comparison file could not be opened."
            case .success(let url):
                busy = true; failure = nil; report = nil
                Task {
                    let loaded: Result<ARCJSONValue, Error> = await Task.detached {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return Result {
                            let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
                            guard descriptor >= 0 else { throw ARCError(.invalidArgument, "Choose a readable, regular JSON file, not a link.") }
                            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                            defer { try? handle.close() }
                            var status = stat()
                            guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG,
                                  status.st_size <= 131_072 else { throw ARCError(.invalidArgument, "Choose a regular comparison file of at most 131072 bytes.") }
                            let bytes = try handle.read(upToCount: 131_073) ?? Data()
                            return try ARCTerse.score(ARCTerse.decode(bytes))
                        }
                    }.value
                    switch loaded {
                    case .success(let value): report = value
                    case .failure(let error): failure = (error as? ARCError)?.message ?? "ARC could not read that comparison file."
                    }
                    busy = false
                }
            }
        }
    }
    private func money(_ value: ARCJSONValue?) -> String {
        guard let micros = value?.integerValue else { return "not available (no correct tasks)" }
        return String(format: "US$%.6f", Double(micros) / 1_000_000)
    }
}
