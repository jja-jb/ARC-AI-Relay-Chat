import ARCKnowledge
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// ARC uses its bundled SHA-256 implementation so macOS and Linux produce
/// identical digests without adding a third-party Swift package.
func arcSHA256Hex(_ data: Data) -> String {
    let input = [UInt8](data)
    var digest = [UInt8](repeating: 0, count: 32)
    input.withUnsafeBufferPointer { source in
        digest.withUnsafeMutableBufferPointer { destination in
            arc_knowledge_sha256(source.baseAddress, source.count, destination.baseAddress)
        }
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

func arcSameFileTimes(_ left: stat, _ right: stat) -> Bool {
    #if os(macOS)
    return left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec
        && left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec
        && left.st_ctimespec.tv_sec == right.st_ctimespec.tv_sec
        && left.st_ctimespec.tv_nsec == right.st_ctimespec.tv_nsec
    #else
    return left.st_mtim.tv_sec == right.st_mtim.tv_sec
        && left.st_mtim.tv_nsec == right.st_mtim.tv_nsec
        && left.st_ctim.tv_sec == right.st_ctim.tv_sec
        && left.st_ctim.tv_nsec == right.st_ctim.tv_nsec
    #endif
}

func arcRead(_ descriptor: Int32, _ destination: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if os(macOS)
    return Darwin.read(descriptor, destination, count)
    #else
    return Glibc.read(descriptor, destination, count)
    #endif
}

func arcWrite(_ descriptor: Int32, _ source: UnsafeRawPointer?, _ count: Int) -> Int {
    #if os(macOS)
    return Darwin.write(descriptor, source, count)
    #else
    return Glibc.write(descriptor, source, count)
    #endif
}
