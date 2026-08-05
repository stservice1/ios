//
//  AsyncTimeout.swift
//  Everywhere
//
//  Swift-concurrency equivalent of Kotlin's `withTimeoutOrNull`: races
//  `operation` against a `seconds`-long timer and returns nil if the timer
//  wins. An error thrown by `operation` itself still propagates (matching
//  Kotlin — `withTimeoutOrNull` only swallows the timeout, not real errors).
//

import Foundation

func withTimeoutOrNil<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        guard let first = try await group.next() else { return nil }
        group.cancelAll()
        return first
    }
}
