import MapKit
import CoreLocation

class MapKitTool {
    static func search(keyword: String) async -> [LocationResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            let userLocation = CLLocation(latitude: 39.9042, longitude: 116.4074) // Beijing fallback
            return response.mapItems.prefix(5).map { item in
                let itemLocation = item.placemark.location
                return LocationResult(
                    name: item.name ?? keyword,
                    address: item.placemark.formattedAddress,
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    distance: itemLocation?.distance(from: userLocation)
                )
            }
        } catch {
            return []
        }
    }
}

extension MKPlacemark {
    var formattedAddress: String {
        [subLocality, locality, administrativeArea]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
