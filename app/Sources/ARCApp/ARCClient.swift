import ARCCore
import Foundation

/// The one narrow app boundary around ARCCore. Production calls stay in this
/// process; tests replace this protocol with deterministic native values.
protocol ARCClientProtocol: Sendable {
    var rootURL: URL { get }

    func roomList(afterSafeID: String?) throws -> ARCRoomListPage
    func roomOpen(room: String) throws -> ARCRoomOpenResult
    func roomCreate(displayName: String, operationID: UUID) throws -> ARCRoomOpenResult
    func roomRename(
        room: String, displayName: String, operationID: UUID
    ) throws -> ARCRevisionResult
    func roomTick(room: String) throws -> ARCRoomTickResult
    func participantInvite(
        room: String, name: String, operationID: UUID
    ) throws -> ARCInstructionResult
    func participantReplaceInstructions(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCInstructionResult
    func participantTryAgain(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult
    func participantRetire(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult
    func producerSelect(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult
    func activityRead(room: String, beforeSequence: Int64?) throws -> ARCActivityPage
    func diagnose(room: String) throws -> ARCDiagnosticResult
    func roomDelete(room: String) throws -> ARCDeleteResult
}

extension ARCError {
    var requiresRoomListRefresh: Bool {
        [
            ARCErrorCode.notFound,
            .roomCorrupt,
            .roomIncompatible,
        ].contains(code)
    }
}

struct ARCClient: ARCClientProtocol, Sendable {
    #if DEBUG || ARC_VISUAL_TESTING
    private static let isolatedDevelopmentRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("arc-development-" + UUID().uuidString, isDirectory: true)
    #endif

    static var defaultRoot: URL {
        #if DEBUG || ARC_VISUAL_TESTING
        if let developmentRoot = ProcessInfo.processInfo.environment["ARC_DEVELOPMENT_ROOT"],
           developmentRoot.hasPrefix("/") {
            return URL(fileURLWithPath: developmentRoot, isDirectory: true)
                .standardized
        }
        return isolatedDevelopmentRoot
        #else
        return ARCStore.defaultRootURL
        #endif
    }

    let rootURL: URL
    private let store: ARCStore

    init(rootURL: URL = ARCClient.defaultRoot, clock: ARCClock = .system) {
        let root = rootURL.standardized
        self.rootURL = root
        self.store = ARCStore(rootURL: root, clock: clock)
    }

    init(rootURL: URL, clock: ARCClock = .system, knowledgeSHA256: String) {
        let root = rootURL.standardized
        self.rootURL = root
        self.store = ARCStore(
            rootURL: root,
            clock: clock,
            knowledgeSHA256: knowledgeSHA256
        )
    }

    func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        try store.roomList(afterSafeID: afterSafeID)
    }

    func roomOpen(room: String) throws -> ARCRoomOpenResult {
        try store.roomOpen(room: room)
    }

    func roomCreate(displayName: String, operationID: UUID) throws -> ARCRoomOpenResult {
        try store.roomCreate(displayName: displayName, operationID: operationID)
    }

    func roomRename(
        room: String, displayName: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try store.roomRename(
            room: room,
            displayName: displayName,
            operationID: operationID
        )
    }

    func roomTick(room: String) throws -> ARCRoomTickResult {
        try store.roomTick(room: room)
    }

    func participantInvite(
        room: String, name: String, operationID: UUID
    ) throws -> ARCInstructionResult {
        try store.participantInvite(room: room, name: name, operationID: operationID)
    }

    func participantReplaceInstructions(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCInstructionResult {
        try store.participantReplaceInstructions(
            room: room,
            participant: participant,
            operationID: operationID
        )
    }

    func participantTryAgain(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try store.participantTryAgain(
            room: room,
            participant: participant,
            operationID: operationID
        )
    }

    func participantRetire(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try store.participantRetire(
            room: room,
            participant: participant,
            operationID: operationID
        )
    }

    func producerSelect(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try store.producerSelect(
            room: room,
            participant: participant,
            operationID: operationID
        )
    }

    func activityRead(room: String, beforeSequence: Int64?) throws -> ARCActivityPage {
        try store.activityRead(room: room, beforeSequence: beforeSequence)
    }

    func diagnose(room: String) throws -> ARCDiagnosticResult {
        try store.diagnose(room: room)
    }

    func roomDelete(room: String) throws -> ARCDeleteResult {
        try store.roomDelete(room: room)
    }
}
