import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class RidePersistenceService {
  static const String _activeRideKey = 'active_driver_ride_data';
  static const String _rideStateKey = 'driver_ride_state';
  static const String _pendingRequestKey = 'pending_driver_request';
  
  // Aktif yolculuk durumunu kaydet - DEBUG İLE GÜÇLENDİRİLMİŞ!
  static Future<void> saveActiveRide({
    required int rideId,
    required String status,
    required String pickupAddress,
    required String destinationAddress,
    required double estimatedPrice,
    required String customerName,
    required String customerPhone,
    required String customerId,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final rideData = {
        'ride_id': rideId,
        'status': status,
        'pickup_address': pickupAddress,
        'destination_address': destinationAddress,
        'estimated_price': estimatedPrice,
        'customer_name': customerName,
        'customer_phone': customerPhone,
        'customer_id': customerId,
        'saved_at': DateTime.now().toIso8601String(),
        'additional_data': additionalData ?? {},
      };
      
      // Kaydet
      await prefs.setString(_activeRideKey, jsonEncode(rideData));
      await prefs.setString(_rideStateKey, 'active');
      
      print('✅ [ŞOFÖR PERSİSTENCE] Aktif yolculuk kaydedildi:');
      print('   📦 Key: $_activeRideKey');
      print('   🆔 Ride ID: $rideId');
      print('   📊 Status: $status');
      print('   👤 Müşteri: $customerName');
      
      // Test - kaydedilenleri kontrol et
      final savedData = prefs.getString(_activeRideKey);
      final savedState = prefs.getString(_rideStateKey);
      print('✅ [ŞOFÖR PERSİSTENCE] Kayıt doğrulandı: Data=${savedData != null}, State=$savedState');
      
    } catch (e) {
      print('❌ [ŞOFÖR PERSİSTENCE] Yolculuk kaydetme hatası: $e');
    }
  }
  
  // Bekleyen talep bildirimini kaydet - BACKGROUND'DAN ÇAĞRILIR!
  static Future<void> savePendingRideRequest(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> normalized = {};
      data.forEach((key, value) {
        normalized[key] = value;
      });
      normalized['persisted_at'] = DateTime.now().toIso8601String();
      await prefs.setString(_pendingRequestKey, jsonEncode(normalized));
      print('📦 [ŞOFÖR PERSİSTENCE] Bekleyen talep kaydedildi: ${normalized['ride_id']}');
    } catch (e) {
      print('❌ [ŞOFÖR PERSİSTENCE] Bekleyen talep kaydetme hatası: $e');
    }
  }

  // Bekleyen talep bildirimini getir
  static Future<Map<String, dynamic>?> getPendingRideRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final requestJson = prefs.getString(_pendingRequestKey);
      if (requestJson == null || requestJson.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(requestJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      print('❌ [ŞOFÖR PERSİSTENCE] Bekleyen talep alma hatası: $e');
    }
    return null;
  }

  // Bekleyen talep bildirimini temizle
  static Future<void> clearPendingRideRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingRequestKey);
      print('🗑️ [ŞOFÖR PERSİSTENCE] Bekleyen talep temizlendi');
    } catch (e) {
      print('❌ [ŞOFÖR PERSİSTENCE] Bekleyen talep temizleme hatası: $e');
    }
  }

  // Aktif yolculuk verilerini al
  static Future<Map<String, dynamic>?> getActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideDataJson = prefs.getString(_activeRideKey);
      final rideState = prefs.getString(_rideStateKey);
      
      if (rideDataJson != null && rideState == 'active') {
        final rideData = jsonDecode(rideDataJson) as Map<String, dynamic>;
        
        // Kayıt tarihini kontrol et (24 saat eski ise sil)
        final savedAt = DateTime.parse(rideData['saved_at']);
        final now = DateTime.now();
        
        if (now.difference(savedAt).inHours > 24) {
          await clearActiveRide();
          print('⏰ [ŞOFÖR] Eski yolculuk verisi temizlendi');
          return null;
        }
        
        print('📱 [ŞOFÖR] Aktif yolculuk bulundu - Ride ID: ${rideData['ride_id']}');
        return rideData;
      }
      
      return null;
    } catch (e) {
      print('❌ [ŞOFÖR] Aktif yolculuk alma hatası: $e');
      return null;
    }
  }
  
  // Yolculuk durumunu güncelle
  static Future<void> updateRideStatus(String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideDataJson = prefs.getString(_activeRideKey);
      
      if (rideDataJson != null) {
        final rideData = jsonDecode(rideDataJson) as Map<String, dynamic>;
        rideData['status'] = newStatus;
        rideData['updated_at'] = DateTime.now().toIso8601String();
        
        await prefs.setString(_activeRideKey, jsonEncode(rideData));
        print('🔄 [ŞOFÖR] Yolculuk durumu güncellendi: $newStatus');
      }
    } catch (e) {
      print('❌ [ŞOFÖR] Durum güncelleme hatası: $e');
    }
  }
  
  // Aktif yolculuğu temizle
  static Future<void> clearActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeRideKey);
      await prefs.remove(_rideStateKey);
      
      print('🗑️ [ŞOFÖR] Aktif yolculuk verisi temizlendi');
    } catch (e) {
      print('❌ [ŞOFÖR] Yolculuk temizleme hatası: $e');
    }
  }
  
  // Yolculuk aktif mi kontrol et
  static Future<bool> hasActiveRide() async {
    final rideData = await getActiveRide();
    return rideData != null;
  }
  
  // Yolculuk ID'sini al
  static Future<int?> getActiveRideId() async {
    final rideData = await getActiveRide();
    return rideData != null ? rideData['ride_id'] as int : null;
  }
  
  // Crash recovery - uygulama açıldığında çağrılır
  static Future<bool> shouldRestoreRideScreen() async {
    try {
      final rideData = await getActiveRide();
      
      if (rideData != null) {
        final status = rideData['status'] as String;
        
        // Şoför için aktif durumlar
        final activeStatuses = [
          'accepted',
          'in_progress',
          'driver_arrived', 
          'ride_started',
          'waiting_customer',
          'on_the_way'
        ];
        
        if (activeStatuses.contains(status)) {
          print('🔄 [ŞOFÖR] Yolculuk ekranı restore edilecek - Status: $status');
          return true;
        } else {
          await clearActiveRide();
          return false;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ [ŞOFÖR] Restore kontrol hatası: $e');
      return false;
    }
  }
  
  // Konum verilerini güncelle
  static Future<void> updateLocationData({
    double? currentLat,
    double? currentLng,
    double? distanceToPickup,
    double? estimatedArrival,
  }) async {
    try {
      final updates = <String, dynamic>{};
      
      if (currentLat != null) updates['current_lat'] = currentLat;
      if (currentLng != null) updates['current_lng'] = currentLng;
      if (distanceToPickup != null) updates['distance_to_pickup'] = distanceToPickup;
      if (estimatedArrival != null) updates['estimated_arrival'] = estimatedArrival;
      
      await updateRideData(updates);
    } catch (e) {
      print('❌ [ŞOFÖR] Konum güncelleme hatası: $e');
    }
  }
  
  // Yolculuk kilometre/süre verilerini güncelle
  static Future<void> updateRideMetrics({
    double? totalDistance,
    int? totalDuration,
    int? waitingMinutes,
  }) async {
    try {
      final updates = <String, dynamic>{};
      
      if (totalDistance != null) updates['total_distance'] = totalDistance;
      if (totalDuration != null) updates['total_duration'] = totalDuration;
      if (waitingMinutes != null) updates['waiting_minutes'] = waitingMinutes;
      
      await updateRideData(updates);
    } catch (e) {
      print('❌ [ŞOFÖR] Metrik güncelleme hatası: $e');
    }
  }
  
  // Ek yolculuk bilgilerini güncelle
  static Future<void> updateRideData(Map<String, dynamic> updates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rideDataJson = prefs.getString(_activeRideKey);
      
      if (rideDataJson != null) {
        final rideData = jsonDecode(rideDataJson) as Map<String, dynamic>;
        
        updates.forEach((key, value) {
          rideData[key] = value;
        });
        
        rideData['updated_at'] = DateTime.now().toIso8601String();
        
        await prefs.setString(_activeRideKey, jsonEncode(rideData));
        print('📝 [ŞOFÖR] Yolculuk verileri güncellendi: ${updates.keys.join(", ")}');
      }
    } catch (e) {
      print('❌ [ŞOFÖR] Veri güncelleme hatası: $e');
    }
  }
}
