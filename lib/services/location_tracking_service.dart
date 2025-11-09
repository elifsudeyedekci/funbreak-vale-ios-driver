import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationTrackingService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static Timer? _locationTimer;
  static StreamSubscription<Position>? _positionStream;
  static bool _isTracking = false;
  static Position? _lastKnownPosition;
  
  // Konum takibini başlat
  static Future<bool> startLocationTracking() async {
    try {
      if (_isTracking) {
        print('Konum takibi zaten aktif');
        return true;
      }
      
      // Konum izinlerini kontrol et
      bool hasPermission = await _checkLocationPermissions();
      if (!hasPermission) {
        print('Konum izni yok');
        return false;
      }
      
      // Şoför ID'sini al
      String? driverId = await _getDriverId();
      if (driverId == null) {
        print('Şoför ID bulunamadı');
        return false;
      }
      
      print('Konum takibi başlatılıyor - Şoför ID: $driverId');
      
      // Konum stream'ini başlat
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 10 metre hareket ettiğinde güncelle
      );
      
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        _lastKnownPosition = position;
        _sendLocationToServer(driverId, position);
      });
      
      // Periyodik güncelleme timer'ı (30 saniyede bir)
      _locationTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
        if (_lastKnownPosition != null) {
          await _sendLocationToServer(driverId, _lastKnownPosition!);
        }
      });
      
      _isTracking = true;
      print('Konum takibi başlatıldı');
      return true;
      
    } catch (e) {
      print('Konum takibi başlatma hatası: $e');
      return false;
    }
  }
  
  // Konum takibini durdur
  static Future<void> stopLocationTracking() async {
    try {
      _locationTimer?.cancel();
      _locationTimer = null;
      
      await _positionStream?.cancel();
      _positionStream = null;
      
      _isTracking = false;
      _lastKnownPosition = null;
      
      print('Konum takibi durduruldu');
    } catch (e) {
      print('Konum takibi durdurma hatası: $e');
    }
  }
  
  // Konum izinlerini kontrol et
  static Future<bool> _checkLocationPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Konum servisi kapalı');
        return false;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Konum izni reddedildi');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        print('Konum izni kalıcı olarak reddedildi');
        return false;
      }
      
      return true;
    } catch (e) {
      print('Konum izni kontrol hatası: $e');
      return false;
    }
  }
  
  // Şoför ID'sini al
  static Future<String?> _getDriverId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('driver_id') ?? prefs.getString('user_id');
    } catch (e) {
      print('Şoför ID alma hatası: $e');
      return null;
    }
  }
  
  // Konumu sunucuya gönder
  static Future<void> _sendLocationToServer(String driverId, Position position) async {
    try {
      print('Konum gönderiliyor: ${position.latitude}, ${position.longitude}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/update_driver_location.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': int.tryParse(driverId) ?? driverId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
          'is_online': 1,
        }),
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('Konum başarıyla gönderildi');
        } else {
          print('Konum gönderme hatası: ${data['message']}');
        }
      } else {
        print('HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('Konum gönderme hatası: $e');
    }
  }
  
  // Mevcut konumu al
  static Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await _checkLocationPermissions();
      if (!hasPermission) {
        return null;
      }
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      _lastKnownPosition = position;
      return position;
    } catch (e) {
      print('Mevcut konum alma hatası: $e');
      return null;
    }
  }
  
  // Takip durumunu kontrol et
  static bool get isTracking => _isTracking;
  
  // Son bilinen konum
  static Position? get lastKnownPosition => _lastKnownPosition;
  
  // Şoför durumunu güncelle (online/offline)
  static Future<bool> updateDriverStatus(bool isOnline) async {
    try {
      String? driverId = await _getDriverId();
      if (driverId == null) {
        return false;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/update_driver_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': driverId,
          'is_online': isOnline,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('Şoför durumu güncellendi: ${isOnline ? "Online" : "Offline"}');
          
          // Online olduğunda konum takibini başlat
          if (isOnline) {
            await startLocationTracking();
          } else {
            await stopLocationTracking();
          }
          
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('Şoför durumu güncelleme hatası: $e');
      return false;
    }
  }
  
  // Manuel konum gönder
  static Future<bool> sendCurrentLocation() async {
    try {
      Position? position = await getCurrentLocation();
      if (position == null) {
        return false;
      }
      
      String? driverId = await _getDriverId();
      if (driverId == null) {
        return false;
      }
      
      await _sendLocationToServer(driverId, position);
      return true;
    } catch (e) {
      print('Manuel konum gönderme hatası: $e');
      return false;
    }
  }
  
  // Servisi temizle
  static Future<void> dispose() async {
    await stopLocationTracking();
    print('Location tracking service temizlendi');
  }
}
