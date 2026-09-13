import XCTest
@testable import Raepplispauter

/// Tests zur prozentualen Aufteilung – die zentrale Zusage lautet:
/// **die Summe ist immer genau 100 %.**
final class SplitCalculatorTests: XCTestCase {

    private func assertSums100(_ values: [Double], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(SplitCalculator.sum(values), 100, accuracy: 0.05, file: file, line: line)
    }

    // MARK: - Gleichmässig verteilen

    func testEqualSharesForTwo() {
        XCTAssertEqual(SplitCalculator.equalShares(count: 2), [50, 50])
    }

    func testEqualSharesForThreeSumsTo100() {
        let values = SplitCalculator.equalShares(count: 3)
        assertSums100(values)
        XCTAssertEqual(values.count, 3)
    }

    func testEqualSharesForSevenSumsTo100() {
        assertSums100(SplitCalculator.equalShares(count: 7))
    }

    func testEqualSharesForOneIsHundred() {
        XCTAssertEqual(SplitCalculator.equalShares(count: 1), [100])
    }

    func testEqualSharesForZeroIsEmpty() {
        XCTAssertTrue(SplitCalculator.equalShares(count: 0).isEmpty)
    }

    // MARK: - Schieber bewegen

    func testAdjustKeepsTotalAt100() {
        let values = SplitCalculator.adjust([50, 50], to: 70, at: 0)
        XCTAssertEqual(values[0], 70)
        XCTAssertEqual(values[1], 30)
        assertSums100(values)
    }

    func testAdjustDistributesProportionally() {
        // Beat und Cem stehen 2:1 zueinander; das bleibt beim Verkleinern erhalten.
        let values = SplitCalculator.adjust([40, 40, 20], to: 10, at: 0)
        XCTAssertEqual(values[0], 10)
        XCTAssertEqual(values[1], 60, accuracy: 0.05)
        XCTAssertEqual(values[2], 30, accuracy: 0.05)
        assertSums100(values)
    }

    func testAdjustCannotExceed100() {
        let values = SplitCalculator.adjust([50, 50], to: 150, at: 0)
        XCTAssertEqual(values[0], 100)
        XCTAssertEqual(values[1], 0)
        assertSums100(values)
    }

    func testAdjustCannotGoBelowZero() {
        let values = SplitCalculator.adjust([50, 50], to: -20, at: 0)
        XCTAssertEqual(values[0], 0)
        XCTAssertEqual(values[1], 100)
        assertSums100(values)
    }

    func testAdjustSpreadsEvenlyWhenOthersAreZero() {
        let values = SplitCalculator.adjust([100, 0, 0], to: 40, at: 0)
        XCTAssertEqual(values[0], 40)
        XCTAssertEqual(values[1], 30, accuracy: 0.05)
        XCTAssertEqual(values[2], 30, accuracy: 0.05)
        assertSums100(values)
    }

    func testAdjustWithSinglePersonStaysAt100() {
        XCTAssertEqual(SplitCalculator.adjust([100], to: 40, at: 0), [100])
    }

    func testAdjustLeavesMovedSliderUntouched() {
        // Die Rundungsdifferenz darf nie auf dem eben bewegten Schieber landen.
        let values = SplitCalculator.adjust([33.4, 33.3, 33.3], to: 33, at: 1)
        XCTAssertEqual(values[1], 33)
        assertSums100(values)
    }

    func testRepeatedAdjustmentsStayValid() {
        var values = SplitCalculator.equalShares(count: 4)
        for round in 0..<12 {
            values = SplitCalculator.adjust(values, to: Double((round * 7) % 101), at: round % 4)
            assertSums100(values)
            XCTAssertFalse(values.contains { $0 < 0 })
            XCTAssertFalse(values.contains { $0 > 100 })
        }
    }

    // MARK: - Normalisieren

    func testNormaliseFixesRoundingDrift() {
        assertSums100(SplitCalculator.normalise([33.3, 33.3, 33.3]))
    }

    func testNormaliseScalesNothingBelowZero() {
        let values = SplitCalculator.normalise([-10, 60, 60])
        XCTAssertFalse(values.contains { $0 < 0 })
        assertSums100(values)
    }

    // MARK: - Gültigkeit

    func testIsValid() {
        XCTAssertTrue(SplitCalculator.isValid([50, 50]))
        XCTAssertTrue(SplitCalculator.isValid([33.4, 33.3, 33.3]))
        XCTAssertFalse(SplitCalculator.isValid([50, 60]))
        XCTAssertFalse(SplitCalculator.isValid([-10, 110]))
    }
}
