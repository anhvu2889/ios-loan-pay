import Foundation

/// A value plus the truth about where and when it came from.
///
/// ARCH: offline-first reads can't be modeled as a plain return value —
/// stale-while-revalidate produces UP TO TWO answers (cached now, fresh
/// later), and the UI must label them differently ("Updated 12m ago" vs
/// nothing). Wrapping the value keeps that honesty in the type system
/// instead of in a side-channel flag someone forgets to read.
public struct Snapshot<Value: Sendable>: Sendable {
    public let value: Value
    public let fetchedAt: Date
    public let isFromCache: Bool

    public init(value: Value, fetchedAt: Date, isFromCache: Bool) {
        self.value = value
        self.fetchedAt = fetchedAt
        self.isFromCache = isFromCache
    }
}

extension Snapshot: Equatable where Value: Equatable {}
