//
//  BuildSecrets.swift
//  Everywhere
//
//  Build-time secrets baked into Info.plist by Scripts/wire_project.rb,
//  which reads them from the gitignored `local.properties` at the repo
//  root — mirrors the Android app's `local.properties` ->
//  `buildConfigField` -> `BuildConfig.DYNU_API_KEY` pipeline.
//

import Foundation

enum BuildSecrets {
    /// Dynu DDNS API key, used by STServiceOrchestrator to mark a node
    /// code's TXT record as "consumed". Empty string if local.properties
    /// was missing/didn't set `dynu.apiKey` at build time (e.g. in CI).
    static var dynuApiKey: String {
        Bundle.main.infoDictionary?["DYNU_API_KEY"] as? String ?? ""
    }
}
