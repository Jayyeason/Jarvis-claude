import Foundation
import CoreLocation

struct LocationResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distance: CLLocationDistance?

    var distanceText: String {
        guard let d = distance else { return "" }
        return d < 1000
            ? String(format: "%.0f m", d)
            : String(format: "%.1f km", d / 1000)
    }
}
