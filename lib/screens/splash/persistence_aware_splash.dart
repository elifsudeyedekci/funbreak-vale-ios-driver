import 'package:flutter/material.dart';
import '../../services/ride_persistence_service.dart';
import '../ride/modern_active_ride_screen.dart'; // MODERN ELİT YOLCULUK EKRANI!
import '../permissions/permission_check_screen.dart'; // PERMISSION SCREEN!
// import 'splash_screen.dart'; // YOKSA KALDIRILIYOR

class PersistenceAwareSplashScreen extends StatefulWidget {
  const PersistenceAwareSplashScreen({Key? key}) : super(key: key);

  @override
  State<PersistenceAwareSplashScreen> createState() => _PersistenceAwareSplashScreenState();
}

class _PersistenceAwareSplashScreenState extends State<PersistenceAwareSplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkForActiveRide();
  }

  Future<void> _checkForActiveRide() async {
    try {
      print('🔄 [ŞOFÖR] Uygulama açılış - Aktif yolculuk kontrol ediliyor...');
      
      // Şoför için aktif yolculuk var mı kontrol et
      final shouldRestore = await RidePersistenceService.shouldRestoreRideScreen();
      
      if (shouldRestore) {
        // Aktif yolculuk verilerini al
        final rideData = await RidePersistenceService.getActiveRide();
        
        if (rideData != null) {
          print('✅ [ŞOFÖR] Aktif yolculuk bulundu - Direkt yolculuk ekranına gidiliyor');
          print('📊 [ŞOFÖR] Ride Data: ${rideData['ride_id']} - Status: ${rideData['status']}');
          
          // Ana sayfa yerine direkt yolculuk ekranını aç
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ModernDriverActiveRideScreen(
                  rideDetails: rideData,
                  waitingMinutes: 0,
                ),
              ),
            );
          }
          return; // Normal splash'e gitmesin
        }
      }
      
      print('ℹ️ [ŞOFÖR] Aktif yolculuk bulunamadı - Normal başlangıç akışı');
      
      // Normal splash screen'e git
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const PermissionCheckScreen(),
          ),
        );
      }
      
    } catch (e) {
      print('❌ [ŞOFÖR] Persistence kontrol hatası: $e');
      
      // Hata durumunda normal akış
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const PermissionCheckScreen(),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
              // FunBreak Driver Logo
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
              SizedBox(height: 4),
              Text(
                'Şoför Uygulaması',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Aktif yolculuk durumu kontrol ediliyor...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
