import Foundation

enum SimulationRequest {
  static func submit(_ action: [String: Any]) throws -> String {
    let id = UUID().uuidString
    var payload = action
    payload["id"] = id
    payload["created"] = Date().timeIntervalSince1970
    let url = URL.documentsDirectory.appendingPathComponent("drive-request.json")
    try JSONSerialization.data(withJSONObject: payload).write(to: url, options: .atomic)
    return id
  }

  static func confirmation(for id: String, success: String) async -> String? {
    let url = URL.documentsDirectory.appendingPathComponent("drive-status.json")
    for _ in 0..<35 {
      guard !Task.isCancelled else { return nil }
      if let data = try? Data(contentsOf: url),
        let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        result["id"] as? String == id
      {
        return result["message"] as? String
          ?? (result["ok"] as? Bool == true ? success : "Request failed. Check the Mac helper.")
      }
      do { try await Task.sleep(for: .seconds(1)) } catch { return nil }
    }
    return "No confirmation. Check the Mac helper and connection, then retry."
  }
}
