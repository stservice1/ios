//
//  DNSTXTClient.swift
//  Everywhere
//
//  Low-level AliDNS-over-HTTPS GET, shared by LoginViewModel.validateNodeCode
//  and STServiceOrchestrator.checkTXTRecord/checkTXTRecordMandatory — ported
//  from the (duplicated, in Kotlin) HttpURLConnection boilerplate in
//  LoginActivity.kt and STServiceOrchestrator.kt. The two call sites still
//  parse the response body differently, exactly as they did in Kotlin, so
//  only the URL-building and the raw HTTP GET are factored out here.
//

import Foundation

enum DNSTXTClient {
    /// Builds the AliDNS DoH URL for `<nodeCode>.stservice<lastTwoDigits>.ddnsfree.com`
    /// — identical on both the Kotlin call sites (LoginActivity.validateNodeCode
    /// inlined it; STServiceOrchestrator.buildTXTCheckURL named it).
    static func buildTXTCheckURL(nodeCode: String) -> String {
        let lastTwoDigits = String(nodeCode.suffix(2))
        let domain = "\(nodeCode).stservice\(lastTwoDigits).ddnsfree.com"
        return "https://dns.alidns.com/resolve?name=\(domain)&type=TXT"
    }

    struct Response {
        let statusCode: Int
        let body: String
    }

    /// GETs `urlString`. Throws on transport failure or a malformed URL; a
    /// non-200 status is still returned normally (matching
    /// HttpURLConnection, which doesn't throw on non-2xx) so callers can
    /// branch on it themselves.
    static func get(_ urlString: String, timeout: TimeInterval) async throws -> Response {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: data, encoding: .utf8) ?? ""
        return Response(statusCode: statusCode, body: body)
    }
}
