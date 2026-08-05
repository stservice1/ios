//
//  AndroidLog.swift
//  Everywhere
//
//  A tiny `android.util.Log`-shaped shim (`Log.d(tag, message)`, `.w`, `.e`)
//  so the ported STVPN business logic (STServiceOrchestrator, LoginViewModel,
//  STMainViewModel, ...) can keep its Android log call sites verbatim instead
//  of being rewritten around os_log's very different call shape. Backed by
//  os_log so messages still show up in Console.app / `xcrun simctl spawn log`.
//

import Foundation
import os.log

enum Log {
    private static var loggers: [String: Logger] = [:]

    private static func logger(for tag: String) -> Logger {
        if let existing = loggers[tag] { return existing }
        let logger = Logger(subsystem: "com.stservice.stvpn", category: tag)
        loggers[tag] = logger
        return logger
    }

    static func d(_ tag: String, _ message: String) {
        logger(for: tag).debug("\(message, privacy: .public)")
    }

    static func w(_ tag: String, _ message: String) {
        logger(for: tag).warning("\(message, privacy: .public)")
    }

    static func e(_ tag: String, _ message: String, _ error: Error? = nil) {
        if let error {
            logger(for: tag).error("\(message, privacy: .public): \(String(describing: error), privacy: .public)")
        } else {
            logger(for: tag).error("\(message, privacy: .public)")
        }
    }
}
