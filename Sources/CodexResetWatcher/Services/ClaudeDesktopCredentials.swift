import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import SQLite3
import Security

/// Sensitive values live only for a refresh, and never enter reports or error messages.
struct ClaudeDesktopSession: Sendable {
    let sessionKey: String
    let organization: UUID
    var fingerprint: Data { Data(SHA256.hash(data: Data((organization.uuidString + sessionKey).utf8))) }
}

struct ClaudeDesktopCredentials: Sendable {
    var database: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/Cookies")
    var password: @Sendable (Bool) throws -> Data = { try readPassword(allowInteraction: $0) }

    func load(allowInteraction: Bool = false) throws -> ClaudeDesktopSession {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw ClaudeDesktopError.loginUnavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw ClaudeDesktopError.loginUnavailable }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var meta: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &meta, nil) == SQLITE_OK else {
            throw ClaudeDesktopError.cookieFormat
        }
        defer { sqlite3_finalize(meta) }
        guard sqlite3_step(meta) == SQLITE_ROW else { throw ClaudeDesktopError.cookieFormat }
        let version = sqlite3_column_int(meta, 0)
        guard (23...24).contains(version) else { throw ClaudeDesktopError.cookieFormat }
        var statement: OpaquePointer?
        let sql = """
            SELECT name, host_key, encrypted_value, value, expires_utc, is_persistent
            FROM cookies WHERE host_key IN ('.claude.ai','claude.ai')
            AND name IN ('sessionKey','lastActiveOrg') AND path='/' AND top_frame_site_key=''
            """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw ClaudeDesktopError.cookieFormat }
        defer { sqlite3_finalize(statement) }
        var values: [String: String] = [:]
        var key: Data?
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let nameBytes = sqlite3_column_text(statement, 0),
                let hostBytes = sqlite3_column_text(statement, 1)
            else { throw ClaudeDesktopError.cookieFormat }
            let name = String(cString: nameBytes)
            let host = String(cString: hostBytes)
            let expires = Double(sqlite3_column_int64(statement, 4)) / 1_000_000 - 11_644_473_600
            if sqlite3_column_int(statement, 5) != 0, expires <= Date().timeIntervalSince1970 { continue }
            guard values[name] == nil else { throw ClaudeDesktopError.cookieFormat }
            let count = Int(sqlite3_column_bytes(statement, 2))
            guard count <= 16_384 else { throw ClaudeDesktopError.cookieFormat }
            let value: String
            if count > 0, let bytes = sqlite3_column_blob(statement, 2) {
                guard sqlite3_column_bytes(statement, 3) == 0 else { throw ClaudeDesktopError.cookieFormat }
                if key == nil { key = try Self.deriveKey(password(allowInteraction)) }
                value = try Self.decrypt(Data(bytes: bytes, count: count), key: key!, host: host, version: Int(version))
            } else {
                guard let text = sqlite3_column_text(statement, 3), sqlite3_column_bytes(statement, 3) <= 16_384 else {
                    throw ClaudeDesktopError.cookieFormat
                }
                value = String(cString: text)
            }
            values[name] = value
        }
        guard let session = values["sessionKey"], !session.isEmpty,
            session.utf8.allSatisfy({ (33...126).contains($0) && $0 != 59 && $0 != 44 && $0 != 34 && $0 != 92 }),
            let org = values["lastActiveOrg"], let organization = UUID(uuidString: org)
        else {
            throw ClaudeDesktopError.loginUnavailable
        }
        return ClaudeDesktopSession(sessionKey: session, organization: organization)
    }

    static func readPassword(allowInteraction: Bool) throws -> Data {
        var result: CFTypeRef?
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data, !data.isEmpty
        else { throw ClaudeDesktopError.keychainAccess }
        return data
    }

    static func deriveKey(_ password: Data) throws -> Data {
        var key = Data(count: 16)
        let salt = Array("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { output in
            password.withUnsafeBytes { input in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), input.bindMemory(to: Int8.self).baseAddress,
                    password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003, output.bindMemory(to: UInt8.self).baseAddress, 16)
            }
        }
        guard status == kCCSuccess else { throw ClaudeDesktopError.cookieFormat }
        return key
    }

    static func decrypt(_ encrypted: Data, key: Data, host: String, version: Int) throws -> String {
        guard encrypted.prefix(3) == Data("v10".utf8), key.count == 16 else { throw ClaudeDesktopError.cookieFormat }
        let ciphertext = Data(encrypted.dropFirst(3))
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let capacity = output.count
        var count = 0
        let iv = [UInt8](repeating: 32, count: 16)
        let status = output.withUnsafeMutableBytes { out in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv, input.baseAddress, ciphertext.count,
                        out.baseAddress, capacity, &count)
                }
            }
        }
        guard status == kCCSuccess else { throw ClaudeDesktopError.cookieFormat }
        output.count = count
        if version >= 24 {
            let hash = Data(SHA256.hash(data: Data(host.utf8)))
            guard output.starts(with: hash) else { throw ClaudeDesktopError.cookieFormat }
            output.removeFirst(hash.count)
        }
        guard let value = String(data: output, encoding: .utf8) else { throw ClaudeDesktopError.cookieFormat }
        return value
    }
}
