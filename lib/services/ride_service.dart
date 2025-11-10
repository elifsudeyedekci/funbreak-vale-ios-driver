import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';

class RideService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static Timer? _rideCheckTimer;
  static StreamController<Map<String, dynamic>>? _rideStreamController;
  
  // Ride stream getter
  static Stream<Map<String, dynamic>> get rideStream {
    _rideStreamController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _rideStreamController!.stream;
  }
  
  // Talep dinlemeyi başlat
  static Future<void> startListeningForRides(int driverId) async {
    print('🎧 SÜRÜCÜ TALEP DİNLEME BAŞLATILDI - Driver ID: $driverId');
    
    // Firebase messaging listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 YENİ TALEP BİLDİRİMİ ALINDI!');
      print('Başlık: ${message.notification?.title}');
      print('Mesaj: ${message.notification?.body}');
      print('Data: ${message.data}');
      
      if (message.data['type'] == 'new_ride_request') {
        _handleNewRideRequest(message.data);
      }
    });
    
    // Periyodik kontrol (her 10 saniyede bir)
    _rideCheckTimer?.cancel();
    _rideCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkForNewRides(driverId);
    });
  }
  
  // Talep dinlemeyi durdur
  static void stopListeningForRides() {
    print('🛑 SÜRÜCÜ TALEP DİNLEME DURDURULDU');
    _rideCheckTimer?.cancel();
  }
  
  // Yeni talep işleme
  static void _handleNewRideRequest(Map<String, dynamic> data) {
    try {
      print('🔍 SÜRÜCÜ: Yeni talep işleniyor - Raw data: $data');
      
      final rideData = {
        'ride_id': int.tryParse(data['id']?.toString() ?? '0') ?? 0,
        'pickup_location': data['pickup_address'] ?? '',
        'destination': data['destination_address'] ?? '',
        'service_type': data['ride_type'] ?? '',
        'estimated_price': double.tryParse(data['estimated_price']?.toString() ?? '0') ?? 0.0,
        'customer_name': data['customer_name'] ?? '',
        'customer_phone': data['customer_phone'] ?? '',
        'distance': data['distance'] ?? '',
        'status': data['status'] ?? '',
      };
      
      print('🚗 SÜRÜCÜ: İşlenmiş talep verisi: $rideData');
      
      // Stream'e gönder
      if (_rideStreamController != null && !_rideStreamController!.isClosed) {
        _rideStreamController!.add(rideData);
        print('✅ SÜRÜCÜ: Talep stream\'e gönderildi');
      } else {
        print('❌ SÜRÜCÜ: Stream controller kapalı');
      }
    } catch (e) {
      print('❌ SÜRÜCÜ: Yeni talep işleme hatası: $e');
    }
  }
  
  // Yeni talepleri kontrol et
  static Future<void> _checkForNewRides(int driverId) async {
    try {
      print('🔍 SÜRÜCÜ: Talep kontrolü başlıyor - Driver ID: $driverId');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_available_rides_for_driver.php?driver_id=$driverId'),
        headers: {'Content-Type': 'application/json'},
      );

      print('📡 SÜRÜCÜ API RESPONSE: ${response.statusCode}');
      print('📡 SÜRÜCÜ API BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📊 SÜRÜCÜ: API Success: ${data['success']}, Rides: ${data['rides']?.length ?? 0}');
        print('📊 SÜRÜCÜ: Raw API Response: ${response.body}');
        
        if (data['success'] == true && data['rides'] != null) {
          print('✅ SÜRÜCÜ: ${data['rides'].length} talep bulundu');
          for (var ride in data['rides']) {
            print('🚗 SÜRÜCÜ: Talep işleniyor - ID: ${ride['id']}');
            _handleNewRideRequest(ride);
          }
        } else {
          print('ℹ️ SÜRÜCÜ: Talep bulunamadı - Success: ${data['success']}, Rides: ${data['rides']}');
        }
      } else {
        print('❌ SÜRÜCÜ API HATASI: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ TALEP KONTROL HATASI: $e');
    }
  }
  
  // Talebi kabul et
  static Future<Map<String, dynamic>> acceptRideRequest(int rideId, int driverId) async {
    try {
      print('✅ TALEP KABUL EDİLİYOR - Ride: $rideId, Driver: $driverId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/accept_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'driver_id': driverId,
        }),
      );

      print('📝 ACCEPT RESPONSE: ${response.statusCode}');
      print('📝 RESPONSE BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ TALEP BAŞARIYLA KABUL EDİLDİ!');
          
          // Müşteriye bildirim gönder
          await _notifyCustomer(rideId, 'accepted');
          
          return data;
        } else {
          throw Exception(data['message'] ?? 'Talep kabul edilemedi');
        }
      } else {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ACCEPT RIDE ERROR: $e');
      throw Exception('Talep kabul etme hatası: $e');
    }
  }
  
  // Talebi reddet
  static Future<bool> rejectRideRequest(int rideId, int driverId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reject_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'driver_id': driverId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ REJECT RIDE ERROR: $e');
      return false;
    }
  }
  
  // Yolculuğu başlat
  static Future<bool> startRide(int rideId, int driverId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/start_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'driver_id': driverId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _notifyCustomer(rideId, 'started');
          await _notifyRidePersistence(rideId);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ START RIDE ERROR: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> fetchRideStatus(String rideId, String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_driver_active_ride.php?driver_id=$driverId&ride_id=$rideId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('❌ FETCH RIDE STATUS HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        if (data['ride_info'] != null) {
          return Map<String, dynamic>.from(data['ride_info']);
        }
        if (data['ride'] != null) {
          return Map<String, dynamic>.from(data['ride']);
        }
      }

      return null;
    } catch (e) {
      print('❌ FETCH RIDE STATUS ERROR: $e');
      return null;
    }
  }
 
  // Yolculuğu tamamla
  static Future<Map<String, dynamic>?> completeRide({
    required int rideId,
    required double totalKm,
    required int waitingMinutes,
    required double totalEarnings,
    double? dropoffLat,  // ✅ BIRAKILAN KONUM
    double? dropoffLng,  // ✅ BIRAKILAN KONUM
  }) async {
    print('🚀 === COMPLETE RIDE SERVICE BAŞLADI ===');
    print('   🆔 Ride ID: $rideId');
    print('   📏 Total KM: $totalKm');
    print('   ⏰ Waiting: $waitingMinutes');
    print('   💰 Earnings: $totalEarnings');
    print('   📍 Dropoff: Lat=$dropoffLat, Lng=$dropoffLng');
    
    try {
      final requestBody = {
        'ride_id': rideId,
        'total_km': totalKm.toStringAsFixed(2),
        'waiting_minutes': waitingMinutes,
        'total_earnings': totalEarnings,
        if (dropoffLat != null) 'dropoff_lat': dropoffLat,
        if (dropoffLng != null) 'dropoff_lng': dropoffLng,
      };
      
      print('📤 REQUEST BODY: ${jsonEncode(requestBody)}');
      print('🔗 URL: $baseUrl/complete_ride.php');
      
      final response = await http.post(
        Uri.parse('$baseUrl/complete_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⏰ COMPLETE RIDE TIMEOUT - 30 saniye aşıldı!');
          throw TimeoutException('Complete ride API timeout');
        },
      );

      print('📡 Complete ride response status: ${response.statusCode}');
      print('📋 Complete ride response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ JSON parse başarılı: $data');
        
        if (data['success'] == true) {
          print('✅ Complete ride SUCCESS!');
          print('💾 Fatura bilgisi: ${data['invoice_created']} - ${data['invoice_message']}');
          await _notifyCustomer(rideId, 'completed');
          return data;
        } else {
          print('❌ Complete ride API success=false: ${data['message']}');
          return null;
        }
      } else {
        print('❌ Complete ride HTTP error: ${response.statusCode}');
        print('   Body: ${response.body}');
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ COMPLETE RIDE ERROR: $e');
      print('📚 STACK TRACE: $stackTrace');
      return null;
    }
  }
 
  // Aktif yolculuğu getir
  static Future<Map<String, dynamic>?> getActiveRide(int driverId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/get_driver_active_ride.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driver_id': driverId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['ride'];
        }
      }
      return null;
    } catch (e) {
      print('❌ GET ACTIVE RIDE ERROR: $e');
      return null;
    }
  }
  
  // Müşteriye bildirim gönder
  static Future<void> _notifyCustomer(int rideId, String status) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/notify_customer.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'status': status,
        }),
      );
    } catch (e) {
      print('❌ CUSTOMER NOTIFICATION ERROR: $e');
    }
  }
  
  // Sürücü durumunu güncelle
  static Future<bool> updateDriverStatus(int driverId, bool isOnline, double? lat, double? lng) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_driver_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'is_online': isOnline,
          'latitude': lat,
          'longitude': lng,
          'last_update': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ UPDATE DRIVER STATUS ERROR: $e');
      return false;
    }
  }
  
  // Cleanup
  static void dispose() {
    _rideCheckTimer?.cancel();
    _rideStreamController?.close();
    _rideStreamController = null;
  }

  static Future<void> _notifyRidePersistence(int rideId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/ensure_ride_persistence.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ride_id': rideId}),
      );
    } catch (e) {
      print('❌ RIDE PERSISTENCE NOTIFY ERROR: $e');
    }
  }
}
