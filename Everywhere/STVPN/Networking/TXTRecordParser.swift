//
//  TXTRecordParser.swift
//  Everywhere
//
//  1:1 port of the Android app's util/TXTRecordParser.kt: parses the JSON
//  blob stored in the node code's DNS TXT record (short keys: v/b/e/c/m/u/d/r)
//  into a TXTRecordInfo, with the same lenient "default on missing/bad field"
//  behavior as org.json's `optInt`/`optBoolean`/`optString`/`optLong`.
//

import Foundation

/// Mirrors the Kotlin `data class TXTRecordInfo`.
struct TXTRecordInfo: Equatable {
    var version: Int
    var banned: Bool
    var expiration: Date?
    var consumed: Bool
    var modified: Int64
    var vpnUrl: String?
    var domainId: Int64
    var recordId: Int64
    /// Legacy field for backward compatibility — never populated by the
    /// parser/cache, kept only because the Kotlin struct still carries it.
    var message: String?
    /// Legacy alias for `vpnUrl` (Kotlin: `val link: String? = vpnUrl`).
    var link: String? { vpnUrl }

    init(
        version: Int,
        banned: Bool,
        expiration: Date?,
        consumed: Bool,
        modified: Int64,
        vpnUrl: String?,
        domainId: Int64,
        recordId: Int64,
        message: String? = nil
    ) {
        self.version = version
        self.banned = banned
        self.expiration = expiration
        self.consumed = consumed
        self.modified = modified
        self.vpnUrl = vpnUrl
        self.domainId = domainId
        self.recordId = recordId
        self.message = message
    }
}

enum TXTRecordParser {
    private static let tag = "TXTRecordParser"

    /// `yyyy-MM-dd`, Locale.US, device-default timezone — matches Android's
    /// `SimpleDateFormat("yyyy-MM-dd", Locale.US)` (no explicit timezone set
    /// there either, so it also falls back to the device's default zone).
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseTXTData(_ txtData: String) -> TXTRecordInfo {
        // Remove outer quotes and unescape internal quotes.
        var cleanData = txtData
        if cleanData.hasPrefix("\"") { cleanData.removeFirst() }
        if cleanData.hasSuffix("\"") { cleanData.removeLast() }
        cleanData = cleanData.replacingOccurrences(of: "\\\"", with: "\"")
        Log.d(tag, "Parsing TXT JSON data: '\(cleanData)'")

        guard let data = cleanData.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Log.e(tag, "Error parsing TXT record JSON data")
            return TXTRecordInfo(version: 1, banned: false, expiration: nil, consumed: false, modified: 0, vpnUrl: nil, domainId: 0, recordId: 0)
        }

        let version = optInt(json, "v", 1)
        let banned = optBool(json, "b", false)
        let consumed = optBool(json, "c", false)
        let modified = optLong(json, "m", 0)
        let vpnUrl = optString(json, "u", "")
        let domainId = optLong(json, "d", 0)
        let recordId = optLong(json, "r", 0)

        var expiration: Date?
        let expirationStr = optString(json, "e", "")
        if !expirationStr.isEmpty {
            if let date = dateFormatter.date(from: expirationStr) {
                expiration = date
                Log.d(tag, "Parsed expiration date: \(expirationStr) -> \(date)")
            } else {
                Log.e(tag, "Error parsing expiration date: \(expirationStr)")
            }
        }

        Log.d(tag, "Parsed JSON TXT record: v=\(version), b=\(banned), e=\(String(describing: expiration)), c=\(consumed), m=\(modified), u=\(vpnUrl), d=\(domainId), r=\(recordId)")

        return TXTRecordInfo(
            version: version,
            banned: banned,
            expiration: expiration,
            consumed: consumed,
            modified: modified,
            vpnUrl: vpnUrl.isEmpty ? nil : vpnUrl,
            domainId: domainId,
            recordId: recordId
        )
    }

    static func isExpired(_ txtInfo: TXTRecordInfo) -> Bool {
        guard let expiration = txtInfo.expiration else { return false }
        return Date() > expiration
    }

    // MARK: - org.json-style lenient accessors

    private static func optInt(_ json: [String: Any], _ key: String, _ def: Int) -> Int {
        (json[key] as? NSNumber)?.intValue ?? def
    }

    private static func optLong(_ json: [String: Any], _ key: String, _ def: Int64) -> Int64 {
        (json[key] as? NSNumber)?.int64Value ?? def
    }

    private static func optBool(_ json: [String: Any], _ key: String, _ def: Bool) -> Bool {
        if let b = json[key] as? Bool { return b }
        if let s = json[key] as? String {
            if s.caseInsensitiveCompare("true") == .orderedSame { return true }
            if s.caseInsensitiveCompare("false") == .orderedSame { return false }
        }
        return def
    }

    private static func optString(_ json: [String: Any], _ key: String, _ def: String) -> String {
        json[key] as? String ?? def
    }
}
