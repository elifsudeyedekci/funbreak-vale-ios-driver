import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  // CANLI PANEL İÇİN GERÇEK API URL - DÜZELTİLMİŞ!
  static const String _baseUrl = 'https://admin.funbreakvale.com/api';
  Timer? _locationTimer;
  bool _isTracking = false;
  String? _currentDriverId;
  bool _isOnlineStatus = false;

  bool get isTracking => _isTracking;

  // ZORUNLU KONUM İZNİ SİSTEMİ - UYGULAMAYI KULLANAMAZ!
  Future<bool> checkAndEnforceLocationPermission() async {
    try {
      debugPrint('🔒 === ZORUNLU KONUM İZNİ KONTROLÜ BAŞLADI ===');
      
      // 1. MEVCUT İZİN DURUMUNU KONTROL ET
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('📍 Mevcut konum izni: $permission');
      
      // 2. KONUM SERVİSİ AKTİF Mİ?
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('📶 Konum servisi aktif: $serviceEnabled');
      
      if (!serviceEnabled) {
        debugPrint('❌ Konum servisi kapalı - ZORUNLU AÇTILMALI!');
        await _showLocationServiceDialog();
        return false;
      }
      
      // 3. İZİN DURUMU KONTROLÜ VE AGRESİF İSTEME
      if (permission == LocationPermission.denied) {
        debugPrint('🚀 Konum izni isteniyor - AGRESİF YÖNTEM!');
        
        // 3 KERE DENE!
        for (int attempt = 1; attempt <= 3; attempt++) {
          debugPrint('🔄 Konum izni deneme #$attempt');
          
          permission = await Geolocator.requestPermission();
          debugPrint('📊 Deneme #$attempt sonucu: $permission');
          
          if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
            debugPrint('✅ KONUM İZNİ VERİLDİ!');
            break;
          }
          
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }
      
      // 4. SON KONTROL - İZİN VAR MI?
      if (permission == LocationPermission.denied) {
        debugPrint('❌ KONUM İZNİ HALA YOK - UYGULAMA KULLANILMASIN!');
        await _showLocationDeniedDialog();
        return false;
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ KONUM İZNİ KALICI REDDİ - UYGULAMA KULLANILMASIN!');
        await _showLocationPermanentlyDeniedDialog();
        return false;
      }
      
      // 5. ARKA PLAN İZNİ KONTROLÜ
      if (permission == LocationPermission.whileInUse) {
        debugPrint('🟡 Sadece uygulama açıkken konum - ARKA PLAN İZNİ İSTENİYOR!');
        permission = await Geolocator.requestPermission();
        
        if (permission != LocationPermission.always) {
          debugPrint('⚠️ Arka plan konum izni yok - sınırlı çalışma');
        }
      }
      
      debugPrint('✅ === KONUM İZNİ KONTROLÜ BAŞARILI ===');
      return true;
      
    } catch (e) {
      debugPrint('❌ Konum izni kontrol hatası: $e');
      return false;
    }
  }
  
  Future<void> startLocationTracking() async {
    if (_isTracking) return;

    // ZORUNLU KONUM İZNİ KONTROLÜ - GEÇMEZSE UYGULAMA ÇALIŞMAZ!
    bool hasPermission = await checkAndEnforceLocationPermission();
    if (!hasPermission) {
      debugPrint('❌ KONUM İZNİ YOK - TAKIP BAŞLATILAMADI!');
      return;
    }

    _isTracking = true;
    
    // HIZLANDIRILMIŞ KONUM GÜNCELLEME: 10 SANİYE!
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _sendLocation();
    });
    
    debugPrint('⚡ Hızlı konum takibi: 10 saniyede bir panele gönderilecek');

    // İlk konumu hemen gönder
    _sendLocation();
    debugPrint('📍 Konum takibi başlatıldı');
  }

  Future<void> stopLocationTracking() async {
    _locationTimer?.cancel();
    _locationTimer = null;
    _isTracking = false;
    debugPrint('📍 Konum takibi durduruldu');
  }

  Future<void> _sendLocation() async {
    try {
      // Mevcut konumu al
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Şoför ID'sini al
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      
      if (driverId == null) {
        debugPrint('Şoför ID bulunamadı');
        return;
      }

      // AKTİF YOLCULUK BİLGİLERİNİ AL
      final activeRideInfo = await _getCurrentActiveRideInfo();
      
      // KRİTİK: is_online PARAMETRES İNİ HİÇ GÖNDERME - BACKEND MEVCUT DEĞERİ KORUR!
      final requestBody = {
        'driver_id': int.parse(driverId),
        'latitude': position.latitude,
        'longitude': position.longitude,
        // is_online ve is_available PARAMETRELERİ KALDIRILDI! ✅
        'last_active': DateTime.now().toIso8601String(),
        'timestamp': DateTime.now().toIso8601String(),
        'accuracy': position.accuracy,
        'speed': position.speed >= 0 ? position.speed : 0,
        'heading': position.heading >= 0 ? position.heading : 0,
        // AKTİF YOLCULUK BİLGİLERİ
        'active_ride': activeRideInfo,
        'has_active_ride': activeRideInfo != null,
        'ride_status': activeRideInfo?['status'] ?? 'none',
        'customer_info': activeRideInfo?['customer_info'],
        'route_info': activeRideInfo?['route_info'],
        'eta_info': activeRideInfo?['eta_info'],
      };
      
      debugPrint('📤 KONUM API\'ye GÖNDERİLİYOR - is_online parametresi YOK (backend mevcut değeri korur)');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/update_driver_location.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Konum güncellendi (is_online korundu)');
        } else {
          debugPrint('❌ Konum güncelleme hatası: ${data['message']}');
        }
      }
    } catch (e) {
      debugPrint('❌ Konum gönderme hatası: $e');
    }
  }

  // ÇEVRİMİÇİ DURUMU YÖNETİMİ - YENİ FONKSİYONLAR!
  Future<void> setOnlineStatus(bool isOnline) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_online', isOnline);
      _isOnlineStatus = isOnline;
      
      debugPrint('🔄 Çevrimiçi durumu değiştirildi: $isOnline');
      
      // Hemen panele bildir
      if (_currentDriverId != null) {
        await _sendStatusUpdate();
      }
    } catch (e) {
      debugPrint('❌ Çevrimiçi durum değiştirme hatası: $e');
    }
  }
  
  Future<void> setAvailabilityStatus(bool isAvailable) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_available', isAvailable);
      
      debugPrint('🔄 Müsaitlik durumu değiştirildi: $isAvailable');
      
      // Hemen panele bildir
      if (_currentDriverId != null) {
        await _sendStatusUpdate();
      }
    } catch (e) {
      debugPrint('❌ Müsaitlik durum değiştirme hatası: $e');
    }
  }
  
  // DURUM GÜNCELLEMESİ (KONUM OLMADAN)
  Future<void> _sendStatusUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      final isOnline = prefs.getBool('driver_is_online') ?? false;  // DOĞRU KEY + DEFAULT FALSE!
      final isAvailable = prefs.getBool('driver_is_available') ?? false;  // DOĞRU KEY + DEFAULT FALSE!
      
      if (driverId == null) return;
      
      final response = await http.post(
        Uri.parse('$_baseUrl/update_driver_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': int.parse(driverId),
          'is_online': isOnline,
          'is_available': isAvailable,
          'last_active': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Durum güncellemesi panele gönderildi!');
        }
      }
    } catch (e) {
      debugPrint('❌ Durum güncelleme hatası: $e');
    }
  }
  
  // ÇEVRİMDIŞI OLURKEN PANELE BİLDİR
  Future<void> setOfflineAndStop() async {
    await setOnlineStatus(false);
    await setAvailabilityStatus(false);
    await stopLocationTracking();
    debugPrint('📴 Vale çevrimdışı oldu ve takip durduruldu');
  }

  // KONUM İZNİ DIALOG'LARI - ZORUNLU SİSTEM!
  
  Future<void> _showLocationServiceDialog() async {
    debugPrint('⚠️ Konum servisi kapalı dialog gösterilmeli');
    // Bu dialog UI'da gösterilmeli: "Konum servisini açmanız gerekiyor"
  }
  
  Future<void> _showLocationDeniedDialog() async {
    debugPrint('❌ Konum izni reddedildi dialog gösterilmeli');
    // Bu dialog UI'da gösterilmeli: "Konum izni olmadan uygulama kullanılamaz"
  }
  
  Future<void> _showLocationPermanentlyDeniedDialog() async {
    debugPrint('🚫 Konum izni kalıcı reddedildi dialog gösterilmeli');
    // Bu dialog UI'da gösterilmeli: "Ayarlardan konum iznini açmanız gerekiyor"
  }
  
  // ARKA PLAN KONUM TAKİBİ YÖNETİMİ
  Future<void> enableBackgroundLocationTracking() async {
    try {
      debugPrint('🌙 Arka plan konum takibi aktifleştiriliyor...');
      
      // Background location için özel ayarlar
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 10 metre hareket ettiğinde güncelle
      );
      
      // Background stream başlat
      Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) {
          debugPrint('🎯 Arka plan konum güncellemesi: ${position.latitude}, ${position.longitude}');
          _sendLocationFromBackground(position);
        },
        onError: (error) {
          debugPrint('❌ Arka plan konum hatası: $error');
        },
      );
      
      debugPrint('✅ Arka plan konum takibi başlatıldı');
    } catch (e) {
      debugPrint('❌ Arka plan konum takibi hatası: $e');
    }
  }
  
  // ARKA PLAN KONUM GÖNDERİMİ
  Future<void> _sendLocationFromBackground(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      
      if (driverId == null) return;
      
      // Sadece konum güncelle (arka plan için minimal veri)
      final response = await http.post(
        Uri.parse('$_baseUrl/update_driver_location.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': int.parse(driverId),
          'latitude': position.latitude,
          'longitude': position.longitude,
          'is_background': true,
          'timestamp': DateTime.now().toIso8601String(),
          'accuracy': position.accuracy,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        debugPrint('🌙 Arka plan konum başarıyla gönderildi');
      }
    } catch (e) {
      debugPrint('❌ Arka plan konum gönderme hatası: $e');
    }
  }

  // AKTİF YOLCULUK BİLGİLERİNİ ALMA - SÜPER ÖZELLİK!
  Future<Map<String, dynamic>?> _getCurrentActiveRideInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      
      if (driverId == null) return null;
      
      // Panel API'den aktif yolculuk bilgilerini al
      final response = await http.post(
        Uri.parse('$_baseUrl/get_driver_active_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': int.parse(driverId),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['has_active_ride'] == true) {
          final rideInfo = data['ride_info'];
          
          // TAHMİNİ VARIŞ HESAPLA (GERÇEK ZAMANLI TRAFİK!)
          Map<String, dynamic>? etaInfo = await _calculateETA(
            rideInfo['destination_latitude'],
            rideInfo['destination_longitude'],
          );
          
          return {
            'ride_id': rideInfo['id'],
            'customer_name': rideInfo['customer_name'] ?? 'Müşteri',
            'customer_phone': rideInfo['customer_phone'] ?? '',
            'pickup_address': rideInfo['pickup_address'] ?? '',
            'destination_address': rideInfo['destination_address'] ?? '',
            'status': rideInfo['status'] ?? 'unknown', // accepted, started, arrived, etc.
            'service_type': rideInfo['service_type'] ?? 'vale',
            'estimated_price': double.tryParse((rideInfo['estimated_price'] ?? 0).toString()) ?? 0.0,
            'customer_info': {
              'name': rideInfo['customer_name'],
              'phone': rideInfo['customer_phone'],
              'rating': rideInfo['customer_rating'] ?? 5.0,
            },
            'route_info': {
              'pickup': rideInfo['pickup_address'],
              'destination': rideInfo['destination_address'],
              'pickup_lat': rideInfo['pickup_latitude'],
              'pickup_lng': rideInfo['pickup_longitude'],
              'destination_lat': rideInfo['destination_latitude'],
              'destination_lng': rideInfo['destination_longitude'],
            },
            'eta_info': etaInfo,
            'status_text': _getRideStatusText(rideInfo['status'], serviceType: rideInfo['service_type']),
            'status_color': _getRideStatusColor(rideInfo['status']),
          };
        }
      }
      
      return null; // Aktif yolculuk yok
    } catch (e) {
      debugPrint('❌ Aktif yolculuk bilgisi alma hatası: $e');
      return null;
    }
  }
  
  // TAHMİNİ VARIŞ HESAPLAMA - TRAFİK DAHİL!
  Future<Map<String, dynamic>?> _calculateETA(double destLat, double destLng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentLat = prefs.getDouble('last_latitude') ?? 0.0;
      final currentLng = prefs.getDouble('last_longitude') ?? 0.0;
      
      if (currentLat == 0.0 || currentLng == 0.0) return null;
      
      // Google Directions API ile gerçek zamanlı trafik hesabı
      final response = await http.get(
        Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=$currentLat,$currentLng'
          '&destination=$destLat,$destLng'
          '&departure_time=now'
          '&traffic_model=best_guess'
          '&key=AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY'
        ),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final legs = route['legs'][0];
          
          final normalDuration = legs['duration']['value']; // saniye
          final trafficDuration = legs['duration_in_traffic']?['value'] ?? normalDuration;
          final distance = legs['distance']['value']; // metre
          
          final etaTime = DateTime.now().add(Duration(seconds: trafficDuration));
          
          return {
            'eta_time': etaTime.toIso8601String(),
            'eta_formatted': '${etaTime.hour.toString().padLeft(2, '0')}:${etaTime.minute.toString().padLeft(2, '0')}',
            'duration_minutes': (trafficDuration / 60).round(),
            'distance_km': (distance / 1000).toStringAsFixed(1),
            'traffic_delay_minutes': ((trafficDuration - normalDuration) / 60).round(),
            'traffic_status': _getTrafficStatus(trafficDuration, normalDuration),
          };
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ ETA hesaplama hatası: $e');
      return null;
    }
  }
  
  // YOLCULUK DURUM METNİ - SERVİS TİPİNE GÖRE!
  String _getRideStatusText(String? status, {String? serviceType}) {
    // SERVİS TİPİNE GÖRE TEMEL METİN
    String servicePrefix = '';
    switch (serviceType) {
      case 'hourly':
        servicePrefix = 'Saatlik ';
        break;
      case 'vale':
        servicePrefix = 'Vale ';
        break;
      case 'transfer':
        servicePrefix = 'Transfer ';
        break;
      case 'airport':
        servicePrefix = 'Havalimanı ';
        break;
      default:
        servicePrefix = 'Vale ';
    }
    
    switch (status) {
      case 'accepted': return servicePrefix + 'Kabul Edildi';
      case 'started': return servicePrefix + 'İşte'; // "Saatlik İşte" veya "Vale İşte"
      case 'arrived': return 'Müşteriye Varıldı';
      case 'waiting': return servicePrefix + 'Beklemede';
      case 'in_progress': return servicePrefix + 'Yolda';
      case 'near_completion': return 'Hedefe Yakın';
      case 'completed': return 'Tamamlandı';
      default: return servicePrefix + 'İşte';
    }
  }
  
  // YOLCULUK DURUM RENGİ
  String _getRideStatusColor(String? status) {
    switch (status) {
      case 'accepted': return '#ffc107'; // Sarı
      case 'started': return '#17a2b8'; // Mavi
      case 'arrived': return '#28a745'; // Yeşil
      case 'waiting': return '#fd7e14'; // Turuncu
      case 'in_progress': return '#007bff'; // Mavi
      case 'near_completion': return '#20c997'; // Teal
      case 'completed': return '#28a745'; // Yeşil
      default: return '#6c757d'; // Gri
    }
  }
  
  // TRAFİK DURUMU
  String _getTrafficStatus(int trafficDuration, int normalDuration) {
    double ratio = trafficDuration / normalDuration;
    if (ratio > 1.5) return 'Yoğun Trafik';
    if (ratio > 1.2) return 'Orta Trafik';
    return 'Akıcı Trafik';
  }

  void dispose() {
    stopLocationTracking();
  }
}