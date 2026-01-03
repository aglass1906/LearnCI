import Foundation
import CoreLocation
import MapKit
import Observation

@Observable
class LocationManager: NSObject {
    var locationString: String?
    var errorMessage: String?
    var isLoading: Bool = false
    
    // Authorization status can be exposed if needed
    var isAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // City level accuracy
    }
    
    func requestLocationAndAddress() {
        isLoading = true
        errorMessage = nil
        
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Location access denied. Please enable it in Settings."
            isLoading = false
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        @unknown default:
            locationManager.requestWhenInUseAuthorization()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if isLoading {
               // If we were waiting for permission to request location
               manager.requestLocation()
            }
        } else if status == .denied || status == .restricted {
            if isLoading {
                isLoading = false
                errorMessage = "Location access denied."
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        
        // Use CLGeocoder for reverse geocoding (not deprecated)
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Failed to find address: \(error.localizedDescription)"
                    return
                }
                
                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? placemark.administrativeArea ?? ""
                    let country = placemark.country ?? ""
                    
                    if !city.isEmpty && !country.isEmpty {
                        self.locationString = "\(city), \(country)"
                    } else {
                        self.locationString = city.isEmpty ? country : city
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        errorMessage = "Failed to get location: \(error.localizedDescription)"
    }
}
