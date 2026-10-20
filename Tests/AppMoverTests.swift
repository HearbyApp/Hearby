import XCTest
@testable import Hearby

final class AppMoverTests: XCTestCase {
    private let home = "/Users/pat"

    func testOffersTheMoveWhereDownloadsLand() {
        XCTAssertTrue(AppMover.shouldOffer(path: "/Volumes/Hearby/Hearby.app", home: home))
        XCTAssertTrue(AppMover.shouldOffer(path: "/Users/pat/Downloads/Hearby.app", home: home))
        XCTAssertTrue(AppMover.shouldOffer(
            path: "/private/var/folders/x/T/AppTranslocation/1234/d/Hearby.app", home: home))
    }

    func testLeavesInstalledAndDeliberateCopiesAlone() {
        XCTAssertFalse(AppMover.shouldOffer(path: "/Applications/Hearby.app", home: home))
        XCTAssertFalse(AppMover.shouldOffer(path: "/Users/pat/Applications/Hearby.app", home: home))
        XCTAssertFalse(AppMover.shouldOffer(path: "/Users/pat/Projects/Hearby/build/Hearby.app", home: home))
        // Another user's Downloads isn't "where my download landed".
        XCTAssertFalse(AppMover.shouldOffer(path: "/Users/sam/Downloads/Hearby.app", home: home))
    }

    func testFindsTheDiskImageToEject() {
        XCTAssertEqual(AppMover.volume(of: "/Volumes/Hearby/Hearby.app"), "/Volumes/Hearby")
        XCTAssertEqual(AppMover.volume(of: "/Volumes/Hearby 1/Hearby.app"), "/Volumes/Hearby 1")
        XCTAssertNil(AppMover.volume(of: "/Users/pat/Downloads/Hearby.app"))
    }
}
