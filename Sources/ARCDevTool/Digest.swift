import ARCKnowledge
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum ARCDevDigest {
    static func data(_ value: Data) -> Data {
        let input = [UInt8](value)
        var output = [UInt8](repeating: 0, count: 32)
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                arc_knowledge_sha256(source.baseAddress, source.count, destination.baseAddress)
            }
        }
        return Data(output)
    }

    static func sameFileTimes(_ left: stat, _ right: stat) -> Bool {
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
}
