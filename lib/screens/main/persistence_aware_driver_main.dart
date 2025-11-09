import 'package:flutter/material.dart';
import '../../services/ride_persistence_service.dart';
import '../ride/modern_active_ride_screen.dart';
import '../home/driver_home_screen.dart';

class PersistenceAwareDriverMainScreen extends StatefulWidget {
  const PersistenceAwareDriverMainScreen({Key? key}) : super(key: key);

  @override
  State<PersistenceAwareDriverMainScreen> createState() => _PersistenceAwareDriverMainScreenState();
}

class _PersistenceAwareDriverMainScreenState extends State<PersistenceAwareDriverMainScreen> {
  
  @override
  void initState() {
    super.initState();
    
    // ANA SAYFA AÇILIRKEN AKTİF YOLCULUK KONTROL! ✅
    _checkForActiveRideAsMain();
  }
  
  Future<void> _checkForActiveRideAsMain() async {
    try {
      print('🚗 [ŞOFÖR ANA SAYFA] Persistence kontrol - Aktif yolculuk var mı?');
      
      final shouldRestore = await RidePersistenceService.shouldRestoreRideScreen();
      
      if (shouldRestore) {
        final rideData = await RidePersistenceService.getActiveRide();
        
        if (rideData != null) {
          final status = rideData['status'];
          
          // SADECE AKTİF DURUMLARDA MODERN EKRAN! ✅
          final activeStatuses = ['accepted', 'in_progress', 'driver_arrived', 'ride_started', 'waiting_customer'];
          
          if (activeStatuses.contains(status)) {
            print('✅ [ŞOFÖR ANA SAYFA] Aktif yolculuk bulundu - Modern ekran ana sayfa oluyor');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ModernDriverActiveRideScreen(
                    rideDetails: rideData,
                    waitingMinutes: 0,
                  ),
                ),
              );
              return; // Normal ana sayfaya gitmesin
            }
          } else {
            // Bitmiş yolculuk varsa temizle
            await RidePersistenceService.clearActiveRide();
            print('🗑️ [ŞOFÖR ANA SAYFA] Bitmiş yolculuk persistence temizlendi');
          }
        }
      }
      
      print('ℹ️ [ŞOFÖR ANA SAYFA] Aktif yolculuk yok - Normal ana sayfaya gidiliyor');
      
    } catch (e) {
      print('❌ [ŞOFÖR ANA SAYFA] Persistence kontrol hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Aktif yolculuk yoksa normal ana sayfayı göster
    return const DriverHomeScreen();
  }
}
