import Darwin
import Foundation

enum ARCFileCollision: Error {
    case destinationExists
}

struct ARCRoomFileInspection: Sendable {
    let document: ARCRoomDocument
    let byteCount: Int
}

struct ARCFileStore: Sendable {
    let rootURL: URL
    let roomsURL: URL
    init(rootURL: URL) throws {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else {
            throw ARCError(.invalidArgument, "ARC's root must be an absolute local path.")
        }
        // `standardizedFileURL` resolves existing symlinks but leaves a missing
        // path lexical.  That makes the same root change identity after ARC
        // creates it (notably /private/tmp becoming /tmp).  Keep normalization
        // lexical; the descriptor path below performs the actual no-link check.
        self.rootURL = rootURL.standardized
        self.roomsURL = rootURL.standardized
            .appendingPathComponent("rooms", isDirectory: true)
        try rejectLinkedPath(self.rootURL, allowMissingTail: true)
        try ensureDirectory(self.rootURL)
        try rejectLinkedPath(self.rootURL, allowMissingTail: false)
        try ensureDirectory(self.roomsURL)
        try rejectLinkedPath(self.roomsURL, allowMissingTail: false)
    }

    func roomURL(_ id: String) throws -> URL {
        guard ARCText.isSafeID(id, prefix: "room-") else {
            throw ARCError(.invalidArgument, "The Room ID is invalid.")
        }
        return roomsURL.appendingPathComponent("\(id).arcroom", isDirectory: false)
    }

