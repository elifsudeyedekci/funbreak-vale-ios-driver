import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/ride_persistence_service.dart';
import '../ride/modern_active_ride_screen.dart';
import '../home/driver_home_screen.dart';
import '../legal/driver_legal_consent_screen.dart';
import '../legal/driver_contract_update_screen.dart';  // YENİ: Sözleşme güncelleme ekranı

class PersistenceAwareDriverMainScreen extends StatefulWidget {
  const PersistenceAwareDriverMainScreen({Key? key}) : super(key: key);

  @override
  State<PersistenceAwareDriverMainScreen> createState() => _PersistenceAwareDriverMainScreenState();
}

class _PersistenceAwareDriverMainScreenState extends State<PersistenceAwareDriverMainScreen> {
  bool _checkingConsents = true;
  bool _showConsentScreen = false;
  bool _showUpdateScreen = false;  // YENİ: Sözleşme güncelleme ekranı
  int _driverId = 0;
  String _driverName = '';
  List<Map<String, dynamic>> _pendingContracts = [];  // YENİ: Bekleyen sözleşmeler
  
  @override
  void initState() {
    super.initState();
    
    // ÖNCELİKLE SÖZLEŞME KONTROLÜ YAP!
    _checkLegalConsents();
  }
  
  /// SÖZLEŞME ONAY KONTROLÜ - BACKEND VERSİYON KONTROLÜ İLE!
  Future<void> _checkLegalConsents() async {
    try {
      print('📋 [SÜRÜCÜ] Sözleşme onay kontrolü yapılıyor (Backend Versiyon Kontrolü)...');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Sürücü bilgilerini al
      _driverId = prefs.getInt('driver_id') ?? 0;
      if (_driverId == 0) {
        final driverIdStr = prefs.getString('driver_id');
        if (driverIdStr != null) {
          _driverId = int.tryParse(driverIdStr) ?? 0;
        }
      }
      _driverName = prefs.getString('driver_name') ?? prefs.getString('name') ?? 'Vale';
      
      print('📋 Driver ID: $_driverId, Name: $_driverName');
      
      if (_driverId <= 0) {
        print('⚠️ [SÜRÜCÜ] Driver ID bulunamadı - normal akışa devam');
        setState(() {
          _checkingConsents = false;
          _showConsentScreen = false;
          _showUpdateScreen = false;
        });
        _checkForActiveRideAsMain();
        return;
      }
      
      // 🔥 BACKEND'DEN SÖZLEŞME VERSİYON KONTROLÜ!
      final contractCheck = await _checkContractUpdatesFromBackend();
      
      if (contractCheck['needs_update'] == true) {
        _pendingContracts = List<Map<String, dynamic>>.from(contractCheck['pending_contracts'] ?? []);
        
        // İlk kez mi kabul ediyor yoksa güncelleme mi?
        final hasAnyAccepted = contractCheck['has_any_accepted'] == true;
        
        if (hasAnyAccepted) {
          // Daha önce kabul etmiş, şimdi güncelleme gerekiyor
          print('🔄 [SÜRÜCÜ] Sözleşme GÜNCELLEMESİ gerekiyor - ${_pendingContracts.length} sözleşme');
          setState(() {
            _checkingConsents = false;
            _showConsentScreen = false;
            _showUpdateScreen = true;
          });
        } else {
          // İlk kez kabul edecek
          print('⚠️ [SÜRÜCÜ] İlk kez sözleşme onayı gerekiyor');
          setState(() {
            _checkingConsents = false;
            _showConsentScreen = true;
            _showUpdateScreen = false;
          });
        }
      } else {
        // Tüm sözleşmeler güncel
        print('✅ [SÜRÜCÜ] Tüm sözleşmeler güncel - Ana sayfaya geçiliyor');
        
        // SharedPreferences'ı da güncelle (geriye dönük uyumluluk)
        await prefs.setBool('driver_consents_accepted', true);
        
        setState(() {
          _checkingConsents = false;
          _showConsentScreen = false;
          _showUpdateScreen = false;
        });
        
        _checkForActiveRideAsMain();
      }
      
    } catch (e) {
      print('❌ [SÜRÜCÜ] Sözleşme kontrol hatası: $e');
      // Hata durumunda eski sisteme fallback
      await _fallbackToLocalCheck();
    }
  }
  
  /// Backend'den sözleşme versiyon kontrolü
  Future<Map<String, dynamic>> _checkContractUpdatesFromBackend() async {
    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/check_contract_updates.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _driverId,
          'user_type': 'driver',
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final needsUpdate = data['needs_update'] == true;
          final pendingContracts = data['pending_contracts'] ?? [];
          final acceptedContracts = data['accepted_contracts'] ?? {};
          
          print('📜 [SÜRÜCÜ] Backend sözleşme kontrolü:');
          print('   - Güncelleme gerekiyor: $needsUpdate');
          print('   - Bekleyen: ${pendingContracts.length}');
          print('   - Daha önce kabul edilmiş: ${acceptedContracts.length}');
          
          return {
            'needs_update': needsUpdate,
            'pending_contracts': pendingContracts,
            'has_any_accepted': acceptedContracts.isNotEmpty,
          };
        }
      }
      
      // API hatası durumunda lokal kontrol yap
      throw Exception('API yanıt hatası');
      
    } catch (e) {
      print('⚠️ [SÜRÜCÜ] Backend kontrol hatası: $e - Lokal kontrole fallback');
      rethrow;
    }
  }
  
  /// Lokal kontrol (fallback)
  /// 
  /// NOT: Backend hata verdiğinde ve sürücü daha önce SharedPreferences'a
  /// 'driver_consents_accepted=true' yazmış olsa bile, eğer DB'ye log atılamadıysa
  /// backend kaydı eksik kalır. Bu yüzden fallback'te de KKVK uyumluluğu için
  /// consent ekranını gösteriyoruz - tekrar onaylasın ve log düşsün.
  Future<void> _fallbackToLocalCheck() async {
    try {
      print('📋 [SÜRÜCÜ] Fallback: Backend ulaşılamadı - güvenlik için consent ekranı gösteriliyor');
      setState(() {
        _checkingConsents = false;
        _showConsentScreen = true;
        _showUpdateScreen = false;
      });
    } catch (e) {
      print('❌ Fallback hatası: $e');
      setState(() {
        _checkingConsents = false;
        _showConsentScreen = false;
        _showUpdateScreen = false;
      });
      _checkForActiveRideAsMain();
    }
  }
  
  /// Sözleşmeler onaylandığında çağrılır (İlk kez veya güncelleme)
  void _onConsentsAccepted() {
    print('✅ [SÜRÜCÜ] TÜM SÖZLEŞMELER ONAYLANDI! Ana sayfaya geçiliyor...');
    setState(() {
      _showConsentScreen = false;
      _showUpdateScreen = false;
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
    
    // 🆕 Sözleşme GÜNCELLEME ekranı göster (eski kullanıcı için yeni versiyon)
    if (_showUpdateScreen && _pendingContracts.isNotEmpty) {
      return DriverContractUpdateScreen(
        driverId: _driverId,
        pendingContracts: _pendingContracts,
        onAllAccepted: _onConsentsAccepted,
      );
    }
    
    // İlk kez sözleşme onay ekranı göster (yeni kullanıcı)
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
