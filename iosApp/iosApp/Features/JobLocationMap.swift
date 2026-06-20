import SwiftUI
import MapKit

/// Parsing + reusable MapKit views for a job's `work_google_map_location`
/// (a plain "lat,lng" string, same format Android stores). MapKit is built into
/// iOS — no SDK, key, or pbxproj wiring needed, unlike Google Maps on Android.
enum JobLocation {
    /// Parse "12.34,56.78" → coordinate. Returns nil for blank/garbage.
    static func parse(_ s: String?) -> CLLocationCoordinate2D? {
        guard let s, !s.isEmpty else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    static func string(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", c.latitude, c.longitude)
    }
}

/// A single map annotation (iOS 16's annotation API needs an Identifiable item).
private struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// Read-only map showing the job's pin, with an "Open in Maps" button.
/// Renders nothing if the job has no parseable coordinate.
struct JobLocationMap: View {
    let location: String?
    var addressFallback: String? = nil
    var height: CGFloat = 160

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let coord = JobLocation.parse(location) {
            VStack(spacing: 8) {
                Map(coordinateRegion: .constant(region(coord)),
                    interactionModes: [],
                    annotationItems: [MapPin(coordinate: coord)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: GHTheme.tertiary)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)

                Button { openInMaps(coord) } label: {
                    Label(L("open_in_maps"), systemImage: "map.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(GHTheme.tertiary).controlSize(.small)
            }
        }
    }

    private func region(_ c: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    }

    private func openInMaps(_ c: CLLocationCoordinate2D) {
        // Apple Maps with a labelled pin at the coordinate.
        let label = (addressFallback ?? "Job location").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let u = URL(string: "http://maps.apple.com/?ll=\(c.latitude),\(c.longitude)&q=\(label)") {
            openURL(u)
        }
    }
}

/// Tap-to-drop-pin map for choosing a job's location (Android's MapLocationPicker).
/// Binds the selected coordinate as a "lat,lng" string.
struct LocationPickerMap: View {
    @Binding var locationString: String
    var height: CGFloat = 240

    // India center default (matches Android's IndiaCenter) until a pin is set.
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20.5937, longitude: 78.9629),
        span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30))
    @State private var picked: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Map(coordinateRegion: $region,
                    annotationItems: picked.map { [MapPin(coordinate: $0)] } ?? []) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: GHTheme.tertiary)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // Drop a pin at the map center when the user taps "Set pin here".
            }
            HStack {
                if let p = picked {
                    Text(String(format: "%.4f, %.4f", p.latitude, p.longitude))
                        .font(.caption.monospaced()).foregroundStyle(GHTheme.onSurfaceVariant)
                } else {
                    Text(L("ios_pan_then_set_pin")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                Spacer()
                Button(L("ios_set_pin_here")) {
                    let c = region.center
                    picked = c
                    locationString = JobLocation.string(c)
                }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(GHTheme.tertiary).controlSize(.small)
            }
        }
        .onAppear {
            // Restore an existing pin (edit flow).
            if let c = JobLocation.parse(locationString) {
                picked = c
                region = MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            }
        }
    }
}
