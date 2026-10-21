import XCTest
@testable import DragTimer

final class DurationMapperTests: XCTestCase {
    func testTinyDragCreatesNothing() {
        XCTAssertEqual(DurationMapper.seconds(for: 5), 0)
    }

    func testShortDragCreatesShortTimer() {
        let seconds = DurationMapper.seconds(for: 60)
        XCTAssertGreaterThanOrEqual(seconds, 60)
        XCTAssertLessThan(seconds, 30 * 60)
    }

    func testOptionMakesTimerLonger() {
        let normal = DurationMapper.seconds(for: 300)
        let option = DurationMapper.seconds(for: 300, optionMultiplier: true)
        XCTAssertEqual(option, normal * 4)
    }

    func testDurationIsCapped() {
        XCTAssertLessThanOrEqual(DurationMapper.seconds(for: 100_000, optionMultiplier: true), 72 * 60 * 60)
    }
}
