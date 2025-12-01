import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 🚗 BACKGROUND LOCATION SERVICE
/// Uygulama tamamen kapalı olsa bile arka planda konum takibi yapar
/// KM hesaplama kesintisiz devam eder!
class BackgroundLocationService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static bool _isInitialized = false;
  
  /// Servisi başlat (bir kez çağrılmalı - main.dart'ta)
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('🚗 Background service zaten başlatılmış');
      return;
    }
    
    final service = FlutterBackgroundService();
    
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'location_tracking_channel',
        initialNotificationTitle: 'FunBreak Vale',
        initialNotificationContent: 'Konum takibi hazır',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
    
    _isInitialized = true;
    print('✅ Background location service başlatıldı');
  }
  
  /// Android/iOS foreground service başlangıcı
  @pragma('vm:entry-point')
  static Future<void> _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    print('🚗 BACKGROUND SERVICE BAŞLADI!');
    
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });
      
      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }
    
    service.on('stopService').listen((event) {
      print('🛑 Background service durduruluyor...');
      service.stopSelf();
    });
    
    service.on('setRideId').listen((event) async {
      if (event != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('background_ride_id', event['ride_id'].toString());
        print('🚗 Ride ID set: ${event['ride_id']}');
      }
    });
    
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: "FunBreak Vale - Yolculuk Devam Ediyor",
            content: "Konum takibi aktif 📍 ${DateTime.now().toString().substring(11, 19)}",
          );
        }
      }
      
      await _sendBackgroundLocation();
      
      service.invoke('locationUpdate', {
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  }
  
  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
  
  /// Arka planda konum gönder
  static Future<void> _sendBackgroundLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('user_id');
      final rideId = prefs.getString('background_ride_id');
      
      if (driverId == null) {
        print('⚠️ Background: Driver ID bulunamadı');
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        print('⚠️ Background: Konum izni yok');
        return;
      }
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      print('📍 BACKGROUND KONUM: ${position.latitude}, ${position.longitude}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/update_location.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': int.tryParse(driverId) ?? driverId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'timestamp': DateTime.now().toIso8601String(),
          'is_online': 1,
          'source': 'background_service',
          if (rideId != null) 'ride_id': int.tryParse(rideId) ?? rideId,
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Background konum gönderildi - KM: ${data['total_distance'] ?? 'N/A'}');
        }
      }
    } catch (e) {
      print('❌ Background konum hatası: $e');
    }
  }
  
  /// Yolculuk başladığında servisi başlat
  static Future<void> startRideTracking(String rideId) async {
    try {
      final service = FlutterBackgroundService();
      
      await service.startService();
      
      service.invoke('setRideId', {'ride_id': rideId});
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_ride_id', rideId);
      await prefs.setBool('background_tracking_active', true);
      
      print('🚗 Background tracking başladı - Ride: $rideId');
    } catch (e) {
      print('❌ Background tracking başlatma hatası: $e');
    }
  }
  
  /// Yolculuk bittiğinde servisi durdur
  static Future<void> stopRideTracking() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('background_ride_id');
      await prefs.setBool('background_tracking_active', false);
      
      print('🛑 Background tracking durduruldu');
    } catch (e) {
      print('❌ Background tracking durdurma hatası: $e');
    }
  }
  
  /// Servis çalışıyor mu kontrol et
  static Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
  
  /// Aktif yolculuk varsa servisi yeniden başlat
  static Future<void> resumeIfActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool('background_tracking_active') ?? false;
      final rideId = prefs.getString('background_ride_id');
      
      if (isActive && rideId != null) {
        final isRunning = await BackgroundLocationService.isRunning();
        if (!isRunning) {
          print('🔄 Background service yeniden başlatılıyor - Ride: $rideId');
          await startRideTracking(rideId);
        }
      }
    } catch (e) {
      print('❌ Resume hatası: $e');
    }
  }
}

