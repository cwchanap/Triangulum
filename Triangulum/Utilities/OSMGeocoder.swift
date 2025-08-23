import Foundation
import CoreLocation

// Lightweight OSM (Nominatim) geocoder for place search in OSM mode.
// It uses the public Nominatim service with polite headers.
enum OSMGeocoder {
    struct Result: Decodable {
        let display_name: String
        let lat: String
        let lon: String

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: Double(lat) ?? 0, longitude: Double(lon) ?? 0)
        }
    }

    static func search(query: String, limit: Int = 5) async throws -> [Result] {
        guard var components = URLComponents(string: "https://nominatim.openstreetmap.org/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Provide a friendly User-Agent per Nominatim usage policy
        let appId = Bundle.main.bundleIdentifier ?? "Triangulum"
        request.setValue("Triangulum/1.0 (+\(appId))", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }
        do {
            let results = try JSONDecoder().decode([Result].self, from: data)
            return results
        } catch {
            return []
        }
    }
}

