import XCTest

/// Made-up titles and artists only.
final class LRCLibClientTests: XCTestCase {
    func testTitleVariantsStripYouTubeDecorations() {
        XCTAssertEqual(LRCLibClient.titleVariants("Paper Moon (Official Video)"), ["Paper Moon (Official Video)", "Paper Moon"])
        XCTAssertEqual(LRCLibClient.titleVariants("Paper Moon [Lyric Video]"), ["Paper Moon [Lyric Video]", "Paper Moon"])
        XCTAssertEqual(LRCLibClient.titleVariants("Paper Moon (feat. Someone)"), ["Paper Moon (feat. Someone)", "Paper Moon"])
        XCTAssertEqual(LRCLibClient.titleVariants("Paper Moon - Remastered 2011"), ["Paper Moon - Remastered 2011", "Paper Moon"])
    }

    func testTitleVariantsKeepPlainTitles() {
        XCTAssertEqual(LRCLibClient.titleVariants("Paper Moon"), ["Paper Moon"])
        // Brackets that aren't decorations stay.
        XCTAssertEqual(LRCLibClient.titleVariants("Paper Moon (Part 2)"), ["Paper Moon (Part 2)"])
    }

    func testPrimaryArtist() {
        XCTAssertEqual(LRCLibClient.primaryArtist("Ana Lima & Ben Ross"), "Ana Lima")
        XCTAssertEqual(LRCLibClient.primaryArtist("Ana Lima, Ben Ross"), "Ana Lima")
        XCTAssertEqual(LRCLibClient.primaryArtist("Ana Lima feat. Ben Ross"), "Ana Lima")
        XCTAssertEqual(LRCLibClient.primaryArtist("Ana Lima"), "Ana Lima")
    }
}
