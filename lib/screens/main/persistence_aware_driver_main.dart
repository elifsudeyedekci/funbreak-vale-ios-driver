import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ride_persistence_service.dart';
import '../ride/modern_active_ride_screen.dart';
import '../home/driver_home_screen.dart';
import '../legal/driver_legal_consent_screen.dart';

class PersistenceAwareDriverMainScreen extends StatefulWidget {
  const PersistenceAwareDriverMainScreen({Key? key}) : super(key: key);

  @override
  State<PersistenceAwareDriverMainScreen> createState() => _PersistenceAwareDriverMainScreenState();
}

class _PersistenceAwareDriverMainScreenState extends State<PersistenceAwareDriverMainScreen> {
  bool _checkingConsents = true;
  bool _showConsentScreen = false;
  int _driverId = 0;
  String _driverName = '';
  
  @override
  void initState() {
    super.initState();
    
    // ÖNCELİKLE SÖZLEŞME KONTROLÜ YAP!
    _checkLegalConsents();
  }
  
  /// SÖZLEŞME ONAY KONTROLÜ - İLK GİRİŞTE ZORUNLU!
  Future<void> _checkLegalConsents() async {
    try {
      print('📋 [SÜRÜCÜ] Sözleşme onay kontrolü yapılıyor...');
      
      final prefs = await SharedPreferences.getInstance();
      final consentsAccepted = prefs.getBool('driver_consents_accepted') ?? false;
      
      // Sürücü bilgilerini al
      _driverId = prefs.getInt('driver_id') ?? 0;
      if (_driverId == 0) {
        // String olarak da dene
        final driverIdStr = prefs.getString('driver_id');
        if (driverIdStr != null) {
          _driverId = int.tryParse(driverIdStr) ?? 0;
        }
      }
      _driverName = prefs.getString('driver_name') ?? prefs.getString('name') ?? 'Vale';
      
      print('📋 Sözleşme durumu: ${consentsAccepted ? "ONAYLANDI" : "ONAYLANMADI"}');
      print('📋 Driver ID: $_driverId, Name: $_driverName');
      
      if (!consentsAccepted) {
        // Sözleşmeler onaylanmamış - onay ekranını göster
        print('⚠️ [SÜRÜCÜ] Sözleşmeler onaylanmamış - Onay ekranı gösteriliyor...');
        setState(() {
          _checkingConsents = false;
          _showConsentScreen = true;
        });
      } else {
        // Sözleşmeler onaylanmış - normal akışa devam
        print('✅ [SÜRÜCÜ] Sözleşmeler zaten onaylanmış - Ana sayfaya geçiliyor');
        setState(() {
          _checkingConsents = false;
          _showConsentScreen = false;
        });
        
        // ANA SAYFA AÇILIRKEN AKTİF YOLCULUK KONTROL! ✅
        _checkForActiveRideAsMain();
      }
      
    } catch (e) {
      print('❌ [SÜRÜCÜ] Sözleşme kontrol hatası: $e');
      // Hata durumunda normal akışa devam
      setState(() {
        _checkingConsents = false;
        _showConsentScreen = false;
      });
      _checkForActiveRideAsMain();
    }
  }
  
  /// Sözleşmeler onaylandığında çağrılır
  void _onConsentsAccepted() {
    print('✅ [SÜRÜCÜ] TÜM SÖZLEŞMELER ONAYLANDI! Ana sayfaya geçiliyor...');
    setState(() {
      _showConsentScreen = false;
    });
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
    // Sözleşme kontrolü yapılıyor
    if (_checkingConsents) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(height: 16),
              Text(
                'Yükleniyor...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    
    // Sözleşme onay ekranı göster
    if (_showConsentScreen) {
      return DriverLegalConsentScreen(
        driverId: _driverId,
        driverName: _driverName,
        onConsentsAccepted: _onConsentsAccepted,
      );
    }
    
    // Aktif yolculuk yoksa normal ana sayfayı göster
    return const DriverHomeScreen();
  }
}
