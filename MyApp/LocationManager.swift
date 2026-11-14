import Combine
import CoreLocation
import Foundation

final class LocationManager: NSObject,
  ObservableObject,
  CLLocationManagerDelegate
{

  private let manager = CLLocationManager()

  @Published var latitude: Double?
  @Published var longitude: Double?
  @Published var source: CLLocationSourceInformation?
  @Published var fixTime: Date?
  @Published var errorMessage: String?

  override init() {
    super.init()
    manager.delegate = self
    manager.requestWhenInUseAuthorization()
  }

  func locationManagerDidChangeAuthorization(
    _ manager: CLLocationManager
  ) {
    if manager.authorizationStatus == .authorizedWhenInUse
      || manager.authorizationStatus == .authorizedAlways
    {
      manager.startUpdatingLocation()
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last else { return }

    errorMessage = nil
    latitude = location.coordinate.latitude
    longitude = location.coordinate.longitude

    source = location.sourceInformation
    fixTime = location.timestamp
  }

  func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    errorMessage = error.localizedDescription
  }
}
