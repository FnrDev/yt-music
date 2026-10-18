import XCTest

/// Uses made-up lines only; no real lyrics in the repository.
final class LRCParserTests: XCTestCase {
    func testParsesTimestampsAndText() {
        let lines = LRCParser.parse("""
        [00:01.50] First line
        [00:04.20] Second line
        [01:02.345] Third line
        """)
        XCTAssertEqual(lines.map(\.text), ["First line", "Second line", "Third line"])
        XCTAssertEqual(lines[0].time, 1.5, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 4.2, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 62.345, accuracy: 0.001)
        XCTAssertEqual(lines.map(\.id), [0, 1, 2])
    }

    func testRepeatedTimestampsExpandAndSort() {
        let lines = LRCParser.parse("""
        [00:10.00][00:30.00] Repeated line
        [00:20.00] Middle line
        """)
        XCTAssertEqual(lines.map(\.text), ["Repeated line", "Middle line", "Repeated line"])
        XCTAssertEqual(lines.map(\.time), [10, 20, 30])
    }

    func testIgnoresMetadataAndUntimedLines() {
        let lines = LRCParser.parse("""
        [ar:Some Artist]
        [ti:Some Title]
        Untimed text
        [00:05.00] Only timed line
        """)
        XCTAssertEqual(lines.map(\.text), ["Only timed line"])
    }

    func testKeepsInstrumentalGapsAsEmptyLines() {
        let lines = LRCParser.parse("[00:05.00] Line\n[00:09.00]\n[00:15.00] Next")
        XCTAssertEqual(lines.map(\.text), ["Line", "", "Next"])
    }

    func testAppliesOffsetTag() {
        // +500 ms means lyrics appear half a second sooner.
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00] Line")
        XCTAssertEqual(lines.first?.time ?? -1, 9.5, accuracy: 0.001)
    }

    func testCurrentIndex() {
        let lines = LRCParser.parse("[00:02.00] A\n[00:05.00] B\n[00:09.00] C")
        XCTAssertNil(LRCParser.currentIndex(in: lines, at: 1.0))
        XCTAssertEqual(LRCParser.currentIndex(in: lines, at: 2.0), 0)
        XCTAssertEqual(LRCParser.currentIndex(in: lines, at: 6.5), 1)
        XCTAssertEqual(LRCParser.currentIndex(in: lines, at: 120), 2)
        XCTAssertNil(LRCParser.currentIndex(in: [], at: 3))
    }
}
