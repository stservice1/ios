//
//  SubscriptionFetcher.swift
//  Everywhere
//
//  Downloads a subscription URL's raw config text. Extracted out of
//  ConfigurationsView's private `fetchConfig(from:)` so both the
//  Configurations screen (manual "Subscribe"/"Update" actions) and
//  ProfileFactory (the STVPN login flow's automatic profile creation, which
//  mirrors Android's Profile.update()) share one implementation instead of
//  two copies of the same HTTP-fetch-and-validate code.
//

import Foundation

enum SubscriptionFetcher {
    struct FetchError: LocalizedError {
        let errorDescription: String?
    }

    static func fetch(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Everywhere/1.0 Clash/1.11.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError(errorDescription: "Server returned HTTP \(http.statusCode).")
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw FetchError(errorDescription: "Response is not valid UTF-8 text.")
        }
        return content
    }
}
