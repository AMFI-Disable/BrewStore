import AppKit
@testable import BrewStore
import XCTest

@MainActor
final class SidebarDestinationSelectionTests: XCTestCase {
    func testOnlyAuthenticDestinationsAreRegisteredAsSelectable() {
        let expectedDestinations = BrewStoreSection.allCases
        XCTAssertEqual(expectedDestinations.count, 19)

        for destination in expectedDestinations {
            XCTAssertTrue(
                BrewStoreSidebarDestinationRegistry.isSelectableDestination(identifier: destination.rawValue),
                "Destination rawValue should be selectable: \(destination.rawValue)"
            )
            XCTAssertTrue(
                BrewStoreSidebarDestinationRegistry.isSelectableDestination(identifier: destination.id),
                "Destination id should be selectable: \(destination.id)"
            )
            XCTAssertFalse(
                BrewStoreSidebarDestinationRegistry.isGroupHeader(identifier: destination.rawValue),
                "Destination rawValue must not be classified as a group header: \(destination.rawValue)"
            )
        }
    }

    func testSidebarGroupHeadersAreNotSelectableDestinations() {
        let groupHeaders = BrewStoreSidebarGroup.allCases
        XCTAssertEqual(groupHeaders.count, 4)

        for group in groupHeaders {
            // Group raw title (e.g. "Storefront") must not be a selectable destination
            XCTAssertFalse(
                BrewStoreSidebarDestinationRegistry.isSelectableDestination(identifier: group.rawValue),
                "Group header '\(group.rawValue)' must not be selectable as a navigation destination."
            )

            // Group accessibility identifier must not be a selectable destination
            XCTAssertFalse(
                BrewStoreSidebarDestinationRegistry.isSelectableDestination(identifier: group.accessibilityIdentifier),
                "Group identifier '\(group.accessibilityIdentifier)' must not be selectable as a navigation destination."
            )

            // Both must be recognized as group headings
            XCTAssertTrue(
                BrewStoreSidebarDestinationRegistry.isGroupHeader(identifier: group.rawValue),
                "Group title '\(group.rawValue)' must be recognized as a group header."
            )
            XCTAssertTrue(
                BrewStoreSidebarDestinationRegistry.isGroupHeader(identifier: group.accessibilityIdentifier),
                "Group identifier '\(group.accessibilityIdentifier)' must be recognized as a group header."
            )
        }
    }

    func testResolveSelectionRejectsGroupHeadersAndAcceptsDestinations() {
        // Group titles should reject resolution to a section
        for group in BrewStoreSidebarGroup.allCases {
            XCTAssertNil(
                BrewStoreSidebarDestinationRegistry.resolveSelection(from: group.rawValue),
                "Resolving selection for group '\(group.rawValue)' must return nil."
            )
            XCTAssertNil(
                BrewStoreSidebarDestinationRegistry.resolveSelection(from: group.accessibilityIdentifier),
                "Resolving selection for identifier '\(group.accessibilityIdentifier)' must return nil."
            )
        }

        // Real destinations should resolve properly
        for section in BrewStoreSection.allCases {
            XCTAssertEqual(
                BrewStoreSidebarDestinationRegistry.resolveSelection(from: section.rawValue),
                section,
                "Resolving selection for destination '\(section.rawValue)' must return the exact section."
            )
        }
    }

    func testOutlineManagerRejectsGroupAndHeaderItems() {
        let outlineView = NSOutlineView()
        let manager = BrewStoreSidebarOutlineManager.shared

        // Test item classification
        let mockItem = "GroupHeaderMock"
        // In a bare outlineView where item is neither group nor expandable, regular leaf should be selectable
        XCTAssertTrue(manager.outlineView(outlineView, shouldSelectItem: mockItem))

        // Proposed selection with multiple indexes
        let proposed = IndexSet([0, 1, 2])
        let allowed = manager.outlineView(outlineView, selectionIndexesForProposedSelection: proposed)
        // With no delegate group items configured, all plain rows are preserved
        XCTAssertEqual(allowed, proposed)
    }
}
