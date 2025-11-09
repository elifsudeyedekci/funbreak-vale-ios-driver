import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminApiProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  // Kullanıcı kayıt
  Future<Map<String, dynamic>> registerCustomer({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'type': 'customer',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Başarılı kayıt
          await _saveUserSession(data['user']);
          return {'success': true, 'user': data['user']};
        } else {
          return {'success': false, 'message': data['message']};
        }
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Kullanıcı giriş
  Future<Map<String, dynamic>> loginCustomer({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'type': 'customer',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _saveUserSession(data['user']);
          return {'success': true, 'user': data['user']};
        } else {
          return {'success': false, 'message': data['message']};
        }
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Şoför giriş
  Future<Map<String, dynamic>> loginDriver({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'type': 'driver',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await _saveUserSession(data['user']);
          return {'success': true, 'user': data['user']};
        } else {
          return {'success': false, 'message': data['message']};
        }
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Vale talebi oluştur
  Future<Map<String, dynamic>> createRideRequest({
    required String customerId,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String destinationAddress,
    required double destinationLat,
    required double destinationLng,
    required DateTime scheduledTime,
    required double estimatedPrice,
    required String paymentMethod,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/create_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': int.tryParse(customerId) ?? 1, // STRING'İ INTEGER'A ÇEVİR!
          'pickup_address': pickupAddress,
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'destination_address': destinationAddress,
          'destination_lat': destinationLat,
          'destination_lng': destinationLng,
          'scheduled_time': scheduledTime.toIso8601String(),
          'estimated_price': estimatedPrice,
          'payment_method': paymentMethod,
          'request_type': 'immediate_or_soon', // REQUEST TYPE EKLENDİ!
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Fiyatlandırma bilgilerini getir
  Future<Map<String, dynamic>> getPricingData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/pricing.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        return {'success': false, 'message': 'Sunucu hatası'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Bağlantı hatası: $e'};
    }
  }

  // Kampanyaları getir
  Future<List<Map<String, dynamic>>> getCampaigns() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_campaigns.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['campaigns']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Kampanya getirme hatası: $e');
      return [];
    }
  }

  // Duyuruları getir
  Future<List<Map<String, dynamic>>> getAnnouncements() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_announcements.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['announcements']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Duyuru getirme hatası: $e');
      return [];
    }
  }

  // Kullanıcı oturum bilgilerini kaydet
  Future<void> _saveUserSession(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', user['id'].toString());
    await prefs.setString('user_name', user['name']);
    await prefs.setString('user_email', user['email']);
    await prefs.setString('user_phone', user['phone'] ?? '');
    await prefs.setBool('is_logged_in', true);
  }

  // Oturum temizle
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Mevcut kullanıcı bilgilerini getir - DOĞRU KEY'LERİ KULLAN!
  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    
    if (!isLoggedIn) return null;
    
    // SÜRÜCÜ UYGULAMASI KEY'LERİNİ KONTROL ET!
    final driverId = prefs.getString('driver_id') ?? 
                     prefs.getString('admin_user_id') ?? 
                     prefs.getString('user_id'); // Fallback
    
    print('🔍 === getCurrentUser DEBUG ===');
    print('   🔑 driver_id: ${prefs.getString('driver_id')}');
    print('   🔑 admin_user_id: ${prefs.getString('admin_user_id')}');
    print('   🔑 user_id: ${prefs.getString('user_id')}');
    print('   ✅ Seçilen ID: $driverId');
    
    if (driverId == null) {
      print('❌ HİÇBİR DRIVER ID BULUNAMADI!');
      return null;
    }
    
    return {
      'id': driverId,
      'name': prefs.getString('user_name') ?? prefs.getString('driver_name'),
      'email': prefs.getString('user_email') ?? prefs.getString('driver_email'),
      'phone': prefs.getString('user_phone') ?? prefs.getString('driver_phone'),
    };
  }

  // ÇEVRİMİÇİ SÜRÜCÜ İÇİN MEVCUT TALEPLERİ ÇEK - KRİTİK API!
  Future<Map<String, dynamic>> getAvailableRidesForDriver(String driverId) async {
    try {
      print('🚗 API çağrısı: Mevcut talepler - sürücü: $driverId');
      print('🔗 URL: $baseUrl/get_available_rides_for_driver.php?driver_id=$driverId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/get_available_rides_for_driver.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          print('✅ Talep API başarılı: ${data['rides']?.length ?? 0} talep');
          return {
            'success': true,
            'rides': data['rides'] ?? [],
          };
        } else {
          print('⚠️ API yanıtı: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Talep listesi alınamadı',
            'rides': [],
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
          'rides': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
        'rides': [],
      };
    }
  }

  // VALE TALEBİNİ KABUL ET - KRİTİK API!
  Future<Map<String, dynamic>> acceptRideRequest({
    required String rideId,
    required String driverId,
  }) async {
    try {
      print('✅ API çağrısı: Talep kabul - ride: $rideId, driver: $driverId');
      
      final response = await http.post(
        Uri.parse('$baseUrl/accept_ride_request.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'driver_id': driverId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          print('✅ Talep kabul API başarılı!');
          return {
            'success': true,
            'message': data['message'] ?? 'Talep başarıyla kabul edildi',
            'ride': data['ride'],
          };
        } else {
          print('❌ Kabul edilemedi: ${data['message']}');
          return {
            'success': false,
            'message': data['message'] ?? 'Talep kabul edilemedi',
          };
        }
      } else {
        return {
          'success': false,
          'message': 'Sunucu hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  // SÜRÜCÜ DURUMUNU GÜNCELLE - SÜPER DETAYLI DEBUG!
  Future<Map<String, dynamic>> updateDriverStatus({
    required String driverId,
    required bool isOnline,
    required bool isAvailable,
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('🌐 === ADMIN API updateDriverStatus BAŞLADI ===');
      print('   🎯 Hedef URL: $baseUrl/update_driver_status.php');
      print('   👨‍🚗 Driver ID: $driverId (${driverId.runtimeType})');
      print('   🔄 is_online: $isOnline (${isOnline.runtimeType})');
      print('   ✅ is_available: $isAvailable (${isAvailable.runtimeType})');
      print('   📍 latitude: $latitude (${latitude.runtimeType})');
      print('   📍 longitude: $longitude (${longitude.runtimeType})');
      
      final requestBody = {
        'driver_id': driverId,
        'is_online': isOnline,
        'is_available': isAvailable,
        'latitude': latitude,
        'longitude': longitude,
        'last_active': DateTime.now().toIso8601String(),
        'timestamp': DateTime.now().toIso8601String(), // İlave timestamp
      };
      
      print('📤 REQUEST BODY: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/update_driver_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15)); // Timeout artırıldı

      print('📡 === HTTP RESPONSE ALINDI ===');
      print('   📊 Status Code: ${response.statusCode}');
      print('   📝 Headers: ${response.headers}');
      print('   📋 Body Length: ${response.body.length} characters');
      print('   📋 Body Preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        print('📊 === JSON PARSE BAŞARILI ===');
        print('   ✅ Success: ${data['success']} (${data['success'].runtimeType})');
        print('   💬 Message: ${data['message']}');
        print('   📊 Data: ${data['data']}');
        
        if (data['success'] == true) {
          print('🎉 === ADMIN API BAŞARILI ===');
          print('   📊 Database drivers tablosu güncellendi!');
          print('   ⏰ Panel 5 saniye içinde yeni durumu göstermeli');
          
          return {
            'success': true,
            'message': data['message'] ?? 'Durum başarıyla güncellendi',
            'data': data['data'],
          };
        } else {
          print('❌ === ADMIN API BAŞARISIZ ===');
          print('   💬 Server hatası: ${data['message']}');
          
          return {
            'success': false,
            'message': data['message'] ?? 'Durum güncellenemedi',
          };
        }
      } else {
        print('❌ === HTTP HATASI ===');
        print('   📊 Status: ${response.statusCode}');
        print('   📋 Body: ${response.body}');
        
        return {
          'success': false,
          'message': 'HTTP hatası: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ === ADMIN API EXCEPTION ===');
      print('   🐛 Exception: $e');
      print('   📊 Type: ${e.runtimeType}');
      
      return {
        'success': false,
        'message': 'Exception: $e',
      };
    }
  }

  // ŞOFÖR DUYURULARINI ÇEK - YENİ API!
  Future<List<Map<String, dynamic>>> getDriverAnnouncements() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_announcements.php?type=driver'), // ŞOFÖR DUYURULARI!
        headers: {'Content-Type': 'application/json'},
      );

      print('Şoför duyuru API çağrısı: $baseUrl/get_announcements.php?type=driver');
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final announcements = List<Map<String, dynamic>>.from(data['announcements']);
          // API'den gelen verileri UI formatına çevir
          return announcements.map((announcement) => {
            'title': announcement['title'] ?? 'Duyuru',
            'subtitle': announcement['message'] ?? '',
            'date': announcement['created_at'] ?? '',
            'id': announcement['id'],
          }).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Şoför duyuru getirme hatası: $e');
      return [];
    }
  }

  // SİSTEM AYARLARI - DESTEK BİLGİLERİ ENTEGRAYSyONU!
  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_system_settings.php'),
        headers: {'Content-Type': 'application/json'},
      );

      print('SÜRÜCÜ Sistem ayarları API çağrısı: $baseUrl/get_system_settings.php');
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['settings'] ?? {};
        }
      }
      
      // Fallback ayarlar
      return {
        'app_name': 'FunBreak Vale Driver',
        'support_phone': '+90 555 123 4567',
        'support_email': 'destek@funbreakvale.com',
        'support_whatsapp': '+90 555 123 4567',
      };
    } catch (e) {
      debugPrint('Sürücü sistem ayarları hatası: $e');
      
      // Fallback ayarlar
      return {
        'app_name': 'FunBreak Vale Driver',
        'support_phone': '+90 555 123 4567',
        'support_email': 'destek@funbreakvale.com',
        'support_whatsapp': '+90 555 123 4567',
      };
    }
  }
}
