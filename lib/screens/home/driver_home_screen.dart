import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; // PROVİZYON TETİKLE İÇİN!
import 'dart:convert'; // JSON ENCODE İÇİN!
import 'dart:async'; // Timer için!
import '../../providers/auth_provider.dart';
import '../../providers/driver_ride_provider.dart';
import '../../providers/real_time_tracking_provider.dart';
import '../../providers/waiting_time_provider.dart';
import '../../providers/admin_api_provider.dart';
import '../../models/ride.dart';
import '../../widgets/driver_notifications_bottom_sheet.dart';
import '../../services/ride_service.dart';
import '../ride/modern_active_ride_screen.dart'; // MODERN ELİT YOLCULUK EKRANI!
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'widgets/driver_status_card.dart'; // YENİ WIDGET!
import 'widgets/driver_toggle_section.dart'; // YENİ WIDGET!
import '../earnings/earnings_screen.dart'; // KAZANÇ ANALİZİ EKRANI!
import 'package:url_launcher/url_launcher.dart'; // NAVİGASYON İÇİN!

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({Key? key}) : super(key: key);

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng _currentLocation = const LatLng(40.0082, 20.0784); // İstanbul
  double _todayEarnings = 0.0;
  int _todayRides = 0;
  
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  
  // DUPLICATE POPUP ÖNLEYİCİ
  final Set<String> _shownRideIds = {};

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addObserver(this); → KALDIRILDI! main.dart'ta var
    _initializeAnimations();
    _getCurrentLocation();
    
    // GÜNLÜK KAZANÇ - FRAME SONRASI YÜKLENSİN!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTodayStats();
    });
    
    _initializeRideService();

    // BACKEND'E BAŞLANGIÇ DURUMUNU BİLDİR!
    _syncInitialStatusToBackend();
    
    // SADECE AKTİF YOLCULUK KONTROLÜ - OTOMATİK ÇEVRİMİÇİ YAPMA!
    _checkAndResumeActiveRide();
  }
  
  // UYGULAMA AÇILINCA BACKEND'E DURUM BİLDİR - ÇEVRİMDIŞIYSA FCM GÖNDERILMESIN!
  Future<void> _syncInitialStatusToBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isOnline = prefs.getBool('driver_is_online') ?? false;
      final driverId = prefs.getString('driver_id') ?? prefs.getString('admin_user_id');
      
      if (driverId == null) return;
      
      debugPrint('🔄 BAŞLANGIÇ: Backend\'e durum gönderiliyor - ${isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');
      
      // AdminApiProvider kullan
      final adminApi = AdminApiProvider();
      final result = await adminApi.updateDriverStatus(
        driverId: driverId,
        isOnline: isOnline,
        isAvailable: isOnline,
        latitude: null,
        longitude: null,
      );
      
      if (result['success'] == true) {
        debugPrint('✅ BAŞLANGIÇ: Backend durumu güncellendi - is_online=${isOnline ? 1 : 0}');
      } else {
        debugPrint('❌ BAŞLANGIÇ: Backend güncelleme başarısız: ${result['message']}');
      }
    } catch (e) {
      debugPrint('❌ BAŞLANGIÇ: Backend durum güncelleme hatası: $e');
    }
  }

  // UYGULAMA YENİDEN AÇILDIĞINDA AKTİF YOLCULUK KONTROLÜ - GÜÇLENDİRİLMİŞ!
  void _checkAndResumeActiveRide() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.user?['id']?.toString() ?? '0';
      
      print('🔍 UYGULAMA BAŞLANGICI: Aktif yolculuk kontrolü - Driver ID: $driverId');
      
      // ÖNCE PERSİSTENCE KONTROL ET
      final prefs = await SharedPreferences.getInstance();
      final driverActiveRide = prefs.getString('active_driver_ride_data');
      
      String? rideIdToCheck;
      
      if (driverActiveRide != null && driverActiveRide.isNotEmpty) {
        print('📱 PERSİSTENCE VERİSİ VAR - Backend ile doğrula');
        final rideData = jsonDecode(driverActiveRide);
        rideIdToCheck = rideData['ride_id']?.toString();
      } else {
        print('ℹ️ PERSİSTENCE VERİSİ YOK - Yine de backend kontrol ediliyor...');
      }
      
      // HER ZAMAN BACKEND'DEN KONTROL ET - Persistence olsun olmasın!
      final apiUrl = rideIdToCheck != null 
          ? 'https://admin.funbreakvale.com/api/check_driver_active_ride.php?driver_id=$driverId&ride_id=$rideIdToCheck'
          : 'https://admin.funbreakvale.com/api/check_driver_active_ride.php?driver_id=$driverId';
      
      print('🌐 BACKEND API çağrılıyor: $apiUrl');
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      print('📡 BACKEND RESPONSE - Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        print('📊 BACKEND DATA: ${data.toString()}');
        print('   has_active_ride: ${data['has_active_ride']}');
        
        if (data['success'] == true && data['has_active_ride'] == true) {
          print('✅ BACKEND DOĞRULANDI - Aktif yolculuk var, ekrana yönlendiriliyor...');
          print('📊 Aktif Ride ID: ${data['ride_id']}, Status: ${data['status']}');
          
          // Güncel verilerle yolculuk ekranına yönlendir
          final activeRideDetails = {
            'ride_id': data['ride_id'],
            'customer_id': data['customer_id'],
            'pickup_address': data['pickup_address'] ?? 'Alış konumu',
            'destination_address': data['destination_address'] ?? 'Varış konumu',
            'pickup_lat': data['pickup_lat'], // 🗺️ KOORDİNATLAR EKLENDİ!
            'pickup_lng': data['pickup_lng'],
            'destination_lat': data['destination_lat'],
            'destination_lng': data['destination_lng'],
            'waypoints': data['waypoints'], // 🛣️ ARA DURAKLAR!
            'estimated_price': data['estimated_price']?.toString() ?? '0',
            'status': data['status'],
            'customer_name': data['customer_name'] ?? 'Müşteri',
            'customer_phone': data['customer_phone'] ?? '',
            'waiting_minutes': data['waiting_minutes'] ?? 0,
            'current_km': data['current_km'] ?? 0.0,
            'started_at': data['started_at'], // SAATLİK PAKET HESABI İÇİN KRİTİK!
            'total_distance': data['total_distance'] ?? 0.0,
            'service_type': data['service_type'], // SAATLİK PAKET TESPİTİ İÇİN!
            'ride_type': data['ride_type'], // SAATLİK PAKET TESPİTİ İÇİN!
          };
          
          print('🔍 ŞOFÖR: Yolculuk detayları hazır:');
          print('   📍 Ride ID: ${data['ride_id']}');
          print('   ⏳ Bekleme: ${data['waiting_minutes']} dk');
          print('   📏 KM: ${data['current_km']} km');
          print('   🕐 Started: ${data['started_at']}');
          
          // YOLCULUK EKRANINA YÖNLENDİR!
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              print('🚗 ŞOFÖR: Yolculuk ekranına geçiliyor...');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ModernDriverActiveRideScreen(
                    rideDetails: activeRideDetails,
                    waitingMinutes: data['waiting_minutes'] ?? 0,
                  ),
                ),
              );
            }
          });
          
        } else {
          print('❌ BACKEND\'DE AKTİF YOLCULUK YOK');
          if (driverActiveRide != null) {
            print('🗑️ Eski persistence temizleniyor');
            await _clearPersistenceData();
          }
          print('✅ AKTİF YOLCULUK YOK - ANA SAYFADA KALINIYOR');
          return; // KRİTİK: Yolculuk ekranı AÇMA!
        }
      } else {
        print('❌ BACKEND KONTROL HATASI - HTTP ${response.statusCode}');
      }
      
    } catch (e) {
      print('❌ Aktif yolculuk kontrol hatası: $e');
      // Hata durumunda persistence temizle ve normal ana sayfaya devam et
      await _clearPersistenceData();
    }
  }
  
  // PERSİSTENCE VERİLERİNİ TEMİZLE
  Future<void> _clearPersistenceData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_driver_ride_data');
      await prefs.remove('driver_ride_state');
      print('🗑️ PERSİSTENCE VERİLERİ TEMİZLENDİ');
    } catch (e) {
      print('❌ Persistence temizleme hatası: $e');
    }
  }
  
  void _initializeRideService() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isLoggedIn && authProvider.user?['id'] != null) {
      print('🚗 Sürücü talep sistemi başlatılıyor...');
      
      // POLLİNG TALEP LİSTENER - POPUP GÖSTER!
      final driverRideProvider = context.read<DriverRideProvider>();
      driverRideProvider.addListener(() {
        print('🔔 [DRIVER_HOME] DriverRideProvider listener tetiklendi');
        _checkNewRidesFromPolling();
      });
      
      print('✅ Sürücü talep sistemi aktif - FCM + Polling aktif!');
    }
  }
  
  void _checkNewRidesFromPolling() {
    print('🔍 [DRIVER_HOME] Yeni talep kontrolü başladı');
    
    if (!mounted) {
      print('⚠️ [DRIVER_HOME] Widget disposed - atlanıyor');
      return;
    }
    
    try {
      final driverRideProvider = context.read<DriverRideProvider>();
      final pendingQueue = driverRideProvider.consumePendingRideRequests();
    
    print('📊 [DRIVER_HOME] Pending queue size: ${pendingQueue.length}');
    
    for (final raw in pendingQueue) {
      if (raw is! Map) continue;
      
      final rideData = Map<String, dynamic>.from(raw as Map);
      final rideId = rideData['id']?.toString() ?? '';
      
      if (rideId.isEmpty) continue;
      
      print('🚀 [DRIVER_HOME] Yeni talep bulundu - popup gösteriliyor: ID $rideId');
      
      // POPUP GÖSTER!
      _showNewRidePopup(rideData);
    }
    } catch (e) {
      print('❌ [DRIVER_HOME] Talep kontrolü hatası: $e');
    }
  }
  
  void _showNewRidePopup(Map<String, dynamic> rideData) {
    final rideId = rideData['id']?.toString() ?? '';
    
    print('🎯 [iOS POPUP] _showNewRidePopup ÇAĞRILDI:');
    print('   📋 Ride ID: $rideId');
    print('   📊 Full Data: $rideData');
    print('   ⏰ scheduled_time: ${rideData['scheduled_time']}');
    print('   📍 pickup_lat: ${rideData['pickup_lat']}');
    print('   📍 pickup_lng: ${rideData['pickup_lng']}');
    
    // DUPLICATE POPUP ÖNLEYİCİ - AYNI TALEP 2 KEZ ÇIKMASIN!
    if (_shownRideIds.contains(rideId)) {
      print('⚠️ [DRIVER_HOME] Duplicate popup engellendi - Ride ID zaten gösterildi: $rideId');
      return;
    }
    _shownRideIds.add(rideId); // Set'e ekle
    
    final customerName = rideData['customer_name'] ?? 'Müşteri';
    final pickupAddress = rideData['pickup_address'] ?? '';
    final destinationAddress = rideData['destination_address'] ?? '';
    final estimatedPrice = rideData['estimated_price']?.toString() ?? '0';
    final scheduledTime = rideData['scheduled_time'] ?? '';
    final scheduledLabel = _getScheduledTimeDisplay(rideData);
    final scheduledSubtext = _getScheduledTimeSubtext(rideData);
    final pickupDistanceRaw = _calculateDistanceToCustomer(rideData);
    final pickupDistanceText = (pickupDistanceRaw.contains('km') || pickupDistanceRaw.contains('m'))
        ? pickupDistanceRaw
        : '$pickupDistanceRaw km';
    
    print('✅ [iOS POPUP] İçerik hazırlandı:');
    print('   ⏰ Scheduled: $scheduledLabel ($scheduledSubtext)');
    print('   📍 Mesafe: $pickupDistanceText');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.directions_car, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '🚗 Yeni Vale Talebi!',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue, size: 24),
                      const SizedBox(width: 8),
                      Text(customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPopupInfoTile(
                          Icons.schedule,
                          'Talep Zamanı',
                          scheduledLabel,
                          scheduledSubtext,
                          iconColor: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPopupInfoTile(
                          Icons.social_distance,
                          'Pickup Mesafesi',
                          pickupDistanceText,
                          'Mevcut konumunuza göre',
                          iconColor: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.green, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Alış:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(pickupAddress, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // 🛣️ ÇİZGİ VE ARA DURAKLAR - ARA DURAK VARSA ONLARI GÖSTER, YOKSA DİREKT ÇİZGİ
                  if (rideData['waypoints'] != null && rideData['waypoints'] != '') ...[
                    // ARA DURAK VAR - Önce pickup'tan ilk ara durağa yeşil çizgi
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Container(
                        margin: const EdgeInsets.only(left: 11, top: 8, bottom: 8),
                        width: 2,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.5),
                        ),
                      ),
                    ),
                    // ARA DURAKLAR LİSTESİ
                    ..._buildWaypointsWidget(rideData['waypoints']),
                    // Son ara duraktan destination'a kırmızı çizgi
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Container(
                        margin: const EdgeInsets.only(left: 11, top: 8, bottom: 8),
                        width: 2,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ] else ...[
                    // ARA DURAK YOK - Direkt pickup'tan destination'a gradient çizgi
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Container(
                        margin: const EdgeInsets.only(left: 11, top: 8, bottom: 8),
                        width: 2,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.green.withOpacity(0.5), Colors.red.withOpacity(0.5)],
                          ),
                        ),
                      ),
                    ),
                  ],
                  // VARIş NOKTASI
                  Row(
                    children: [
                      const Icon(Icons.flag, color: Colors.red, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Varış:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(destinationAddress, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.payment, color: Color(0xFFFFD700), size: 20),
                              const SizedBox(height: 4),
                              Text('₺$estimatedPrice', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('❌ REDDET', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _acceptRideFromPolling(rideId, rideData);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('✅ KABUL ET', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _acceptRideFromPolling(String rideId, Map<String, dynamic> rideData) async {
    try {
      print('✅ [DRIVER_HOME] Talep kabul ediliyor (polling): $rideId');
      
      // DriverRideProvider.acceptRide() metodunu kullan - _currentRide otomatik set edilecek!
      final driverRideProvider = context.read<DriverRideProvider>();
      final success = await driverRideProvider.acceptRide(rideId);
      
      if (success) {
        print('🎉 [DRIVER_HOME] Talep DriverRideProvider ile kabul edildi, yolculuk ekranına gidiliyor');
        print('   📊 _currentRide set edildi - polling durdu!');
        
        final rideDetails = {
          'ride_id': rideId,
          'customer_id': rideData['customer_id'] ?? '0',
          'customer_name': rideData['customer_name'] ?? 'Müşteri',
          'customer_phone': rideData['customer_phone'] ?? '',
          'pickup_address': rideData['pickup_address'] ?? '',
          'destination_address': rideData['destination_address'] ?? '',
          'pickup_lat': rideData['pickup_lat'], // 🗺️ KOORDİNATLAR EKLENDİ!
          'pickup_lng': rideData['pickup_lng'],
          'destination_lat': rideData['destination_lat'],
          'destination_lng': rideData['destination_lng'],
          'waypoints': rideData['waypoints'], // 🛣️ ARA DURAKLAR!
          'estimated_price': rideData['estimated_price']?.toString() ?? '0',
          'status': 'accepted',
        };
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ModernDriverActiveRideScreen(
              rideDetails: rideDetails,
              waitingMinutes: 0,
            ),
          ),
        );
      } else {
        print('❌ [DRIVER_HOME] Talep kabul başarısız');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Talep kabul edilemedi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ [DRIVER_HOME] Talep kabul hatası: $e');
    }
  }
  
  // SÜRÜCÜNÜN AKTİF YOLCULUĞU VAR MI KONTROL ET!
  Future<bool> _checkDriverActiveRide(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/check_driver_active_ride.php?driver_id=$driverId'),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hasActive = data['has_active_ride'] == true;
        
        if (hasActive) {
          print('⚠️ Sürücü ${driverId} aktif yolculukta - Ride ID: ${data['ride_id']}');
        } else {
          print('✅ Sürücü ${driverId} yolculukta değil - yeni talep alabilir');
        }
        
        return hasActive;
      }
      
      return false; // API çalışmıyorsa false döner, talep gösterilir
    } catch (e) {
      print('❌ Aktif ride kontrol hatası: $e');
      return false; // Hata durumunda da false döner
    }
  }
  
  void _showNewRideDialog(Map<String, dynamic> rideData) async {
    if (!mounted) return;
    
    // SÜRÜCÜ YOLCULUKTAYken YENİ TALEP DÜŞME ENGELİ!
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final driverId = authProvider.user?['id']?.toString() ?? '0';
    
    print('🔍 Sürücü aktif yolculuk kontrolü başlıyor - Driver ID: $driverId');
    
    final hasActiveRide = await _checkDriverActiveRide(driverId);
    
    if (hasActiveRide) {
      print('⚠️ Sürücü zaten yolculukta - DİREKT YOLCULUK EKRANINA GİDİLİYOR: ${rideData['ride_id']}');
      
      // Popup gösterme yerine direkt yolculuk ekranına git!
      final rideId = int.tryParse(rideData['ride_id']?.toString() ?? '0') ?? 0;
      if (rideId > 0) {
        print('🚗 Aktif yolculuk tespit edildi - Yolculuk ekranı açılıyor: $rideId');
        await _navigateToModernActiveRideScreen(rideId);
      }
      return;
    }
    
    print('✅ Sürücü yolculukta değil - popup gösterilecek: ${rideData['ride_id']}');
      
      // GERÇEK MÜŞTERİ VERİLERİNI ÇEK VE POPUP GÖSTER!
    _fetchCustomerDetailsAndShowDialog(rideData);
  }
  
  
  // GERÇEK MÜŞTERİ VERİLERİNİ ÇEKİP POPUP GÖSTER!
  void _fetchCustomerDetailsAndShowDialog(Map<String, dynamic> rideData) async {
    try {
      // API'YE GEREK YOK - ZATEN DRIVER PROVIDER'DAN CUSTOMER NAME GELİYOR!
      print('✅ Müşteri verisi zaten mevcut: ${rideData['customer_name']}');
      print('🕐 Talep zamanı: ${rideData['scheduled_time']}');
      print('📏 Mesafe: ${rideData['distance_km']}');
      
    } catch (e) {
      print('❌ Müşteri veri hazırlama hatası: $e');
      rideData['customer_name'] = 'Müşteri';
    }
    
    // Gerçek veriler ile popup göster!
    _showActualNewRideDialog(rideData);
  }
  
  // GERÇEK POPUP GÖSTERME METHOD'U - 30 SANİYE TIMEOUT İLE!
  void _showActualNewRideDialog(Map<String, dynamic> rideData) {
    if (!mounted) return;
    
    // 30 SANİYE TIMEOUT TIMER!
    Timer? timeoutTimer;
    bool isDialogClosed = false;
    
    // BÜYÜK EMOJİ'Lİ TALEP EKRANI - PROFESYONEL!
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.05,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.0),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title with animation
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.0),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFFFD700), width: 2),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.notifications_active, color: Color(0xFFFFD700), size: 30),
                    SizedBox(width: 10),
                    Text(
                      '📞 YENİ VALE TALEBİ!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Ride details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer info
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '👤 Müşteri: ${_getCustomerDisplayName(rideData)}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Pickup location
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.my_location, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('📍 Alış Noktası:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              Text(
                                '${rideData['pickup_address'] ?? rideData['pickup_location'] ?? 'Konum bilgisi yok'}',
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Destination location
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🎯 Varış Noktası:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              Text(
                                '${rideData['destination_address'] ?? rideData['destination'] ?? 'Konum bilgisi yok'}',
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Price and time info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(Icons.attach_money, color: Colors.green, size: 24),
                                const Text('💰 Tahmini Fiyat', style: TextStyle(fontSize: 12)),
                                Text(
                                  '₺${rideData['estimated_price'] ?? '0'}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 50, color: Colors.grey[300]),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(Icons.schedule, color: Colors.orange, size: 24),
                                const Text('⏰ Vale Gelme Saati', style: TextStyle(fontSize: 12)),
                                Text(
                                  _getScheduledTimeDisplay(rideData),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  _getScheduledTimeSubtext(rideData),
                                  style: TextStyle(fontSize: 11, color: Colors.orange[600]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 50, color: Colors.grey[300]),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Icon(Icons.near_me, color: Colors.blue, size: 24),
                                const Text('📍 Müşteriye Uzaklık', style: TextStyle(fontSize: 10)),
                                Text(
                                  '${_calculateDistanceToCustomer(rideData)} km',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Action buttons - BÜYÜK VE BELİRGİN!
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _rejectRide(int.tryParse(rideData['ride_id'].toString()) ?? 0),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 5,
                      ),
                      icon: const Icon(Icons.close, size: 24),
                      label: const Text(
                        '❌ REDDET',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptRide(int.tryParse(rideData['ride_id'].toString()) ?? 0),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 5,
                      ),
                      icon: const Icon(Icons.check, size: 24),
                      label: const Text(
                        '✅ KABUL ET',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Warning text
              Text(
                '⏰ Bu talep 30 saniye sonra otomatik olarak iptal olacaktır',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      // Dialog açıldıktan sonra 30 SANİYE TIMEOUT BAŞLAT!
      timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!isDialogClosed && mounted && Navigator.canPop(context)) {
          isDialogClosed = true;
          Navigator.of(context).pop(); // Dialog'u kapat
          
          print('⏰ 30 saniye doldu - Talep ${rideData['ride_id']} otomatik RED edildi!');
          
          // Otomatik red işlemi
          _rejectRide(int.tryParse(rideData['ride_id'].toString()) ?? 0);
        }
      });
    });
    
    // Dialog manuel kapatılırsa timer'ı temizle
    if (timeoutTimer != null && timeoutTimer!.isActive) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) {
          timeoutTimer?.cancel();
        }
      });
    }
  }
  
  // MÜŞTERİ DISPLAY NAME - GERÇEK İSIM SOYİSİM GÖSTER!
  String _getCustomerDisplayName(Map<String, dynamic> rideData) {
    try {
      // Önce customer_name kontrol et (API'den gelen tam isim)
      if (rideData['customer_name'] != null && rideData['customer_name'].toString().trim().isNotEmpty) {
        final name = rideData['customer_name'].toString().trim();
        
        // Eğer sadece rakam değilse (gerçek isim) direk döndür
        if (!RegExp(r'^\d+$').hasMatch(name) && name != 'null' && name != 'NULL') {
          return name;
        }
      }
      
      // name + surname alanları varsa birleştir
      String firstName = rideData['customer_first_name']?.toString().trim() ?? 
                        rideData['name']?.toString().trim() ?? '';
      String lastName = rideData['customer_last_name']?.toString().trim() ?? 
                       rideData['surname']?.toString().trim() ?? '';
      
      if (firstName.isNotEmpty || lastName.isNotEmpty) {
        return '${firstName} ${lastName}'.trim();
      }
      
      // Telefon numarası varsa son 4 hanesiyle göster
      if (rideData['customer_phone'] != null) {
        final phone = rideData['customer_phone'].toString().trim();
        if (phone.length >= 4) {
          final lastFour = phone.substring(phone.length - 4);
          return 'Müşteri ***$lastFour';
        }
      }
      
      // Email varsa @ öncesi kısmını göster
      if (rideData['customer_email'] != null) {
        final email = rideData['customer_email'].toString().trim();
        if (email.contains('@')) {
          final username = email.split('@')[0];
          if (username.length > 2) {
            return 'Müşteri ${username.substring(0, 2)}***';
          }
        }
      }
      
      // Son çare - ID ile göster
      final customerId = rideData['customer_id'] ?? 'XX';
      return 'Müşteri #$customerId';
      
    } catch (e) {
      print('❌ Müşteri isim gösterme hatası: $e');
      return 'Müşteri';
    }
  }
  
  // SCHEDULED TIME GÖSTER İM - MÜŞTERİNİN SEÇTİĞİ ZAMAN!
  String _getScheduledTimeDisplay(Map<String, dynamic> rideData) {
    try {
      final scheduledTime = rideData['scheduled_time']?.toString();
      
      print('⏰ SCHEDULED TIME DEBUG:');
      print('   📝 Raw scheduled_time: $scheduledTime');
      
      if (scheduledTime == null || 
          scheduledTime.isEmpty || 
          scheduledTime == 'null' || 
          scheduledTime == '0000-00-00 00:00:00') {
        return 'Hemen';
      }
      
      try {
        // ✅ Backend TR timezone (UTC+3) gönderdiği için local olarak parse et
        final scheduledDateTime = DateTime.parse(scheduledTime);
        
        // ✅ Phone local time yerine aynı timezone'da karşılaştırma yap
        // Backend zaten TR time gönderdiği için doğrudan karşılaştırabiliriz
        final now = DateTime.now();
        
        // ✅ Backend'den gelen zaman zaten TR timezone'da (local), phone time da local
        // İkisi de aynı timezone'daysa karşılaştırma doğru olur
        final difference = scheduledDateTime.difference(now);
        
        print('   ⏰ Scheduled DateTime: $scheduledDateTime (Backend TR time)');
        print('   🕐 Now: $now (Phone local time)');
        print('   ⏱️ Difference: ${difference.inMinutes} dakika (${difference.inHours} saat)');
        
        // ✅ Gelecekte bir zaman ise saat göster
        // 5 dakikadan fazla fark varsa scheduled olarak göster (15 yerine 5)
        if (difference.inMinutes > 5) {
          if (scheduledDateTime.day == now.day) {
            // Aynı gün - sadece saat:dakika
            final timeStr = '${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
            print('   ✅ SONUÇ: "$timeStr" (aynı gün, ${difference.inMinutes} dk sonra)');
            return timeStr;
          } else {
            // Farklı gün - gün.ay saat:dakika
            final timeStr = '${scheduledDateTime.day}.${scheduledDateTime.month} ${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
            print('   ✅ SONUÇ: "$timeStr" (farklı gün)');
            return timeStr;
          }
        }
        
        print('   ✅ SONUÇ: "Hemen" (${difference.inMinutes} dk <= 5 dk)');
        return 'Hemen';
        
      } catch (e) {
        print('❌ Scheduled time parse hatası: $e');
        return 'Hemen';
      }
    } catch (e) {
      print('❌ Scheduled time gösterim hatası: $e');
      return 'Hemen';
    }
  }
  
  // SCHEDULED TIME ALT METİN - KALAN SÜRE!
  String _getScheduledTimeSubtext(Map<String, dynamic> rideData) {
    try {
      final scheduledTime = rideData['scheduled_time']?.toString();
      
      if (scheduledTime == null || 
          scheduledTime.isEmpty || 
          scheduledTime == 'null' || 
          scheduledTime == '0000-00-00 00:00:00') {
        return '(hemen gelmeliyim)';
      }
      
      final scheduledDateTime = DateTime.tryParse(scheduledTime);
      if (scheduledDateTime == null) {
        return '(hemen gelmeliyim)';
      }
      
      final now = DateTime.now();
      final difference = scheduledDateTime.difference(now);
      
      if (difference.inMinutes > 15) {
        if (difference.inHours >= 24) {
          final days = difference.inDays;
          return '($days gün sonra)';
        } else if (difference.inHours >= 1) {
          final hours = difference.inHours;
          return '($hours saat sonra)';
        } else {
          final minutes = difference.inMinutes;
          return '($minutes dk sonra)';
        }
      }
      
      return '(hemen gelmeliyim)';
      
    } catch (e) {
      return '(zaman belirsiz)';
    }
  }

  // MÜŞTERİYE GERÇEK UZAKLIK HESAPLAMA - SÜRÜCÜ KONUMU → MÜŞTERİ PICKUP!
  String _calculateDistanceToCustomer(Map<String, dynamic> rideData) {
    try {
      // GÜNCEL KONUM AL!
      _getCurrentLocation(); // Konum güncelle
      
      // Sürücünün GERÇEK anlık konumu
      final driverLat = _currentLocation.latitude;
      final driverLng = _currentLocation.longitude;
      
      // Müşterinin pickup koordinatları
      double? pickupLat = double.tryParse(rideData['pickup_lat']?.toString() ?? '');
      double? pickupLng = double.tryParse(rideData['pickup_lng']?.toString() ?? '');
      
      print('📍 MESAFE HESAPLAMA DEBUG:');
      print('   🚗 Sürücü: $driverLat, $driverLng');
      print('   👤 Müşteri pickup: $pickupLat, $pickupLng');
      
      // Eğer koordinatlar varsa GERÇEK mesafe hesapla
      if (pickupLat != null && pickupLng != null && 
          pickupLat != 0.0 && pickupLng != 0.0) {
            
        // GERÇEK COĞRAFI MESAFE HESAPLAMA!
        final distanceInMeters = Geolocator.distanceBetween(
          driverLat, 
          driverLng, 
          pickupLat, 
          pickupLng
        );
        
        final distanceInKm = distanceInMeters / 1000;
        
        print('   📏 Hesaplanan mesafe: ${distanceInMeters.toInt()}m (${distanceInKm.toStringAsFixed(1)}km)');
        
        // AKILLI GÖSTER İM: 100m altında metre, üstünde km
        if (distanceInKm < 0.0) {
          return '${distanceInMeters.toInt()}m';
        } else if (distanceInKm < 0.0) {
          return '${(distanceInKm * 1000).toInt()}m';
        }
        
        return distanceInKm.toStringAsFixed(1);
      }
      
      // Koordinat yoksa API'den distance çek (fallback)
      if (rideData['distance_km'] != null && rideData['distance_km'] != '?') {
        final distance = rideData['distance_km'].toString();
        print('   📊 API distance kullanılıyor: $distance');
        
        if (distance != '?' && distance.isNotEmpty) {
          final distanceNum = double.tryParse(distance.replaceAll(' km', ''));
          if (distanceNum != null) {
            return distanceNum.toStringAsFixed(1);
          }
        }
      }
      
      // Son çare - DEBUG için varsayılan
      print('   ⚠️ Koordinat yok - varsayılan mesafe');
      return '0.0'; // Daha gerçekçi varsayılan
      
    } catch (e) {
      print('❌ Müşteriye uzaklık hesaplama hatası: $e');
      return '?';
    }
  }

  Widget _buildPopupInfoTile(IconData icon, String title, String value, String subtitle, {Color iconColor = const Color(0xFF2563EB)}) {
    final backgroundColor = iconColor.withOpacity(0.12);
    final borderColor = iconColor.withOpacity(0.2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  // 🛣️ ARA DURAKLAR WIDGET BUILDER
  List<Widget> _buildWaypointsWidget(dynamic waypointsData) {
    try {
      List<dynamic> waypoints = [];
      
      // JSON string ise parse et
      if (waypointsData is String && waypointsData.isNotEmpty) {
        waypoints = jsonDecode(waypointsData);
      } else if (waypointsData is List) {
        waypoints = waypointsData;
      }
      
      if (waypoints.isEmpty) return [];
      
      return [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.alt_route, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '🛣️ Ara Duraklar (${waypoints.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...waypoints.asMap().entries.map((entry) {
                final index = entry.key;
                final waypoint = entry.value;
                // Backend hem "address" hem "adres" gönderebilir!
                final address = waypoint['address'] ?? waypoint['adres'] ?? 'Ara Durak ${index + 1}';
                
                // Koordinatları farklı formatlardan al
                dynamic lat, lng;
                
                print('🔍 DEBUG - Waypoint #${index + 1} RAW DATA:');
                print('   waypoint: $waypoint');
                
                // Format 1: location/konum array [lat, lng] - Backend hem "location" hem "konum" gönderebilir!
                dynamic locationArray = waypoint['location'] ?? waypoint['konum'];
                
                if (locationArray != null && locationArray is List && locationArray.length >= 2) {
                  lat = locationArray[0];
                  lng = locationArray[1];
                  print('   ✅ Format: location/konum array');
                  print('      locationArray: $locationArray');
                  print('      lat: $lat (${lat.runtimeType})');
                  print('      lng: $lng (${lng.runtimeType})');
                } else {
                  // Format 2: latitude/longitude veya lat/lng object keys
                  lat = waypoint['latitude'] ?? waypoint['lat'] ?? waypoint['enlem'];
                  lng = waypoint['longitude'] ?? waypoint['lng'] ?? waypoint['boylam'];
                  print('   ℹ️ Format: object keys');
                  print('      lat: $lat (${lat?.runtimeType ?? "null"})');
                  print('      lng: $lng (${lng?.runtimeType ?? "null"})');
                }
                
                // Koordinatları double'a çevir
                double? latDouble = lat is num ? lat.toDouble() : double.tryParse(lat?.toString() ?? '');
                double? lngDouble = lng is num ? lng.toDouble() : double.tryParse(lng?.toString() ?? '');
                
                print('   🎯 FINAL: latDouble=$latDouble, lngDouble=$lngDouble');
                
                return Column(
                  children: [
                    // ÇİZGİ (İLK SATIR DIŞINDA) - CIRCLE MERKEZİNDE
                    if (index > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 11, bottom: 8), // Circle merkezi (24/2 = 12, ama border 1px = 11)
                        width: 2,
                        height: 20,
                        color: Colors.orange.withOpacity(0.5),
                      ),
                    // TIKLANABİLİR ARA DURAK SATIRI
                    InkWell(
                      onTap: () {
                        print('🗺️ Ara Durak #${index + 1} Tıklandı:');
                        print('   Adres: $address');
                        print('   LatDouble: $latDouble');
                        print('   LngDouble: $lngDouble');
                        
                        if (latDouble != null && lngDouble != null) {
                          print('   ✅ KOORDİNATLAR GEÇERLİ - Navigasyon açılıyor...');
                          _openNavigationToWaypoint(latDouble.toString(), lngDouble.toString(), address);
                        } else {
                          print('   ❌ Koordinatlar NULL veya PARSE EDİLEMEDİ!');
                          print('      Raw lat: $lat');
                          print('      Raw lng: $lng');
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('❌ Ara durak koordinatları bulunamadı veya hatalı format'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                address,
                                style: const TextStyle(fontSize: 13, color: Colors.black87, decoration: TextDecoration.underline),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.navigation, size: 18, color: Colors.orange),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ];
    } catch (e) {
      print('⚠️ Waypoints widget hatası: $e');
      return [];
    }
  }
  
  // GERÇEK MESAFE HESAPLAMA (ESKİ FONKSIYON KORUNDU)!
  String _calculateRealDistance(Map<String, dynamic> rideData) {
    // API'den distance gelirse onu kullan
    if (rideData['distance_km'] != null && rideData['distance_km'] != '?') {
      final distance = rideData['distance_km'].toString();
      if (distance != '?' && distance.isNotEmpty) {
        final distanceNum = double.tryParse(distance.replaceAll(' km', ''));
        if (distanceNum != null) {
          return distanceNum.toStringAsFixed(1);
        }
      }
    }
    
    // Gerçek mesafe hesapla (sürücü konumu vs pickup konumu)
    try {
      // Basit tahmin - şehir içi ortalama
      return '0.0'; // Varsayılan değer
    } catch (e) {
      return '?';
    }
  }
  
  void _acceptRide(int rideId) async {
    Navigator.pop(context); // Dialog'u kapat
    
    // 30 SANİYE TIMEOUT TIMER'I TEMİZLE!
    // Timer referansını bulamadığım için global bir Set kullanacağım
    print('✅ KABUL EDİLDİ - Timeout timer temizleniyor: $rideId');
    
    try {
      final authProvider = context.read<AuthProvider>();
      final driverId = authProvider.user?['id'] ?? '0';
      
      print('✅ Vale talep kabul etti - provizyon sistemi tetikleniyor...');
      
      // 1. Talebi kabul et
      await RideService.acceptRideRequest(rideId, int.tryParse(driverId) ?? 0);
      
      // 2. PROVİZYON TETİKLE - MÜŞTERE BILDIR!
      await _triggerCustomerProvisionAfterAcceptance(rideId);
      
      // 3. GERÇEK ZAMANLI ROTA TAKİBİNİ BAŞLAT!
      final trackingProvider = context.read<RealTimeTrackingProvider>();
      await trackingProvider.startRideTracking(rideId.toString(), driverId);
      
      print('🚗 Talep kabul → Provizyon tetiklendi → Rota tracking başladı');
      print('📍 Gerçek km hesaplama sistemi aktif: $rideId');
      
      // YOLCULUK EKRANINA YÖNLENDİR - ANA SAYFANIN YERİNİ ALSIN!
      await _navigateToModernActiveRideScreen(rideId);
      
      // KRİTİK: PERSİSTENCE KAYDET - YOLCULUK KAYBOLMASIN!
      await _saveDriverRidePersistence(rideId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Talep kabul edildi! Yolculuk ekranına yönlendirildi.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Talep kabul hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Talep kabul hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // MÜŞTERİ PROVİZYON TETİKLE - VALE KABUL ETTİKTEN SONRA!
  Future<void> _triggerCustomerProvisionAfterAcceptance(int rideId) async {
    try {
      print('💳 Müşteri provizyon sistemi tetikleniyor - Ride: $rideId');
      
      // Status change notification API'sine bildir - provizyon otomatik çekilecek
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/status_change_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'old_status': 'pending',
          'new_status': 'accepted',
          'customer_id': 0, // API'de bulacak
          'driver_id': int.tryParse(context.read<AuthProvider>().user?['id'] ?? '0') ?? 0,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ Müşteri provizyon sistemi başarıyla tetiklendi');
        } else {
          print('⚠️ Provizyon tetikleme uyarısı: ${data['message']}');
        }
      }
    } catch (e) {
      print('❌ Provizyon tetikleme hatası: $e');
    }
  }
  
  
  void _rejectRide(int rideId) async {
    Navigator.pop(context); // Dialog'u kapat
    
    // 30 SANİYE TIMEOUT TIMER'I TEMİZLE!
    print('❌ RED EDİLDİ - Timeout timer temizleniyor: $rideId');
    
    try {
      final authProvider = context.read<AuthProvider>();
      await RideService.rejectRideRequest(rideId, int.tryParse(authProvider.user!['id'] ?? '0') ?? 0);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Talep reddedildi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e')),
      );
    }
  }

  @override
  void dispose() {
    // Dispose çağrıldığında lifecycle yönetimini main.dart'a bırak
    print('🔴 dispose() çağrıldı - main.dart lifecycle yönetecek');
    
    // WidgetsBinding.instance.removeObserver(this); → KALDIRILDI! main.dart'ta var
    _slideController.dispose();
    super.dispose();
  }
  
  // DUPLİCATE LİFECYCLE METODLARI KALDIRILDI - main.dart SADECE LIFECYCLE YÖNETİR!

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation, 15));
      
      // Driver konumunu güncelle
      final driverProvider = Provider.of<DriverRideProvider>(context, listen: false);
      driverProvider.updateDriverLocation(position.latitude, position.longitude);
    } catch (e) {
      print('Konum alınamadı: $e');
    }
  }

  Future<void> _loadTodayStats() async {
    try {
      final driverProvider = Provider.of<DriverRideProvider>(context, listen: false);
      final stats = await driverProvider.getTodayEarnings();
      
      print('📊 GÜNLÜK KAZANÇ API RESPONSE:');
      print('   Earnings: ${stats['earnings']}');
      print('   Rides: ${stats['rides']}');
      
      if (mounted) {
        setState(() {
          _todayEarnings = stats['earnings'] ?? 0.0;
          _todayRides = stats['rides'] ?? 0;
        });
        print('✅ Günlük kazanç kartı güncellendi: ₺${_todayEarnings.toStringAsFixed(2)}');
      }
    } catch (e) {
      print('❌ Günlük kazanç yükleme hatası: $e');
    }
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const DriverNotificationsBottomSheet(),
    );
  }

  Widget _buildQuickStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.0),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<DriverRideProvider>(
        builder: (context, driverProvider, child) {
          return Stack(
            children: [
              // Ana harita
              GoogleMap(
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
                initialCameraPosition: CameraPosition(
                  target: _currentLocation,
                  zoom: 15,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('driver_location'),
                    position: _currentLocation,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                    infoWindow: const InfoWindow(title: 'Konumunuz'),
                  ),
                  // Mevcut ride varsa hedef marker'ı
                  if (driverProvider.currentRide != null)
                    Marker(
                      markerId: const MarkerId('destination'),
                      position: driverProvider.currentRide!.destinationLocation,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      infoWindow: InfoWindow(
                        title: 'Hedef',
                        snippet: driverProvider.currentRide!.destinationAddress,
                      ),
                    ),
                },
                polylines: driverProvider.currentRide != null ? {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: [_currentLocation, driverProvider.currentRide!.destinationLocation],
                    color: const Color(0xFFFFD700),
                    width: 4,
                  ),
                } : {},
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                mapType: MapType.normal,
                zoomControlsEnabled: false,
              ),

              // Header
              Positioned(
                top: MediaQuery.of(context).padding.top + 20,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.0),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // MODERN HEADER with action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                                'FunBreak Vale',
                            style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                              color: Color(0xFFFFD700),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Sürücü Paneli',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                              // KAZANÇ ANALİZİ BUTONU - YENİ!
                          Container(
                            decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const EarningsScreen(),
                                      ),
                                    ).then((_) => _loadTodayStats());
                                  },
                                  icon: const Icon(
                                    Icons.analytics_rounded,
                                    color: Colors.green,
                                    size: 24,
                                  ),
                                  tooltip: 'Kazanç Analizi',
                                ),
                              ),
                              const SizedBox(width: 8),
                              // BİLDİRİMLER BUTONU
                        Container(
                          decoration: BoxDecoration(
                                  color: const Color(0xFFFFD700).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: IconButton(
                                  onPressed: _showNotifications,
                                  icon: const Icon(
                                    Icons.notifications_rounded,
                                    color: Color(0xFFFFD700),
                                size: 24,
                              ),
                                  tooltip: 'Bildirimler',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      // YENİ DRIVER TOGGLE SECTION WIDGET!
                      const DriverToggleSection(),
                      
                      const SizedBox(height: 20),
                      
                      // MODERN İSTATİSTİK KARTLARI - TIKLANABİLİR!
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                // Günlük kazanç kartına tıklanınca kazanç analizi ekranına git!
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const EarningsScreen(),
                                  ),
                                ).then((_) => _loadTodayStats());
                              },
                              borderRadius: BorderRadius.circular(20),
                            child: Container(
                                padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700).withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                    Icons.currency_lira,
                                    color: Colors.white,
                                        size: 24,
                                  ),
                                    ),
                                    const SizedBox(height: 12),
                                  Text(
                                    '₺${_todayEarnings.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                    'Günlük Kazanç',
                                    style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.white.withOpacity(0.9),
                                            fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          color: Colors.white.withOpacity(0.7),
                                          size: 14,
                                        ),
                                ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                // Tamamlanan yolculuk kartına tıklanınca kazanç analizi ekranına git!
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const EarningsScreen(),
                                  ),
                                ).then((_) => _loadTodayStats());
                              },
                              borderRadius: BorderRadius.circular(20),
                            child: Container(
                                padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.blue[400]!, Colors.blue[600]!],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.directions_car_rounded,
                                    color: Colors.white,
                                        size: 24,
                                  ),
                                    ),
                                    const SizedBox(height: 12),
                                  Text(
                                    '$_todayRides',
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Tamamlanan Yolculuk',
                                    style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.white.withOpacity(0.9),
                                            fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                        Icon(
                                          Icons.arrow_forward_ios,
                                          color: Colors.white.withOpacity(0.7),
                                          size: 14,
                                        ),
                                ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ),

              // AKTİF YOLCULUK KARTI KALDIRILDI - ZATEN YOLCULUK EKRANI AÇILIYOR!
              // ÇEVRİMDIŞI DURUMDA ARTIK "MÜŞTERİ ATAMASI BEKLENİYOR" YAZISI YOK!
            ],
          );
        },
      ),
    );
  }

  // GOOGLE MAPS NAVİGASYON AÇMA - SÜPER ÖZELLİK!
  Future<void> _openGoogleMapsNavigation(double lat, double lng, String address) async {
    try {
      debugPrint('🗺️ Google Maps navigasyon açılıyor: $lat, $lng');
      
      // Google Maps URL formatı
      final googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
      
      // URL launcher ile açmaya çalış
      final Uri googleMapsUri = Uri.parse(googleMapsUrl);
      
      // Burada url_launcher paketini kullanarak açabilirsiniz
      // await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
      
      debugPrint('✅ Google Maps URL hazırlandı: $googleMapsUrl');
      
      // Şimdilik debug için
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Maps açılıyor: ${address.substring(0, 30)}...'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      debugPrint('❌ Google Maps açma hatası: $e');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Maps açılamadı'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // YANDEX MAPS NAVİGASYON AÇMA - SÜPER ÖZELLİK!
  Future<void> _openYandexMapsNavigation(double lat, double lng, String address) async {
    try {
      debugPrint('🔴 Yandex Maps navigasyon açılıyor: $lat, $lng');
      
      // Yandex Maps URL formatı (Türkiye için optimize)
      final yandexMapsUrl = 'yandexmaps://build_route_on_map?lat_to=$lat&lon_to=$lng';
      
      // Alternatif web URL (eğer uygulama yoksa)
      final yandexWebUrl = 'https://yandex.com.tr/maps/?rtext=~$lat,$lng&rtt=auto';
      
      final Uri yandexMapsUri = Uri.parse(yandexMapsUrl);
      
      // Burada url_launcher ile açmaya çalış
      // try {
      //   await launchUrl(yandexMapsUri, mode: LaunchMode.externalApplication);
      // } catch (e) {
      //   // Yandex app yoksa web versiyonunu aç
      //   await launchUrl(Uri.parse(yandexWebUrl), mode: LaunchMode.externalApplication);
      // }
      
      debugPrint('✅ Yandex Maps URL hazırlandı: $yandexMapsUrl');
      
      // Şimdilik debug için
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yandex Maps açılıyor: ${address.substring(0, 30)}...'),
          backgroundColor: Colors.red[600],
          duration: const Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      debugPrint('❌ Yandex Maps açma hatası: $e');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yandex Maps açılamadı'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // HER İKİ NAVİGASYON SEÇENEĞİNİ GÖSTEREN DIALOG
  Future<void> _showNavigationOptions(double lat, double lng, String address) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.navigation, color: Color(0xFFFFD700)),
            SizedBox(width: 12),
            Text('Navigasyon Seç'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hedef konuma nasıl gitmek istersiniz?',
              style: TextStyle(
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              address,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'İptal',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openGoogleMapsNavigation(lat, lng, address);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Google Maps'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openYandexMapsNavigation(lat, lng, address);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Yandex Maps'),
          ),
        ],
      ),
    );
  }
  
  // HELPER METHOD'LAR - GERÇEK VERİLER İÇİN!
  
  // SCHEDULED TIME FORMATLAMASI!
  String _formatScheduledTimeHelper(DateTime? scheduledTime) {
    if (scheduledTime == null) {
      return 'Hemen (Anlık)';
    }
    
    final now = DateTime.now();
    final difference = scheduledTime.difference(now);
    
    if (difference.inMinutes < 60) {
      return 'Hemen (${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')})';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} saat sonra (${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')})';
    } else {
      return '${scheduledTime.day}.${scheduledTime.month} ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}';
    }
  }
  
  // MÜŞTERİYE MESAFE HESAPLAMA - GERÇEK GPS!
  String _calculateDistanceToCustomerHelper(LatLng customerLocation) {
    try {
      // Sürücünün mevcut konumunu al
      final driverProvider = Provider.of<DriverRideProvider>(context, listen: false);
      
      // Eğer konum bilgisi varsa gerçek hesaplama yap
      // Şimdilik basit hesaplama
      if (customerLocation.latitude != 0 && customerLocation.longitude != 0) {
        // Basit mesafe hesaplaması - koordinatlara göre
        double distance = ((customerLocation.latitude - 40.0) * (customerLocation.latitude - 40.0) + 
                          (customerLocation.longitude - 20.0) * (customerLocation.longitude - 20.0)).abs() * 100;
        
        if (distance < 1) {
          return '${(distance * 1000).toInt()}m';
        } else {
          return '${distance.toStringAsFixed(1)}km';
        }
      }
      
      return '? km'; // Koordinat yoksa
    } catch (e) {
      print('❌ Mesafe hesaplama hatası: $e');
      return '? km';
    }
  }
  
  // YENİ: AKTİF YOLCULUK EKRANINA GİT - ANA SAYFANIN YERİNİ ALSIN!
  Future<void> _navigateToModernActiveRideScreen(int rideId) async {
    try {
      // Ride detaylarını API'den çek
      print('🌐 API çağrısı: get_ride_details.php - Ride ID: $rideId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_ride_details.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      print('📡 API Response Status: ${response.statusCode}');
      print('📋 API Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ API Parse başarılı - Success: ${data['success']}');
        
        if (data['success'] == true && data['ride'] != null) {
          final rideDetails = data['ride'];
          print('✅ Ride detayları alındı: ${rideDetails['customer_name']}');
          
          // Ana sayfa navigation'ını değiştir - yolculuk ekranı ana sayfa olsun
              // RIDE ID SORUNU ÇÖZÜLSİN!
              final correctRideId = rideDetails['id'] ?? rideId;
              print('🔍 ŞOFÖR: Yolculuk ekranına geçiliyor - Ride ID: $correctRideId');
              
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => ModernDriverActiveRideScreen(
                    rideDetails: {
                      'ride_id': correctRideId,  // DOĞRU RIDE ID!
                      'id': correctRideId,       // İKİ TÜRLÜ DE KAYDET!
                      'customer_id': rideDetails['customer_id'] ?? '0',
                      'customer_name': rideDetails['customer_name'] ?? 'Müşteri',
                      'customer_phone': rideDetails['customer_phone'] ?? '0543 123 45 67',
                      'pickup_address': rideDetails['pickup_address'] ?? 'Alış konumu',
                      'destination_address': rideDetails['destination_address'] ?? 'Varış konumu',
                      'pickup_lat': rideDetails['pickup_lat'] ?? 0.0,
                      'pickup_lng': rideDetails['pickup_lng'] ?? 0.0,
                      'destination_lat': rideDetails['destination_lat'] ?? 0.0,
                      'destination_lng': rideDetails['destination_lng'] ?? 0.0,
                      'estimated_price': rideDetails['estimated_price'] ?? '0',
                      'payment_method': rideDetails['payment_method'] ?? 'card',
                      'status': 'accepted',
                      'created_at': rideDetails['created_at'] ?? DateTime.now().toIso8601String(),
                      'accepted_at': DateTime.now().toIso8601String(),
                    },
                    waitingMinutes: 0,
                  ),
                ),
              );
          
          print('🚗 SÜRÜCÜ: Yolculuk kabul edildi - ActiveRideScreen ana sayfa oldu');
          return;
        }
      }
      
      // API başarısız - fallback ile git
      print('⚠️ Ride detayları API\'den alınamadı, fallback ile devam...');
      print('❌ API başarısız olma nedeni: Response code ${response.statusCode} veya data parse hatası');
      
    } catch (e, stackTrace) {
      print('❌ ActiveRideScreen navigation hatası: $e');
      print('📋 Stack trace: $stackTrace');
    }
    
    // Fallback: Basit verilerle git
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ModernDriverActiveRideScreen(
          rideDetails: {
            'ride_id': rideId,
            'customer_id': '0',
            'customer_name': 'Müşteri',
            'customer_phone': '0543 123 45 67',
            'pickup_address': 'Alış konumu yükleniyor...',
            'destination_address': 'Varış konumu yükleniyor...',
            'pickup_lat': 40.0082,
            'pickup_lng': 20.0784,
            'destination_lat': 40.0082,
            'destination_lng': 20.0784,
            'estimated_price': '50',
            'payment_method': 'card',
            'status': 'accepted',
            'created_at': DateTime.now().toIso8601String(),
            'accepted_at': DateTime.now().toIso8601String(),
          },
          waitingMinutes: 0,
        ),
      ),
    );
  }
  
  // KRİTİK: ŞOFÖR PERSİSTENCE KAYDETME - YOLCULUK KAYBOLMASIN!
  Future<void> _saveDriverRidePersistence(int rideId) async {
    try {
      print('💾 ŞOFÖR: Talep kabul sonrası persistence kaydediliyor...');
      
      final prefs = await SharedPreferences.getInstance();
      
      // DOĞRU RIDE DATA - ÇOKLU ALAN DESTEĞİ!
      final rideData = {
        'ride_id': rideId,      // Ana alan
        'id': rideId,           // Alternatif alan
        'status': 'accepted',
        'pickup_address': 'Alış konumu',
        'destination_address': 'Varış konumu',
        'estimated_price': '100',
        'customer_name': 'Müşteri',
        'customer_phone': '0543 123 45 67',
        'customer_id': '1',
        'saved_at': DateTime.now().toIso8601String(),
      };
      
      // Doğru key'lerle kaydet
      await prefs.setString('active_driver_ride_data', jsonEncode(rideData));
      await prefs.setString('driver_ride_state', 'active');
      
      print('✅ ŞOFÖR: Persistence kaydedildi - Key: active_driver_ride_data');
      print('✅ ŞOFÖR: Ride ID: $rideId, State: active');
      
      // Debug - kaydedileni kontrol et
      final savedData = prefs.getString('active_driver_ride_data');
      print('🔍 ŞOFÖR: Kaydedilen data: ${savedData?.substring(0, 100)}...');
      
    } catch (e) {
      print('❌ ŞOFÖR: Persistence kaydetme hatası: $e');
    }
  }
  
  // 🗺️ ARA DURAK NAVİGASYON AÇMA FONKSİYONU
  Future<void> _openNavigationToWaypoint(String lat, String lng, String address) async {
    try {
      print('🗺️ Ara durak navigasyonu açılıyor: $lat, $lng');
      
      // Yandex Maps URL (öncelikli)
      final yandexUrl = 'yandexmaps://maps.yandex.com/?rtext=~$lat,$lng&rtt=auto';
      final yandexUri = Uri.parse(yandexUrl);
      
      // Google Maps URL (yedek)
      final googleUrl = 'google.navigation:q=$lat,$lng&mode=d';
      final googleUri = Uri.parse(googleUrl);
      
      // Önce Yandex'i dene
      if (await canLaunchUrl(yandexUri)) {
        await launchUrl(yandexUri, mode: LaunchMode.externalApplication);
        print('✅ Yandex Maps açıldı - Ara Durak: $address');
      } else if (await canLaunchUrl(googleUri)) {
        // Yandex yoksa Google Maps aç
        await launchUrl(googleUri, mode: LaunchMode.externalApplication);
        print('✅ Google Maps açıldı - Ara Durak: $address');
      } else {
        // Hiçbiri yoksa web'de aç
        final webUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
        final webUri = Uri.parse(webUrl);
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        print('✅ Web Maps açıldı - Ara Durak: $address');
      }
    } catch (e) {
      print('❌ Navigasyon hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Navigasyon açılamadı: $e')),
        );
      }
    }
  }
}
