import Foundation
import SQLite3
import CryptoKit

struct BackupArchive: Codable {
    var backupVersion: Int
    var createdAt: String
    var files: [String: Data]
    var checksums: [String: String]
}

enum BackupService {
    static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    // Restores only to a newly created directory. Existing databases are never replaced.
    // The caller can then open LibraryStore(directory:) to verify/recover this snapshot.
    static func restore(_ archiveData: Data, toNewDirectory directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw LibraryError.conflict("恢复目录已存在，禁止覆盖") }
        let archive = try JSONCoding.decoder().decode(BackupArchive.self, from: archiveData)
        let names = Set(DatabaseSchema.files.map { $0.1 })
        guard archive.backupVersion == 1, Set(archive.files.keys) == names, Set(archive.checksums.keys) == names else { throw LibraryError.validation(["备份版本或数据库文件清单无效"]) }
        for (name, data) in archive.files {
            guard checksum(data) == archive.checksums[name] else { throw LibraryError.validation(["备份校验和不匹配：\(name)"]) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for (name, data) in archive.files { try data.write(to: directory.appendingPathComponent(name), options: .atomic) }
            let restored = try LibraryStore(directory: directory)
            try restored.checkIntegrity()
            _ = try restored.snapshot()
        } catch {
            // Only this method's newly created directory is removed on failure.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

extension LibraryStore {
    func backup(to parent: URL) throws -> URL {
        try synchronized {
            try checkIntegrity()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let token = UUID().uuidString.lowercased()
            let staging = parent.appendingPathComponent(".backup-\(token)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: staging) }
            var files: [String: Data] = [:]
            var checksums: [String: String] = [:]
            // A read transaction pins the source snapshot; the store lock excludes all app writes.
            try db.execute("BEGIN")
            do {
                for (schema, _) in DatabaseSchema.files { _ = try db.rows("SELECT count(*) FROM \(schema).sqlite_master") }
                for (schema, filename) in DatabaseSchema.files {
                    let output = staging.appendingPathComponent(filename)
                    do {
                        let destination = try SQLiteConnection(url: output)
                        guard let backup = sqlite3_backup_init(destination.handle, "main", db.handle, schema) else { throw destination.failure() }
                        var status = SQLITE_OK
                        var retries = 0
                        repeat {
                            status = sqlite3_backup_step(backup, 128)
                            if status == SQLITE_BUSY || status == SQLITE_LOCKED {
                                retries += 1; if retries <= 50 { Thread.sleep(forTimeInterval: 0.01) }
                            }
                        } while status == SQLITE_OK || ((status == SQLITE_BUSY || status == SQLITE_LOCKED) && retries <= 50)
                        let finish = sqlite3_backup_finish(backup)
                        guard status == SQLITE_DONE, finish == SQLITE_OK else { throw destination.failure() }
                        guard try destination.rows("PRAGMA integrity_check").allSatisfy({ $0.values.first == "ok" }) else { throw LibraryError.database("备份完整性检查失败") }
                    }
                    let data = try Data(contentsOf: output)
                    files[filename] = data; checksums[filename] = BackupService.checksum(data)
                }
                try db.execute("COMMIT")
            } catch { try? db.execute("ROLLBACK"); throw error }
            let archive = BackupArchive(backupVersion: 1, createdAt: Timestamp.now(), files: files, checksums: checksums)
            let output = parent.appendingPathComponent("KaoyanEnglish-\(token).kaoyanbackup")
            try JSONCoding.encoder().encode(archive).write(to: output, options: .atomic)
            return output
        }
    }
}
