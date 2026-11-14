import MapKit
import SwiftUI

struct DriveView: View {
  @ObservedObject var location: LocationManager
  @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
  @State private var destination: CLLocationCoordinate2D?
  @State private var route: MKRoute?
  @State private var requestID = UUID()
  @State private var loading = false
  @State private var message: String?
  @State private var playbackID: String?
  @State private var playbackStatus: String?
  @State private var exportURL: URL?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      MapReader { proxy in
        Map(position: $camera) {
          UserAnnotation()
          if let destination {
            Marker("Destination", coordinate: destination)
          }
          if let route {
            MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
          }
        }
        .onTapGesture { point in
          guard let coordinate = proxy.convert(point, from: .local) else { return }
          destination = coordinate
          route = nil
          exportURL = nil
          message = nil
          loading = true
          requestID = UUID()
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        if let route, let exportURL {
          Text(
            "\(route.distance.formatted(.number.precision(.fractionLength(0)))) m · \(Int(ceil(route.expectedTravelTime / 60))) min"
          )
          HStack {
            Button("Start drive") { sendDrive(route) }
            Button("Stop simulation") { sendDrive(nil) }
          }
          if let playbackStatus { Text(playbackStatus).font(.footnote) }
          ShareLink(item: exportURL) {
            Label("Share drive GPX", systemImage: "square.and.arrow.up")
          }
        } else if let message {
          Text(message)
        } else if loading {
          ProgressView("Finding driving route…")
        } else {
          Text("Tap a destination to route from your current GPS fix.")
        }
      }
      .padding([.horizontal, .bottom])
    }
    .task(id: playbackID) {
      guard let id = playbackID else { return }
      if let reply = await SimulationRequest.confirmation(
        for: id, success: "Mac applied the request.")
      {
        playbackStatus = reply
      }
    }
    .task(id: requestID) { await calculateRoute() }
  }

  private func sendDrive(_ route: MKRoute?) {
    var request: [String: Any] = [:]
    if let route {
      let points = UnsafeBufferPointer(
        start: route.polyline.points(), count: route.polyline.pointCount)
      let waypoints = points.map {
        ["latitude": $0.coordinate.latitude, "longitude": $0.coordinate.longitude]
      }
      request["route"] =
        [
          "mode": "interval", "interval": 1,
          "speed": route.distance / max(1, route.expectedTravelTime), "waypoints": waypoints,
        ] as [String: Any]
    } else {
      request["stop"] = true
    }
    do {
      playbackID = try SimulationRequest.submit(request)
      playbackStatus = "Waiting for Mac…"
    } catch {
      playbackStatus = error.localizedDescription
    }
  }

  private func calculateRoute() async {
    guard let destination else { return }
    let id = requestID
    defer { if id == requestID { loading = false } }
    guard let lat = location.latitude, let lon = location.longitude else {
      message = "Waiting for a GPS fix. Check the GPS tab, then tap the destination again."
      return
    }
    let request = MKDirections.Request()
    request.source = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
    request.destination = MKMapItem(
      location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
      address: nil)
    request.transportType = .automobile
    do {
      let response = try await MKDirections(request: request).calculate()
      guard !Task.isCancelled, id == requestID else { return }
      guard let drive = response.routes.first, drive.polyline.pointCount >= 2 else {
        message = "No driving route found. Tap another destination."
        return
      }
      exportURL = try writeGPX(drive)
      route = drive
      camera = .rect(
        drive.polyline.boundingMapRect.insetBy(
          dx: -drive.polyline.boundingMapRect.width * 0.1 - 500,
          dy: -drive.polyline.boundingMapRect.height * 0.1 - 500))
    } catch {
      guard !Task.isCancelled, id == requestID else { return }
      message = error.localizedDescription + " Tap the map to retry."
    }
  }

  private func writeGPX(_ drive: MKRoute) throws -> URL {
    let points = Array(
      UnsafeBufferPointer(start: drive.polyline.points(), count: drive.polyline.pointCount))
    var distances = [0.0]
    for (a, b) in zip(points, points.dropFirst()) {
      distances.append(distances[distances.count - 1] + a.distance(to: b))
    }
    guard let total = distances.last, total > 0 else { throw CocoaError(.fileWriteUnknown) }
    let start = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="MyApp" xmlns="http://www.topografix.com/GPX/1/1">
      """
    for (point, distance) in zip(points, distances) {
      let time = start.addingTimeInterval(drive.expectedTravelTime * distance / total)
      let c = point.coordinate
      xml +=
        "\n<wpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\"><time>\(formatter.string(from: time))</time></wpt>"
    }
    xml += "\n</gpx>\n"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Drive-\(UUID().uuidString).gpx")
    try xml.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
