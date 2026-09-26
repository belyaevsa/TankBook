import Foundation
import os
import Testing
@testable import TankbookCore

/// The foreground rates refresh asks only for what the cache lacks: the whole
/// `packWindowDays` window on a cold cache, a week before the newest cached day
/// otherwise. Asking for the whole window every time re-downloaded ~1.2 MB on
/// every foreground (production, 2026-09-26).
@Suite("Rates refresh is incremental")
struct RateRefreshIncrementalTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 18))!

    private final class RecordingFetcher: RateFetcher, @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [(Date, Date)]())
        var ranges: [(Date, Date)] { lock.withLock { $0 } }
        func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
            lock.withLock { $0.append((from, to)) }
            return RatePack(rates: [])
        }
    }

    private func day(_ offset: Int) -> Date {
        Self.calendar.date(byAdding: .day, value: offset, to: Self.calendar.startOfDay(for: Self.now))!
    }

    private func rate(_ date: Date, base: CurrencyCode = .eur) -> ExchangeRate {
        ExchangeRate(base: base, quote: .usd, date: date, rate: Decimal(string: "1.1")!, source: .ecb)
    }

    private func requestedStart(seed: [ExchangeRate]) async throws -> Date {
        let fetcher = RecordingFetcher()
        let store = RateStore(seed: seed, fetcher: fetcher, clock: { Self.now }, calendar: Self.calendar)
        await store.refresh(trigger: .userInitiated)
        return try #require(fetcher.ranges.first).0
    }

    @Test("a cold cache asks for the whole window")
    func coldCacheAsksForTheWindow() async throws {
        let start = try await requestedStart(seed: [])
        let days = Self.calendar.dateComponents([.day], from: Self.calendar.startOfDay(for: start),
                                                to: Self.calendar.startOfDay(for: Self.now)).day! + 1
        #expect(days == RateStore.packWindowDays)
    }

    @Test("a warm cache asks from a week before its newest day")
    func warmCacheAsksForTheTail() async throws {
        let start = try await requestedStart(seed: [rate(day(-400)), rate(day(-2)), rate(day(-30))])
        #expect(Self.calendar.isDate(start, inSameDayAs: day(-2 - RateStore.refreshOverlapDays)))
    }

    @Test("rows older than the window, or on another base, do not shrink the request")
    func onlyEurRowsInsideTheWindowCount() async throws {
        let stale = try await requestedStart(seed: [rate(day(-900))])
        let days = Self.calendar.dateComponents([.day], from: Self.calendar.startOfDay(for: stale),
                                                to: Self.calendar.startOfDay(for: Self.now)).day! + 1
        #expect(days == RateStore.packWindowDays, "a cache that only holds years-old rows is cold")
        let otherBase = try await requestedStart(seed: [rate(day(-1), base: .usd)])
        #expect(Self.calendar.dateComponents([.day], from: otherBase, to: Self.now).day! >= RateStore.packWindowDays - 1)
    }
}
