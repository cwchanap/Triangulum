import Testing
import Foundation
import MapKit
@testable import Triangulum

private final class MockAppleSearchCompleter: AppleSearchCompleting {
    var delegate: MKLocalSearchCompleterDelegate?
    var resultTypes: MKLocalSearchCompleter.ResultType = []
    var region: MKCoordinateRegion = .init()
    var queryFragment: String = ""
    var results: [MKLocalSearchCompletion] = []
}

@Suite(.serialized)
struct AppleSearchCompleterTests {
    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test @MainActor func testInitConfiguresDelegateAndResultTypes() {
        let mockCompleter = MockAppleSearchCompleter()

        let completer = AppleSearchCompleter(completer: mockCompleter)

        #expect((mockCompleter.delegate as AnyObject?) === completer)
        #expect(mockCompleter.resultTypes.contains(.address))
        #expect(mockCompleter.resultTypes.contains(.pointOfInterest))
    }

    @Test @MainActor func testRegionForwardsToUnderlyingCompleter() {
        let mockCompleter = MockAppleSearchCompleter()
        let completer = AppleSearchCompleter(completer: mockCompleter)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.75)
        )

        completer.region = region

        #expect(mockCompleter.region.center.latitude == region.center.latitude)
        #expect(mockCompleter.region.center.longitude == region.center.longitude)
        #expect(mockCompleter.region.span.latitudeDelta == region.span.latitudeDelta)
        #expect(mockCompleter.region.span.longitudeDelta == region.span.longitudeDelta)
    }

    @Test @MainActor func testQueryFragmentForwardsToUnderlyingCompleter() {
        let mockCompleter = MockAppleSearchCompleter()
        let completer = AppleSearchCompleter(completer: mockCompleter)

        completer.queryFragment = "coffee"

        #expect(mockCompleter.queryFragment == "coffee")
    }

    @Test @MainActor func testCompleterDidUpdateResultsClearsErrorMessage() async {
        let mockCompleter = MockAppleSearchCompleter()
        let completer = AppleSearchCompleter(completer: mockCompleter)
        completer.errorMessage = "Old error"

        completer.completerDidUpdateResults(MKLocalSearchCompleter())
        await waitUntil { completer.errorMessage == nil }

        #expect(completer.results.isEmpty)
        #expect(completer.errorMessage == nil)
    }

    @Test @MainActor func testCompleterDidFailWithErrorPublishesError() async {
        let mockCompleter = MockAppleSearchCompleter()
        let completer = AppleSearchCompleter(completer: mockCompleter)
        let error = NSError(
            domain: "AppleSearchCompleterTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Mock search failure"]
        )

        completer.completer(MKLocalSearchCompleter(), didFailWithError: error)
        await waitUntil { completer.errorMessage == "Mock search failure" }

        #expect(completer.results.isEmpty)
        #expect(completer.errorMessage == "Mock search failure")
    }
}
