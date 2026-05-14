import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../main/persistence_aware_driver_main.dart'; // SÖZLEŞME KONTROLÜ İÇİN!
import 'login_screen.dart';
import '../ride/modern_active_ride_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id');
      final adminUserId = prefs.getString('admin_user_id');
      final authToken = prefs.getString('auth_token');
      
      print(
        '🔐 [ŞOFÖR] Auth kontrol: driver_id=$driverId, admin_user_id=$adminUserId, Token=${authToken != null ? "Var" : "Yok"}',
      );
      
      final isLoggedIn = (driverId != null && driverId.isNotEmpty) ||
          (adminUserId != null && adminUserId.isNotEmpty);
      
      if (isLoggedIn) {
        // LOGIN BAŞARILI - PERSİSTENCE KONTROL ET!
        await _checkActiveRidePersistence();
      }
      
      setState(() {
        _isLoggedIn = isLoggedIn;
        _isLoading = false;
      });
      
    } catch (e) {
      print('❌ [ŞOFÖR] Auth kontrol hatası: $e');
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
    }
  }
  
  // KRİTİK: AKTİF YOLCULUK PERSİSTENCE KONTROL - GÜÇLENDİRİLMİŞ!
  Future<void> _checkActiveRidePersistence() async {
    try {
      print('🔍 ŞOFÖR: AuthWrapper persistence kontrol başlıyor...');
      
      final prefs = await SharedPreferences.getInstance();
      final driverActiveRide = prefs.getString('active_driver_ride_data');
      
      if (driverActiveRide != null && driverActiveRide.isNotEmpty) {
        final rideData = jsonDecode(driverActiveRide);
        final status = rideData['status']?.toString() ?? '';
        final rideId = rideData['ride_id']?.toString() ?? '0';
        
        print('✅ ŞOFÖR: AuthWrapper\'da persistence verisi bulundu - ID: $rideId, Status: $status');
        
        // BACKEND'DEN GERÇEK DURUMU KONTROL ET!
        final hasRealActiveRide = await _checkBackendActiveRide(rideId);
        
        if (hasRealActiveRide) {
          final activeStatuses = ['accepted', 'in_progress', 'driver_arrived', 'ride_started', 'waiting_customer'];
          
          if (activeStatuses.contains(status)) {
            print('🚗 ŞOFÖR: Backend doğrulandı - Yolculuk ekranına yönlendiriliyor');
            
            // 2 saniye bekle ki UI hazır olsun
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ModernDriverActiveRideScreen(
                      rideDetails: rideData,
                      waitingMinutes: rideData['waiting_minutes'] ?? 0,
                    ),
                  ),
                );
              }
            });
          } else {
            print('🗑️ ŞOFÖR: Eski durum - persistence temizleniyor');
            await _clearPersistenceData();
          }
        } else {
          print('❌ ŞOFÖR: Backend\'de aktif yolculuk yok - persistence temizleniyor');
          await _clearPersistenceData();
        }
      } else {
        print('ℹ️ ŞOFÖR: AuthWrapper\'da persistence verisi yok');
      }
    } catch (e) {
      print('❌ ŞOFÖR: AuthWrapper persistence hatası: $e');
      // Hata durumunda persistence temizle
      await _clearPersistenceData();
    }
  }
  
  // BACKEND'DEN GERÇEK AKTİF YOLCULUK KONTROLÜ
  Future<bool> _checkBackendActiveRide(String rideId) async {
    try {
      if (rideId == '0' || rideId.isEmpty) return false;
      
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/check_driver_active_ride.php?ride_id=$rideId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hasActive = data['has_active_ride'] == true;
        
        print('🌐 ŞOFÖR: Backend kontrol - has_active_ride: $hasActive');
        return hasActive;
      }
      
      return false;
    } catch (e) {
      print('❌ ŞOFÖR: Backend aktif yolculuk kontrol hatası: $e');
      return false;
    }
  }
  
  // PERSİSTENCE VERİLERİNİ TEMİZLE
  Future<void> _clearPersistenceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_driver_ride_data');
      await prefs.remove('driver_ride_state');
      print('🗑️ ŞOFÖR: Persistence verileri temizlendi');
    } catch (e) {
      print('❌ ŞOFÖR: Persistence temizleme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF1A1A2E),
                Color(0xFF16213E),
              ],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_taxi,
                  size: 80,
                  color: Color(0xFFFFD700),
                ),
                SizedBox(height: 16),
                Text(
                  'FunBreak Vale',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
                Text(
                  'Şoför Uygulaması',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFFFFD700),
                  ),
                ),
                SizedBox(height: 32),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                ),
                SizedBox(height: 16),
                Text(
                  'Yükleniyor...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Giriş durumuna göre yönlendir
    if (_isLoggedIn) {
      print('✅ [ŞOFÖR] Giriş yapılmış - Sözleşme kontrolü yapılacak');
      // SÖZLEŞME KONTROLÜ İÇİN PersistenceAwareDriverMainScreen KULLAN!
      return const PersistenceAwareDriverMainScreen();
    } else {
      print('ℹ️ [ŞOFÖR] Giriş yapılmamış - Login sayfasına yönlendiriliyor');
      return const LoginScreen();
    }
  }
}
