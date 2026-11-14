import MapKit
import SwiftUI

private struct CampusStop: Codable, Equatable {
  var name: String
  var clock: String
  var lat: Double
  var lon: Double
}

private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

struct RoutineView: View {
  @State private var week: [String: [CampusStop]] = [:]
  @State private var day = "Mon"
  @State private var days = 7
  @State private var editor: StopSelection?
  @State private var info = ""
  @AppStorage("campusRequest") private var pending = ""
  @AppStorage("campusStopping") private var stopping = false
  private let file = URL.documentsDirectory.appendingPathComponent("campus-week-v1.json")

  var body: some View {
    NavigationStack {
      Form {
        Section("Campus stops · New York time") {
          Picker("Day", selection: $day) {
            ForEach(weekdays, id: \.self) { Text($0).tag($0) }
          }
          let stops = week[day] ?? []
          ForEach(stops.indices, id: \.self) { index in
            Button {
              editor = StopSelection(index: index, stop: stops[index])
            } label: {
              HStack {
                Text(stops[index].clock).monospacedDigit()
                Text(stops[index].name)
              }
            }
          }
          .onDelete { offsets in
            var items = stops
            items.remove(atOffsets: offsets)
            save(items)
          }
          Button("Add stop") {
            let base = stops.last
            editor = StopSelection(
              index: nil,
              stop: CampusStop(
                name: "", clock: "12:00", lat: base?.lat ?? 43.08579, lon: base?.lon ?? -77.66898))
          }
        }
        Section("Playback") {
          Stepper("Calendar days: \(days)", value: $days, in: 1...30)
          Button("Start routine") { send(stop: false) }
          Button("Stop simulation") { send(stop: true) }
          if !info.isEmpty { Text(info).font(.footnote) }
        }
      }
      .navigationTitle("Routine")
      .onAppear {
        guard week.isEmpty else { return }
        do {
          let source =
            FileManager.default.fileExists(atPath: file.path)
            ? file : Bundle.main.url(forResource: "CampusWeek", withExtension: "json")
          guard let source else { throw CocoaError(.fileNoSuchFile) }
          week = try JSONDecoder().decode(
            [String: [CampusStop]].self, from: Data(contentsOf: source))
        } catch { info = error.localizedDescription }
      }
      .sheet(item: $editor) { selection in
        StopEditor(stop: selection.stop) { value in
          var items = week[day] ?? []
          if let index = selection.index { items[index] = value } else { items.append(value) }
          guard Set(items.map(\.clock)).count == items.count else {
            return "Choose a different arrival time."
          }
          return save(items.sorted { $0.clock < $1.clock }) ? nil : info
        }
      }
      .task(id: pending) {
        guard !pending.isEmpty else { return }
        let id = pending
        let success = stopping ? "Simulation stopped." : "Routine started."
        if let reply = await SimulationRequest.confirmation(for: id, success: success) {
          info = reply
        }
      }
    }
  }

  @discardableResult private func save(_ stops: [CampusStop]) -> Bool {
    var updated = week
    updated[day] = stops
    do {
      try JSONEncoder().encode(updated).write(to: file, options: .atomic)
      week = updated
      return true
    } catch {
      info = error.localizedDescription
      return false
    }
  }

  private func send(stop: Bool) {
    do {
      var request: [String: Any] = [:]
      if stop {
        request["stop"] = true
      } else {
        request["week"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(week))
        request["days"] = days
      }
      let id = try SimulationRequest.submit(request)
      stopping = stop
      info = "Waiting for Mac…"
      pending = id
    } catch { info = error.localizedDescription }
  }
}

private struct StopSelection: Identifiable {
  let id = UUID()
  let index: Int?
  let stop: CampusStop
}

private struct StopEditor: View {
  @Environment(\.dismiss) var dismiss
  @State var stop: CampusStop
  var commit: (CampusStop) -> String?
  @State private var error = ""
  var body: some View {
    NavigationStack {
      Form {
        TextField("Stop name", text: $stop.name)
        TextField("Arrival (HH:mm)", text: $stop.clock)
        Section("Tap the map to place the stop") {
          let pin = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon)
          MapReader { proxy in
            Map(
              initialPosition: .region(
                MKCoordinateRegion(center: pin, latitudinalMeters: 750, longitudinalMeters: 750))
            ) {
              Marker("Stop", coordinate: pin)
            }
            .frame(height: 270)
            .onTapGesture { point in
              if let c = proxy.convert(point, from: .local) {
                stop.lat = c.latitude
                stop.lon = c.longitude
              }
            }
          }
        }
        if !error.isEmpty { Text(error) }
      }
      .navigationTitle("Campus stop")
      .toolbar {
        Button("Cancel") { dismiss() }
        Button("Save") {
          stop.name = stop.name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !stop.name.isEmpty,
            stop.clock.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression)
              != nil
          else {
            error = "Enter a name and a 24-hour time such as 09:30."
            return
          }
          if let problem = commit(stop) { error = problem } else { dismiss() }
        }
      }
    }
  }
}