    func roomIDs() throws -> [String] {
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: roomsURL.path) }
        catch { throw ARCError(.ioFailure, "ARC could not list its rooms.") }
        return names.compactMap { name in
            guard name.hasSuffix(".arcroom") else { return nil }
            let id = String(name.dropLast(".arcroom".count))
            return ARCText.isSafeID(id, prefix: "room-") ? id : nil
        }.sorted()
    }

    func create<T>(
        _ document: ARCRoomDocument,
        body: (ARCRoomDocument) throws -> T
    ) throws -> T {
        let url = try roomURL(document.room.id)
        return try withLock(for: url) {
            guard lstatExists(url.path) == false else {
                throw ARCFileCollision.destinationExists
            }
            var value = document
            let data = try dataForCommit(&value)
            try atomicWrite(data, to: url, exclusive: true)
            return try body(value)
        }
    }

    func read<T>(_ id: String, body: (ARCRoomDocument) throws -> T) throws -> T {
        let url = try roomURL(id)
        try requireExistingRoom(at: url)
        return try withLock(for: url) {
            try body(readDocument(at: url, expectedID: id))
        }
    }

    func inspect(_ id: String) throws -> ARCRoomFileInspection {
        let url = try roomURL(id)
        try requireExistingRoom(at: url)
        return try withLock(for: url) {
            try readSnapshot(at: url, expectedID: id)
        }
    }

    func update<T>(
        _ id: String,
        body: (inout ARCRoomDocument) throws -> (value: T, commit: Bool)
    ) throws -> T {
        let url = try roomURL(id)
        try requireExistingRoom(at: url)
        return try withLock(for: url) {
            var document = try readDocument(at: url, expectedID: id)
            let result = try body(&document)
            if result.commit {
                let data = try dataForCommit(&document)
                try atomicWrite(data, to: url, exclusive: false)
            }
            return result.value
        }
    }

    func delete(_ id: String) throws {
        let url = try roomURL(id)
        try requireExistingRoom(at: url)
        try withLock(for: url) {
            let document = try readDocument(at: url, expectedID: id)
            guard document.participants.allSatisfy({ $0.phase == .retired }) else {
                throw ARCError(
                    .wrongState,
                    "Retire every AI participant before permanently deleting this room."
                )
            }
            try deleteAdmittedRegularFile(url)
        }
        try removeLockIfUnused(for: url)
    }

    private func deleteAdmittedRegularFile(_ url: URL) throws {
        let sourceDirectory = try openRoomsDirectory()
        defer { Darwin.close(sourceDirectory) }
        let source = openat(
            sourceDirectory, url.lastPathComponent,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard source >= 0 else {
            if errno == ENOENT { throw ARCError(.notFound, "ARC could not find that room.") }
            throw ARCError(.ioFailure, "ARC refused an unsafe room file.")
        }
        defer { Darwin.close(source) }

        var admitted = stat()
        var pathState = stat()
        guard fstat(source, &admitted) == 0,
              (admitted.st_mode & S_IFMT) == S_IFREG,
              admitted.st_nlink == 1,
              fstatat(
                  sourceDirectory, url.lastPathComponent, &pathState,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              admitted.st_dev == pathState.st_dev,
              admitted.st_ino == pathState.st_ino else {
            throw ARCError(.ioFailure, "ARC refused an unsafe room file.")
        }

        let originalName = url.lastPathComponent
        var current = stat()
        guard fstatat(
            sourceDirectory, originalName, &current, AT_SYMLINK_NOFOLLOW
        ) == 0,
              (current.st_mode & S_IFMT) == S_IFREG,
              current.st_nlink == 1,
              current.st_dev == admitted.st_dev,
              current.st_ino == admitted.st_ino else {
            throw ARCError(.ioFailure, "The room changed before ARC could delete it.")
        }
        guard unlinkat(sourceDirectory, originalName, 0) == 0 else {
            throw ARCError(.ioFailure, "ARC could not permanently delete that room.")
        }
        guard fsync(sourceDirectory) == 0 else {
            throw ARCError(.ioFailure, "ARC could not synchronize permanent deletion.")
        }
    }

    private func removeLockIfUnused(for roomURL: URL) throws {
        let directory = try openRoomsDirectory()
        defer { Darwin.close(directory) }
        let lockName = roomURL.appendingPathExtension("lock").lastPathComponent
        if unlinkat(directory, lockName, 0) != 0 && errno != ENOENT {
            throw ARCError(.ioFailure, "ARC deleted the room but could not remove its lock file.")
        }
        guard fsync(directory) == 0 else {
            throw ARCError(.ioFailure, "ARC could not synchronize permanent deletion.")
        }
    }

    private func readDocument(at url: URL, expectedID: String) throws -> ARCRoomDocument {
        try readSnapshot(at: url, expectedID: expectedID).document
    }

    /// A command for a missing room must not create that room's adjacent lock.
    /// The later locked read still guards against a concurrent removal.
    private func requireExistingRoom(at url: URL) throws {
        guard lstatExists(url.path) else {
            throw ARCError(.notFound, "ARC could not find that room.")
        }
    }

    private func readSnapshot(
        at url: URL, expectedID: String
    ) throws -> ARCRoomFileInspection {
        let directory = try openRoomsDirectory()
        defer { Darwin.close(directory) }
        let descriptor = openat(
            directory, url.lastPathComponent,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ARCError(.notFound, "ARC could not find that room.") }
            throw ARCError(.ioFailure, "ARC could not open that room.")
        }
        defer { Darwin.close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size > 0,
              info.st_size <= ARCConstants.maximumRoomBytes else {
            throw ARCError(.roomCorrupt, "The room is not one bounded regular file.")
        }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ARCError(.ioFailure, "ARC could not read that room.")
            }
            data.append(buffer, count: count)
            guard data.count <= ARCConstants.maximumRoomBytes else {
                throw ARCError(.roomCorrupt, "The room file is larger than 8 MiB.")
            }
        }
        var after = stat()
        var pathState = stat()
        guard fstat(descriptor, &after) == 0,
              fstatat(directory, url.lastPathComponent, &pathState, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_dev == after.st_dev, info.st_ino == after.st_ino,
              info.st_size == after.st_size,
              info.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              info.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              info.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              info.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_dev == pathState.st_dev, after.st_ino == pathState.st_ino,
              data.count == Int(after.st_size) else {
            throw ARCError(.ioFailure, "The room changed while ARC was reading it.")
        }
        return ARCRoomFileInspection(
            document: try ARCRoomCodec.decode(data, expectedID: expectedID),
            byteCount: data.count
        )
    }

    private func dataForCommit(_ document: inout ARCRoomDocument) throws -> Data {
        try ARCRoomCodec.encode(document)
    }

    private func withLock<T>(for roomURL: URL, body: () throws -> T) throws -> T {
        let lockURL = roomURL.appendingPathExtension("lock")
        let directory = try openRoomsDirectory()
        defer { Darwin.close(directory) }
        let descriptor = openat(
            directory, lockURL.lastPathComponent,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw ARCError(.ioFailure, "ARC could not open the room lock.")
        }
        defer { Darwin.close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw ARCError(.ioFailure, "ARC refused an unsafe room lock.")
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else {
                throw ARCError(.ioFailure, "ARC could not lock that room.")
            }
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw ARCError(.busy, "That ARC room is busy. Try again.")
            }
            usleep(20_000)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func atomicWrite(
        _ data: Data, to destination: URL, exclusive: Bool
    ) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).tmp"
        )
        let directory = try openRoomsDirectory()
        defer { Darwin.close(directory) }
        let descriptor = openat(
            directory, temporary.lastPathComponent,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw ARCError(.ioFailure, "ARC could not create its atomic room update.")
        }
        var shouldRemove = true
        defer {
            Darwin.close(descriptor)
            if shouldRemove { _ = unlinkat(directory, temporary.lastPathComponent, 0) }
        }

        do {
            try data.withUnsafeBytes { raw in
                guard var pointer = raw.baseAddress else { return }
                var remaining = raw.count
                while remaining > 0 {
                    let count = Darwin.write(descriptor, pointer, remaining)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw ARCError(.ioFailure, "ARC could not write its room update.")
                    }
                    remaining -= count
                    pointer = pointer.advanced(by: count)
                }
            }
            guard fsync(descriptor) == 0 else {
                throw ARCError(.ioFailure, "ARC could not synchronize its room update.")
            }
            let renameStatus = exclusive
                ? renameatx_np(
                    directory, temporary.lastPathComponent,
                    directory, destination.lastPathComponent,
                    UInt32(RENAME_EXCL)
                )
                : renameat(
                    directory, temporary.lastPathComponent,
                    directory, destination.lastPathComponent
                )
            guard renameStatus == 0 else {
                if exclusive && errno == EEXIST {
                    throw ARCFileCollision.destinationExists
                }
                throw ARCError(.ioFailure, "ARC could not publish its room update.")
            }
            shouldRemove = false
            guard fsync(directory) == 0 else {
                throw ARCError(.ioFailure, "ARC could not synchronize its rooms folder.")
            }
        } catch let error as ARCFileCollision {
            throw error
        } catch let error as ARCError {
            throw error
        } catch {
            throw ARCError(.ioFailure, "ARC could not commit its room update.")
        }
    }

    private func openRoomsDirectory() throws -> Int32 {
        try rejectLinkedPath(roomsURL, allowMissingTail: false)
        let descriptor = Darwin.open(
            roomsURL.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw ARCError(.ioFailure, "ARC could not open its rooms folder.")
        }
        return descriptor
    }

    private func lstatExists(_ path: String) -> Bool {
        var value = stat()
        return lstat(path, &value) == 0
    }
}

