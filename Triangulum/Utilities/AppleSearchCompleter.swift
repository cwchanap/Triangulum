import Foundation
import Combine
import MapKit

final class AppleSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var errorMessage: String?

    private let completer: MKLocalSearchCompleter = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        // Favor addresses and points of interest
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var region: MKCoordinateRegion? {
        didSet {
            if let region { completer.region = region }
        }
    }

    var queryFragment: String = "" {
        didSet {
            completer.queryFragment = queryFragment
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = completer.results
            self.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.results = []
            self.errorMessage = error.localizedDescription
        }
    }
}
