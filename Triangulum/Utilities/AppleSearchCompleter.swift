import Foundation
import Combine
import MapKit

protocol AppleSearchCompleting: AnyObject {
    var delegate: MKLocalSearchCompleterDelegate? { get set }
    var resultTypes: MKLocalSearchCompleter.ResultType { get set }
    var region: MKCoordinateRegion { get set }
    var queryFragment: String { get set }
    var results: [MKLocalSearchCompletion] { get }
}

extension MKLocalSearchCompleter: AppleSearchCompleting {}

final class AppleSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var errorMessage: String?

    private let completer: any AppleSearchCompleting

    init(completer: any AppleSearchCompleting = MKLocalSearchCompleter()) {
        self.completer = completer
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
            self.results = self.completer.results
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