private func rejectLinkedPath(_ url: URL, allowMissingTail: Bool) throws {
    guard url.isFileURL, url.path.hasPrefix("/") else {
        throw ARCError(.ioFailure, "ARC refused an unsafe data path.")
    }
    var path = "/"
    for component in (url.path as NSString).pathComponents.dropFirst() {
        path = (path as NSString).appendingPathComponent(component)
        var value = stat()
        if lstat(path, &value) != 0 {
            if allowMissingTail, errno == ENOENT { return }
            throw ARCError(.ioFailure, "ARC could not inspect its data path.")
        }
        guard (value.st_mode & S_IFMT) != S_IFLNK else {
            throw ARCError(.ioFailure, "ARC refused a linked data path.")
        }
    }
}

private func ensureDirectory(_ url: URL) throws {
    var value = stat()
    if lstat(url.path, &value) == 0 {
        guard (value.st_mode & S_IFMT) == S_IFDIR else {
            throw ARCError(.ioFailure, "ARC refused an unsafe data folder.")
        }
        return
    }
    guard errno == ENOENT else {
        throw ARCError(.ioFailure, "ARC could not inspect its data folder.")
    }
    do {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    } catch {
        throw ARCError(.ioFailure, "ARC could not create its data folder.")
    }
    guard lstat(url.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFDIR else {
        throw ARCError(.ioFailure, "ARC could not create a safe data folder.")
    }
}
