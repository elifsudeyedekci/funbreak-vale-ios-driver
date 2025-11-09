import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class RealTimeTrackingProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  Timer? _locationTimer;
  List<LatLng> _traveledRoute = [];
  double _totalDistance = 0.0;
  double _basePricePerKm = 10.0;
  double _basePrice = 50.0;
  bool _isTracking = false;
  String? _currentRideId;
  LatLng? _lastKnownPosition;
  DateTime? _rideStartTime;
  List<Map<String, dynamic>> _specialLocations = [];
  
  // Getters
  List<LatLng> get traveledRoute => _traveledRoute;
  double get totalDistance => _totalDistance;
  double get currentPrice => _basePrice + (_totalDistance * _basePricePerKm);
  bool get isTracking => _isTracking;

  // Admin panelden fiyatlandırma ayarlarını yükle
  Future<void> loadPricingSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/pricing_settings.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _basePricePerKm = double.parse(data['price_per_km'].toString());
          _basePrice = double.parse(data['base_price'].toString());
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Fiyatlandırma ayarları yükleme hatası: $e');
    }
  }

  // Yolculuk takibini başlat
  Future<void> startRideTracking(String rideId, String driverId) async {
    if (_isTracking) return;

    _currentRideId = rideId;
    _isTracking = true;
    _traveledRoute.clear();
    _totalDistance = 0.0;
    _rideStartTime = DateTime.now();
    
    // Admin panele yolculuk başladı bilgisi gönder
    await _updateRideStatus(rideId, 'started');
    
    // Konum takibini başlat (her 5 saniyede bir)
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _trackCurrentLocation(driverId);
    });
    
    notifyListeners();
  }

  // Yolculuk takibini durdur ve final fiyatı hesapla
  Future<double> stopRideTracking() async {
    if (!_isTracking || _currentRideId == null) return currentPrice;

    _isTracking = false;
    _locationTimer?.cancel();
    
    // Final fiyatı hesapla
    double finalPrice = _calculateFinalPrice();
    
    // Admin panele final fiyat ve mesafe bilgisi gönder
    await _updateRideFinalData(_currentRideId!, finalPrice, _totalDistance);
    
    _currentRideId = null;
    notifyListeners();
    
    return finalPrice;
  }

  // Anlık konum takibi
  Future<void> _trackCurrentLocation(String driverId) async {
    try {
      // Mevcut konumu al
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      LatLng currentLocation = LatLng(position.latitude, position.longitude);
      
      // Eğer önceki konum varsa mesafe hesapla
      if (_lastKnownPosition != null) {
        double segmentDistance = _calculateDistance(
          _lastKnownPosition!,
          currentLocation,
        );
        
        // Minimum 10 metre hareket varsa kaydet (GPS hatasını önlemek için)
        if (segmentDistance > 0.01) { // 10 metre
          _totalDistance += segmentDistance;
          _traveledRoute.add(currentLocation);
          
          // Admin panele anlık konum ve mesafe gönder
          await _sendLocationUpdate(driverId, currentLocation, _totalDistance);
          
          notifyListeners();
        }
      } else {
        // İlk konum
        _traveledRoute.add(currentLocation);
      }
      
      _lastKnownPosition = currentLocation;
      
    } catch (e) {
      debugPrint('Konum takip hatası: $e');
    }
  }

  // Admin panele anlık konum ve mesafe güncelleme
  Future<void> _sendLocationUpdate(String driverId, LatLng location, double totalDistance) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/update_ride_tracking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': _currentRideId,
          'driver_id': driverId,
          'current_lat': location.latitude,
          'current_lng': location.longitude,
          'total_distance': totalDistance,
          'current_price': currentPrice,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Konum güncelleme hatası: $e');
    }
  }

  // Yolculuk durumu güncelle
  Future<void> _updateRideStatus(String rideId, String status) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/update_ride_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Ride durum güncelleme hatası: $e');
    }
  }

  // Final fiyat ve mesafe verilerini gönder
  Future<void> _updateRideFinalData(String rideId, double finalPrice, double totalDistance) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/complete_ride_tracking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'final_price': finalPrice,
          'total_distance': totalDistance,
          'travel_time': _rideStartTime != null 
              ? DateTime.now().difference(_rideStartTime!).inMinutes 
              : 0,
          'route_points': _traveledRoute.map((point) => {
            'lat': point.latitude,
            'lng': point.longitude,
          }).toList(),
          'completed_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Final veri gönderme hatası: $e');
    }
  }

  // Final fiyat hesapla (gerçek mesafe + konum ek ücretleri)
  double _calculateFinalPrice() {
    double finalPrice = _basePrice + (_totalDistance * _basePricePerKm);
    
    // Rotadaki özel konumlar için ek ücret hesapla
    for (LatLng point in _traveledRoute) {
      finalPrice += _calculateLocationExtraFee(point);
    }
    
    return finalPrice;
  }

  // Koordinatlara göre ek ücret hesapla
  double _calculateLocationExtraFee(LatLng coords) {
    double extraFee = 0.0;
    
    for (var location in _specialLocations) {
      final locationLat = double.parse(location['latitude'].toString());
      final locationLng = double.parse(location['longitude'].toString());
      final radius = double.parse(location['radius'].toString()); // km cinsinden
      
      final distance = _calculateDistance(
        LatLng(coords.latitude, coords.longitude),
        LatLng(locationLat, locationLng),
      );
      
      if (distance <= radius) {
        extraFee += double.parse(location['extra_fee'].toString());
        break; // Bir kez ek ücret al
      }
    }
    
    return extraFee;
  }

  // İki nokta arası mesafe hesapla (Haversine formula)
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km
    
    double dLat = _degreesToRadians(point2.latitude - point1.latitude);
    double dLon = _degreesToRadians(point2.longitude - point1.longitude);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(point1.latitude)) * 
        math.cos(_degreesToRadians(point2.latitude)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }
}
