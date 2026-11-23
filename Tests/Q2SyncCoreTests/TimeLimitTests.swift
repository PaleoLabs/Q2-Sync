//
//  TimeLimitTests.swift
//  Q2-Sync › Tests
//
//  PURPOSE
//  Checks that waiting with a time limit returns the result in time, gives
//  up on work that runs too long, and passes errors through.
//

import Foundation
import Testing
@testable import Q2SyncCore

@Suite("Time limit")
struct TimeLimitTests {

    struct Boom: Error {}

    @Test("A quick task's value comes back")
    func quick() async throws {
        let task = Task<Int, any Error> { 42 }
        let result = await TimeLimit.result(of: task, within: .seconds(5))
        #expect(try result?.get() == 42)
    }

    @Test("A task that runs too long gives nil, without waiting for it")
    func tooLong() async {
        let clock = ContinuousClock()
        let start = clock.now
        // Ignores cancellation, like a stuck ITLibrary read.
        let task = Task<Int, any Error> {
            usleep(2_000_000) // Blocks the thread, ignoring cancellation.
            return 1
        }
        let result = await TimeLimit.result(of: task, within: .milliseconds(100))
        #expect(result == nil)
        #expect(clock.now - start < .seconds(1))
    }

    @Test("A failing task's error comes back")
    func failure() async {
        let task = Task<Int, any Error> { throw Boom() }
        let result = await TimeLimit.result(of: task, within: .seconds(5))
        #expect(throws: Boom.self) { try result?.get() }
    }
}
