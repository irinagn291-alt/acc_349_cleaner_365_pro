import Foundation
import CryptoKit

struct ArchiveIntegrity: Codable, Equatable {
    let bytes: Int64
    let sha256: String
}

enum EncryptedArchive {
    static let chunkSize = 1_048_576
    static func encrypt(input: URL, output: URL, key: SymmetricKey, identity: String) throws -> ArchiveIntegrity {
        let manager = FileManager.default
        guard manager.createFile(atPath: output.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw VaultError("Could not create the vault file.") }
        let source = try FileHandle(forReadingFrom: input); defer { try? source.close() }
        let target = try FileHandle(forWritingTo: output); defer { try? target.close() }
        var hash = SHA256(); var bytes: Int64 = 0; var index = 0
        do {
            while let data = try source.read(upToCount: chunkSize), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data); bytes += Int64(data.count)
                let sealed = try AES.GCM.seal(data, using: key, authenticating: Data("\(identity):\(index)".utf8)).combined!
                var length = UInt32(sealed.count).bigEndian
                try target.write(contentsOf: withUnsafeBytes(of: &length) { Data($0) }); try target.write(contentsOf: sealed)
                index += 1
            }
            try target.synchronize()
            return ArchiveIntegrity(bytes: bytes, sha256: hash.finalize().map { String(format: "%02x",$0) }.joined())
        } catch { try? manager.removeItem(at: output); throw error }
    }
    static func decrypt(input: URL, output: URL?, key: SymmetricKey, identity: String, expected: ArchiveIntegrity) throws {
        let manager = FileManager.default
        let source = try FileHandle(forReadingFrom: input); defer { try? source.close() }
        var target: FileHandle?
        if let output {
            guard manager.createFile(atPath: output.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete]) else { throw VaultError("Could not prepare a protected file.") }
            target = try FileHandle(forWritingTo: output)
        }
        defer { try? target?.close() }
        var hash = SHA256(); var bytes: Int64 = 0; var index = 0
        do {
            while let header = try source.read(upToCount: 4), !header.isEmpty {
                try Task.checkCancellation()
                guard header.count == 4 else { throw VaultError("The vault copy is incomplete.") }
                let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                guard length >= 28 && length <= chunkSize + 28, let sealed = try source.read(upToCount: Int(length)), sealed.count == Int(length) else { throw VaultError("The vault copy is damaged.") }
                let data = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: Data("\(identity):\(index)".utf8))
                hash.update(data: data); bytes += Int64(data.count)
                guard bytes <= expected.bytes else { throw VaultError("The size of the copy changed.") }
                try target?.write(contentsOf: data); index += 1
            }
            let actual = ArchiveIntegrity(bytes: bytes, sha256: hash.finalize().map { String(format: "%02x",$0) }.joined())
            guard actual == expected else { throw VaultError("The copy failed its integrity check.") }
        } catch { if let output { try? manager.removeItem(at: output) }; throw error }
    }
}
