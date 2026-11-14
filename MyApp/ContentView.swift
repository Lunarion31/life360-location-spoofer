import SwiftUI

struct ContentView: View {
  @StateObject private var location = LocationManager()

  @State private var requestID: String?
  @State private var controlStatus = ""

  var body: some View {
    TabView {
      DriveView(location: location)
        .tabItem { Label("Drive", systemImage: "car") }
      RoutineView()
        .tabItem { Label("Routine", systemImage: "calendar") }
      diagnostics
        .tabItem { Label("GPS", systemImage: "location") }
    }
  }

  private var diagnostics: some View {
    VStack(spacing: 16) {
      Text("GPS Debugger")
        .font(.title)

      if let lat = location.latitude,
        let lon = location.longitude
      {
        Text("Latitude: \(lat)")
        Text("Longitude: \(lon)")

        if let source = location.source {
          Text(
            source.isSimulatedBySoftware ? "Software simulation: yes" : "Software simulation: no")
          Text(source.isProducedByAccessory ? "External accessory: yes" : "External accessory: no")
        } else {
          Text("Source information unavailable")
        }

        if let fixTime = location.fixTime {
          Text("Location fix: \(fixTime.formatted(date: .abbreviated, time: .standard))")
        }
      } else {
        Text("Waiting for location...")
      }

      Button("Hold here") {
        guard let lat = location.latitude, let lon = location.longitude else { return }
        send(["hold": [lat, lon]])
      }
      .disabled(location.latitude == nil || location.longitude == nil)

      Button("Clear simulation") { send(["stop": true]) }
      if !controlStatus.isEmpty { Text(controlStatus).font(.footnote) }

      if let error = location.errorMessage {
        Text(error)
          .foregroundStyle(.red)
      }
    }
    .padding()
    .task(id: requestID) {
      guard let id = requestID else { return }
      if let reply = await SimulationRequest.confirmation(for: id, success: "Simulation cleared.") {
        controlStatus = reply
      }
    }
  }

  private func send(_ action: [String: Any]) {
    do {
      requestID = try SimulationRequest.submit(action)
      controlStatus = "Waiting for Mac…"
    } catch {
      controlStatus = error.localizedDescription
    }
  }
}
