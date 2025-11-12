import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http; // CLEANUP API İÇİN!
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/ride.dart';
import 'admin_api_provider.dart';
import '../services/location_service.dart';
import '../services/location_tracking_service.dart'; // ✅ KM TRACKING İÇİN!

class DriverRideProvider extends ChangeNotifier {
  final AdminApiProvider _adminApi = AdminApiProvider();
  final LocationService _locationService = LocationService();
  
  List<Ride> _availableRides = [];
  List<Ride> _acceptedRides = [];
  List<Ride> _completedRides = [];
  Ride? _currentRide;
  final List<Map<String, dynamic>> _pendingRideQueue = [];
  final Set<String> _knownAvailableRideIds = {};
  bool _isOnline = false;
  bool _isLoading = false;
  String? _error;
  Timer? _ridePollingTimer;

  DriverRideProvider() {
    _loadDriverStatus();
  }

  Future<void> _loadDriverStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // UYGULAMA HER AÇILIŞTA ÇEVRİMDIŞI BAŞLASIN - KULLANICI TALEBİ!
      _isOnline = false;
      await prefs.setBool('driver_is_online', false);
      
      // İPTAL FLAG KONTROLÜ - ÖNCE BU!
      final cancelledFlag = prefs.getString('ride_cancelled_flag');
      if (cancelledFlag != null) {
        debugPrint('FLAG BULUNDU: Müşteri iptal etmiş - current_ride temizleniyor...');
        await prefs.remove('current_ride');
        await prefs.remove('ride_cancelled_flag');
        _currentRide = null;
        debugPrint('CURRENT RIDE TEMIZLENDI: App açılırken cancelled flag görüldü!');
      }
      
      // AKTİF YOLCULUK DURUMUNU GERI YÜKLE - PERSİSTENCE!
      final savedRideJson = prefs.getString('current_ride');
      if (savedRideJson != null && savedRideJson.isNotEmpty) {
        try {
          final rideData = json.decode(savedRideJson);
          
          // STATUS KONTROL - COMPLETED/CANCELLED İSE TEMİZLE!
          final status = rideData['status']?.toString() ?? '';
          if (status == 'completed' || status == 'cancelled') {
            debugPrint('🗑️ TAMAMLANMIŞ YOLCULUK - Persistence temizleniyor: Status=$status');
            await prefs.remove('current_ride');
            _currentRide = null;
          } else {
            _currentRide = Ride.fromMap(Map<String, dynamic>.from(rideData), rideData['id']?.toString() ?? '0');
            debugPrint('🔄 Aktif yolculuk geri yüklendi: ${_currentRide?.id}, Status: ${_currentRide?.status}');
          }
        } catch (e) {
          debugPrint('❌ Aktif yolculuk geri yükleme hatası: $e');
          await prefs.remove('current_ride');
        }
      }
      
      debugPrint('🔴 SÜRÜCÜ UYGULAMASI: Başlangıçta çevrimdışı, _currentRide=${_currentRide?.id ?? "YOK"}');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Driver status yükleme hatası: $e');
    }
  }
  
  // AKTİF YOLCULUK KAYDETME - PERSİSTENCE!
  Future<void> _saveCurrentRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentRide != null) {
        final rideJson = json.encode(_currentRide!.toMap());
        await prefs.setString('current_ride', rideJson);
        debugPrint('💾 SÜRÜCÜ: Aktif yolculuk kaydedildi');
      } else {
        await prefs.remove('current_ride');
        debugPrint('🗑️ SÜRÜCÜ: Aktif yolculuk temizlendi');
      }
    } catch (e) {
      debugPrint('❌ SÜRÜCÜ: Aktif yolculuk kaydetme hatası: $e');
    }
  }
  
  // DUPLICATE SİLİNDİ - ÜSTTEKİ KULLANILACAK
  
  // CURRENT RIDE TEMİZLEME - YOLCULUK BİTİNCE ÇAĞRILACAK!
  Future<void> clearCurrentRide() async {
    debugPrint('🗑️ PROVIDER: _currentRide temizleniyor...');
    _currentRide = null;
    await _saveCurrentRide(); // Persistence'tan da sil!
    notifyListeners(); // UI güncelle!
    debugPrint('✅ PROVIDER: _currentRide NULL yapıldı - yeni talep aranabilir!');
  }
  
  // Getters
  List<Ride> get availableRides => _availableRides;
  List<Ride> get acceptedRides => _acceptedRides;
  List<Ride> get completedRides => _completedRides;
  Ride? get currentRide => _currentRide;
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<Map<String, dynamic>> consumePendingRideRequests() {
    final queue = List<Map<String, dynamic>>.from(_pendingRideQueue);
    _pendingRideQueue.clear();
    return queue;
  }

  // Driver online/offline durumu - KONUM BİLGİSİ + LOCATION TRACKING!
  Future<void> toggleOnlineStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('admin_user_id');
      
      if (driverId == null) {
        _error = 'Driver ID bulunamadı';
        notifyListeners();
        return;
      }

      _isOnline = !_isOnline;
      await prefs.setBool('driver_is_online', _isOnline);

      debugPrint('🔄 TOGGLE: Sürücü durumu değiştiriliyor - ${_isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');

      // ✅ KRİTİK: ÇEVRİMİÇİ → LocationTracking BAŞLAT, ÇEVRİMDIŞI → DURDUR!
      if (_isOnline) {
        await LocationTrackingService.startLocationTracking();
        debugPrint('✅ TOGGLE: LocationTracking BAŞLATILDI - Arka plan KM tracking aktif!');
      } else {
        await LocationTrackingService.stopLocationTracking();
        debugPrint('⏹️ TOGGLE: LocationTracking DURDURULDU');
      }

      // KONUM BİLGİSİNİ AL VE GÖNDER!
      double? latitude;
      double? longitude;

      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        latitude = position.latitude;
        longitude = position.longitude;
        debugPrint('📍 TOGGLE: Konum bilgisi alındı: $latitude, $longitude');
      } catch (e) {
        debugPrint('❌ TOGGLE: Konum alınamadı: $e');
      }

      // Admin panele driver durumunu konum ile bildir
      await _updateDriverStatusWithLocation(driverId, _isOnline, latitude, longitude);

      if (_isOnline) {
        debugPrint('🔄 TOGGLE: Çevrimiçi oldu - polling başlatılıyor');
        _startRidePollingInternal();
        // LOCATION TRACKING HER ZAMAN ÇALIŞIR - BAŞLATMA GEREKMİYOR
        debugPrint('📍 LOCATION TRACKING zaten çalışıyor - sadece polling başlatıldı');
      } else {
        debugPrint('⏹️ TOGGLE: Çevrimdışı oldu - SADECE polling durduruluyor');
        _stopRidePolling();
        _availableRides.clear(); // Çevrimdışı olunca talepleri temizle
        _pendingRideQueue.clear();
        _knownAvailableRideIds.clear();
        // KRİTİK: LOCATION TRACKING DURDURMUYORUZ - DEVAM ETSİN!
        debugPrint('📍 LOCATION TRACKING DEVAM EDİYOR - çevrimdışı şoför de takip ediliyor');
      }
      
      notifyListeners();
    } catch (e) {
      _error = 'Durum güncellenemedi: $e';
      debugPrint('❌ TOGGLE: Hata - $e');
      notifyListeners();
    }
  }

  // Online durumunu güncelle (dışarıdan çağrılabilir) - DEBUG TRACKING!
  Future<void> updateOnlineStatus(bool isOnline, String driverId) async {
    try {
      print('🔍 === updateOnlineStatus ÇAĞRILDI ===');
      print('   📞 Kim çağırdı: ${StackTrace.current}');
      print('   📍 Driver ID: $driverId');
      print('   🔄 Yeni durum: ${isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');
      print('   📊 Eski durum: ${_isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');
      
      _isOnline = isOnline;
      
      // Admin panele driver durumunu bildir
      await _updateDriverStatus(driverId, isOnline);
      
      if (isOnline) {
        debugPrint('🔄 updateOnlineStatus: Çevrimiçi - SADECE polling başlatılıyor');
        _startRidePollingInternal();
        // LOCATION TRACKING HER ZAMAN ÇALIŞIR - BAŞLATMA GEREKMİYOR
        debugPrint('📍 LOCATION SERVICE zaten çalışıyor');
      } else {
        debugPrint('⏹️ updateOnlineStatus: Çevrimdışı - SADECE polling durduruluyor');
        _stopRidePolling();
        // KRİTİK: LOCATION TRACKING HİÇ DURDURMUYORUZ - DEVAM ETSİN!
        debugPrint('📍 LOCATION SERVICE ÇALIŞMAYA DEVAM EDİYOR - çevrimdışı şoför de takip');
        _availableRides.clear();
        _pendingRideQueue.clear();
        _knownAvailableRideIds.clear();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Online durum güncelleme hatası: $e');
    }
  }

  // Driver durumunu admin panele bildir - KONUM BİLGİSİ İLE!
  Future<void> _updateDriverStatus(String driverId, bool isOnline) async {
    try {
      // MEVCUT KONUM BİLGİSİNİ AL!
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        debugPrint('📍 Mevcut konum alındı: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        debugPrint('⚠️ Konum alınamadı, null ile devam: $e');
        position = null;
      }
      
      await _updateDriverStatusWithLocation(
        driverId, 
        isOnline, 
        position?.latitude, 
        position?.longitude
      );
    } catch (e) {
      debugPrint('❌ Driver status update hatası: $e');
      // Fallback: konum olmadan güncelle
      await _updateDriverStatusWithLocation(driverId, isOnline, null, null);
    }
  }

  // Driver durumunu konum bilgisi ile admin panele bildir - SÜPER DETAYLI DEBUG!
  Future<void> _updateDriverStatusWithLocation(String driverId, bool isOnline, double? latitude, double? longitude) async {
    try {
      debugPrint('📍 === DRIVER STATUS GÜNCELLEME BAŞLADI ===');
      debugPrint('   👨‍🚗 Driver ID: $driverId');
      debugPrint('   🔄 Yeni Durum: ${isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');
      debugPrint('   📍 Konum: ${latitude?.toStringAsFixed(6)}, ${longitude?.toStringAsFixed(6)}');
      debugPrint('   ✅ Available: ${isOnline ? "MÜSAIT" : "MÜSAIT DEĞİL"}');
      debugPrint('   🌐 API URL: https://admin.funbreakvale.com/api/update_driver_status.php');
      
      // ADMİN API İLE KONUM VE DURUM GÜNCELLE - TUTARLI ENTEGRASYON!
      final apiResult = await _adminApi.updateDriverStatus(
        driverId: driverId,
        isOnline: isOnline,
        isAvailable: isOnline, // Online ise available, offline ise unavailable
        latitude: latitude,
        longitude: longitude,
      );
      
      debugPrint('📡 === API RESPONSE ALINDI ===');
      debugPrint('   ✅ Success: ${apiResult['success']}');
      debugPrint('   💬 Message: ${apiResult['message']}');
      debugPrint('   📊 Data: ${apiResult['data']}');
      
      if (apiResult['success'] == true) {
        debugPrint('✅ DRIVER PROVIDER: API başarılı!');
        debugPrint('📊 Database güncellendi: drivers tablosu');
        debugPrint('   🔄 is_online = ${isOnline ? 1 : 0}');
        debugPrint('   ✅ is_available = ${isOnline ? 1 : 0}');
        debugPrint('   📍 latitude = $latitude');
        debugPrint('   📍 longitude = $longitude');
        debugPrint('   ⏰ last_active = NOW()');
        debugPrint('📊 Panel canlı takipte ${isOnline ? "ÇEVRİMİÇİ GÖZÜKECEK" : "ÇEVRİMDIŞI GÖZÜKECEK"}');
        debugPrint('📊 Müşteri uygulamalarında ${isOnline ? "GÖRÜNECEK" : "GİZLENECEK"}');
      } else {
        debugPrint('❌ DRIVER PROVIDER: API hatası!');
        debugPrint('   💬 Hata mesajı: ${apiResult['message']}');
        debugPrint('   🚫 Panel güncellenmeyecek!');
      }
      
      debugPrint('📍 === DRIVER STATUS GÜNCELLEME TAMAMLANDI ===');
    } catch (e) {
      debugPrint('❌ DRIVER PROVIDER: Exception!');
      debugPrint('   🐛 Hata: $e');
      debugPrint('   🚫 Panel güncellenmedi!');
    }
  }

  // Yeni ride taleplerini sürekli kontrol et (public metod)
  Future<void> startRidePolling() async {
    debugPrint('🔄 SÜRÜCÜ: Public ride polling başlatılıyor...');
    _startRidePollingInternal();
  }

  // Yeni ride taleplerini sürekli kontrol et (internal)
  void _startRidePollingInternal() {
    debugPrint('🔄 SÜRÜCÜ: Ride polling başlatılıyor...');
    _ridePollingTimer?.cancel();
    _ridePollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        debugPrint('⏰ SÜRÜCÜ: Polling timer tetiklendi - talep kontrolü');
        _fetchAvailableRides();
      },
    );
    _fetchAvailableRides(); // İlk çağrı
  }

  void _stopRidePolling() {
    _ridePollingTimer?.cancel();
  }
  
  // ESKİ TALEPLERİ TEMİZLEME FONKSİYONU!
  Future<void> _cleanupExpiredRequests() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/cleanup_expired_requests.php?timeout_minutes=1'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final expiredCount = data['expired_count'] ?? 0;
          final deletedCount = data['deleted_count'] ?? 0;
          
          if (expiredCount > 0 || deletedCount > 0) {
            debugPrint('🧹 CLEANUP: $expiredCount expired, $deletedCount deleted');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ CLEANUP hatası (normal): $e');
    }
  }

  // Admin panelden mevcut ride taleplerini getir - ADMİN API İLE DÜZELTİLDİ!
  Future<void> _fetchAvailableRides() async {
    try {
      debugPrint('🔍 SÜRÜCÜ: Talep kontrolü başlıyor...');
      
      // ÇEVRİMDIŞI KONTROLÜ - ÇEVRİMDIŞIYSA TALEP ARAMA!
      final prefs = await SharedPreferences.getInstance();
      final isOnline = prefs.getBool('driver_is_online') ?? false;
      
      if (!isOnline) {
        debugPrint('🔴 SÜRÜCÜ POLLING: Çevrimdışı - talep arama atlanıyor');
        return;
      }
      
      // AKTİF YOLCULUK VARSA TALEP ARAMA! - COMPLETED STATUS KONTROL ET!
      if (_currentRide != null) {
        // İPTAL FLAG KONTROLÜ - _handleCrossCancel tarafından yazılmış olabilir!
        final prefs = await SharedPreferences.getInstance();
        final cancelledFlag = prefs.getString('ride_cancelled_flag');
        if (cancelledFlag != null) {
          debugPrint('🚩 İPTAL FLAG BULUNDU! Müşteri iptal etmiş - _currentRide temizleniyor...');
          _currentRide = null;
          await _saveCurrentRide(); // NULL'u kaydet
          await prefs.remove('ride_cancelled_flag'); // Flag'i temizle
          debugPrint('✅ _currentRide temizlendi (cancelled flag) - yeni talep arama başlayacak!');
          // Devam et - talep ara!
        }
        // Completed ise temizle ve arama yap!
        else if (_currentRide!.status == 'completed' || _currentRide!.status == 'cancelled') {
          debugPrint('🗑️ SÜRÜCÜ: Tamamlanmış yolculuk tespit edildi - temizleniyor: ${_currentRide!.status}');
          _currentRide = null;
          await _saveCurrentRide(); // NULL'u kaydet - persistence temizler!
          debugPrint('✅ SÜRÜCÜ: _currentRide NULL yapıldı - talep arama başlayacak!');
          // Devam et - talep ara!
        } else {
          // BACKEND'DEN KONTROL ET - İPTAL EDİLMİŞ OLABİLİR!
          try {
            final backendCheck = await http.get(Uri.parse(
              'https://admin.funbreakvale.com/api/check_driver_active_ride.php?driver_id=${_currentRide!.driverId}&ride_id=${_currentRide!.id}'
            )).timeout(const Duration(seconds: 5));
            
            if (backendCheck.statusCode == 200) {
              final backendData = jsonDecode(backendCheck.body);
              
              if (backendData['success'] != true || backendData['has_active_ride'] != true) {
                debugPrint('🚫 BACKEND: Ride ${_currentRide!.id} iptal/tamamlanmış! Temizleniyor...');
                _currentRide = null;
                await _saveCurrentRide();
                await prefs.remove('active_driver_ride_data');
                await prefs.remove('driver_ride_state');
                debugPrint('✅ _currentRide temizlendi - yeni talep arama başlayacak!');
                // Devam et - talep ara!
              } else {
                debugPrint('ℹ️ SÜRÜCÜ: Aktif yolculuk var - talep arama atlanıyor (Ride ID: ${_currentRide!.id})');
                debugPrint('   📊 Yolculuk durumu: ${_currentRide!.status}');
                debugPrint('   ⏸️ Polling devam ediyor ama talep aranmıyor - yolculuk bitince otomatik arama başlar');
                return;
              }
            } else {
              // Backend hatası - varsayılan davranış
              debugPrint('ℹ️ SÜRÜCÜ: Aktif yolculuk var - talep arama atlanıyor (Ride ID: ${_currentRide!.id})');
              return;
            }
          } catch (e) {
            debugPrint('❌ Backend check hatası: $e - polling devam ediyor');
            return;
          }
        }
      }
      
      // ÖNCE ESKİ TALEPLERİ TEMİZLE (1 dakika+)!
      await _cleanupExpiredRequests();
      
      // Mevcut sürücü ID'sini al
      final currentUser = await _adminApi.getCurrentUser();
      if (currentUser == null || currentUser['id'] == null) {
        debugPrint('❌ SÜRÜCÜ: Driver ID bulunamadı');
        return;
      }

      final driverId = currentUser['id'].toString();
      debugPrint('👨‍🚗 SÜRÜCÜ: Driver ID $driverId için talep kontrolü');

      // ADMİN API İLE TALEP ÇEK - TUTARLI ENTEGRASYON!
      final apiResult = await _adminApi.getAvailableRidesForDriver(driverId);
      
      if (apiResult['success'] == true) {
        final ridesData = apiResult['rides'] as List;
        debugPrint('✅ SÜRÜCÜ: ${ridesData.length} talep bulundu');
        
        // Debug: Her talebi detayıyla logla
        for (int i = 0; i < ridesData.length; i++) {
          final ride = ridesData[i];
          debugPrint('🚗 TALEP ${i+1}: ID ${ride['id']}, Müşteri: ${ride['customer_name'] ?? ride['customer_id']}, Pickup: ${ride['pickup_address']}');
          debugPrint('   💰 Fiyat: ₺${ride['estimated_price']}, Durum: ${ride['status']}');
        }
        
        // Ride verilerini model'e çevir
        final parsedRides = ridesData.map((rideData) {
          try {
            return Ride(
              id: rideData['id'].toString(),
              customerId: rideData['customer_id'].toString(),
              customerName: rideData['customer_name']?.toString(), // MÜŞTERİ İSMİ EKLENDİ!
              pickupLocation: LatLng(
                (rideData['pickup_lat'] ?? 0.0).toDouble(),
                (rideData['pickup_lng'] ?? 0.0).toDouble(),
              ),
              destinationLocation: LatLng(
                (rideData['destination_lat'] ?? 0.0).toDouble(),
                (rideData['destination_lng'] ?? 0.0).toDouble(),
              ),
              pickupAddress: rideData['pickup_address'] ?? '',
              destinationAddress: rideData['destination_address'] ?? '',
              estimatedPrice: double.tryParse((rideData['estimated_price'] ?? 0).toString()) ?? 0.0,
              estimatedTime: (rideData['estimated_time'] ?? 15).toInt(),
              paymentMethod: rideData['payment_method'] ?? 'cash',
              status: rideData['status'] ?? 'pending',
              createdAt: DateTime.tryParse(rideData['created_at'] ?? '') ?? DateTime.now(),
              scheduledTime: rideData['scheduled_time'] != null ? DateTime.tryParse(rideData['scheduled_time'].toString()) : null, // SCHEDULED TIME EKLENDİ!
            );
          } catch (e) {
            debugPrint('❌ Ride verisi çevrilemedi: $e');
            return null;
          }
        }).where((ride) => ride != null).cast<Ride>().toList();

        _availableRides = parsedRides;

        debugPrint('✅ SÜRÜCÜ: ${_availableRides.length} talep başarıyla işlendi');

        final Set<String> fetchedIds = {};
        for (final rawRide in ridesData) {
          if (rawRide is! Map) {
            continue;
          }
          final rideMap = Map<String, dynamic>.from(rawRide as Map);
          final rideId = rideMap['id']?.toString() ?? '';
          if (rideId.isEmpty) {
            continue;
          }
          fetchedIds.add(rideId);

          if (!_knownAvailableRideIds.contains(rideId)) {
            _pendingRideQueue.add(rideMap);
            debugPrint('🔔 SÜRÜCÜ: Yeni talep kuyruğa eklendi (ID: $rideId)');
          }
        }

        // Mevcut olmayan talepleri setten sil
        _knownAvailableRideIds.removeWhere((id) => !fetchedIds.contains(id));
        _knownAvailableRideIds.addAll(fetchedIds);

        notifyListeners();
      } else {
        debugPrint('❌ SÜRÜCÜ API hatası: ${apiResult['message']}');
      }
    } catch (e) {
      debugPrint('❌ SÜRÜCÜ: Available rides getirme hatası: $e');
    }
  }

  // Ride kabul et - ADMİN API İLE DÜZELTİLDİ!
  Future<bool> acceptRide(String rideId) async {
    try {
      _isLoading = true;
      notifyListeners();
      debugPrint('✅ SÜRÜCÜ: Talep kabul ediliyor - ID: $rideId');

      // Mevcut sürücü ID'sini al
      final currentUser = await _adminApi.getCurrentUser();
      if (currentUser == null || currentUser['id'] == null) {
        _error = 'Driver ID bulunamadı';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final driverId = currentUser['id'].toString();
      debugPrint('👨‍🚗 SÜRÜCÜ: Driver ID $driverId talebi kabul ediyor');

      // ADMİN API İLE TALEP KABUL ET - TUTARLI ENTEGRASYON!
      final apiResult = await _adminApi.acceptRideRequest(
        rideId: rideId,
        driverId: driverId,
      );

      if (apiResult['success'] == true) {
        debugPrint('✅ SÜRÜCÜ: Talep başarıyla kabul edildi!');
        
        // BACKEND'DEN DÖNEN RIDE STATUS KONTROL ET!
        final rideStatus = apiResult['status']?.toString() ?? apiResult['data']?['status']?.toString() ?? '';
        if (rideStatus == 'cancelled') {
          debugPrint('⚠️ KABUL SONRASI: Ride cancelled durumda - _currentRide SET ETME!');
          debugPrint('ℹ️ Müşteri bu ride\'ı iptal etmiş, yeni talep aranacak!');
          _isLoading = false;
          notifyListeners();
          return false; // Kabul başarısız say!
        }
        
        // Kabul edilen ride'ı available'dan çıkar ve accepted'a ekle
        final acceptedRideIndex = _availableRides.indexWhere((ride) => ride.id == rideId);
        if (acceptedRideIndex != -1) {
          final acceptedRide = _availableRides[acceptedRideIndex];
          _availableRides.removeAt(acceptedRideIndex);
          _acceptedRides.add(acceptedRide);
          _currentRide = acceptedRide;
          
          // AKTİF YOLCULUK PERSİSTENCE KAYDET!
          await _saveCurrentRide();
          
          debugPrint('📋 SÜRÜCÜ: Ride listesi güncellendi - Available: ${_availableRides.length}, Current set: ${_currentRide?.id}');
        }
        
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = apiResult['message'] ?? 'Ride kabul edilemedi';
        debugPrint('❌ SÜRÜCÜ: Kabul hatası: ${_error}');
      }
    } catch (e) {
      _error = 'Ride kabul etme hatası: $e';
      debugPrint('❌ SÜRÜCÜ: Exception: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Ride'ı tamamla
  Future<bool> completeRide(String rideId, double finalPrice) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/complete_ride_tracking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'final_price': finalPrice,
          'total_distance': 0.0, // Varsayılan değer
          'travel_time': 0, // Varsayılan değer
          'route_points': [], // Varsayılan değer
          'completed_at': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // KRİTİK: ÖNCE _currentRide STATUS UPDATE ET!
          if (_currentRide != null && _currentRide!.id == rideId) {
            _currentRide = null; // DIREKT NULL YAP - STATUS GÜNCELLEME GEREKSIZ!
            debugPrint('🗑️ PROVIDER: _currentRide NULL yapıldı (completeRide)');
          }
          
          // Tamamlanan ride'ı accepted'dan çıkar ve completed'a ekle
          final completedRideIndex = _acceptedRides.indexWhere((ride) => ride.id == rideId);
          if (completedRideIndex >= 0) {
            final completedRide = _acceptedRides[completedRideIndex];
            _acceptedRides.removeAt(completedRideIndex);
            _completedRides.insert(0, completedRide);
          }
          
          // AKTİF YOLCULUK PERSİSTENCE TEMİZLE!
          await _clearCurrentRidePersistence();
          
          _isLoading = false;
          notifyListeners();
          debugPrint('✅ PROVIDER: completeRide tamamlandı - polling yeniden başlayacak!');
          return true;
        } else {
          _error = data['message'] ?? 'Ride tamamlanamadı';
        }
      }
    } catch (e) {
      _error = 'Ride tamamlama hatası: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // AKTİF YOLCULUK PERSİSTENCE KAYDET
  Future<void> _saveCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentRide != null) {
        final rideJson = json.encode(_currentRide!.toMap());
        await prefs.setString('current_ride', rideJson);
        debugPrint('💾 Aktif yolculuk persist edildi: ${_currentRide!.id}');
      }
    } catch (e) {
      debugPrint('❌ Aktif yolculuk persist hatası: $e');
    }
  }
  
  // AKTİF YOLCULUK PERSİSTENCE TEMİZLE
  Future<void> _clearCurrentRidePersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_ride');
      debugPrint('🗑️ Aktif yolculuk persistence temizlendi');
      
      // KRİTİK: _currentRide NULL YAP!
      _currentRide = null;
      debugPrint('🗑️ PROVIDER: _currentRide NULL yapıldı!');
      notifyListeners(); // UI güncelle!
    } catch (e) {
      debugPrint('❌ Aktif yolculuk persistence temizleme hatası: $e');
    }
  }

  // Driver konumunu güncelle
  Future<void> updateDriverLocation(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      
      if (driverId == null || !_isOnline) return;

      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_driver_location.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'lat': lat,
          'lng': lng,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Driver konum güncelleme hatası: $e');
    }
  }

  // Komisyon oranını panelden çek
  Future<double> _getCommissionRate() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_settings.php?key=commission_rate'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return double.tryParse(data['value'].toString()) ?? 15.0;
        }
      }
    } catch (e) {
      debugPrint('Komisyon oranı alınamadı: $e');
    }
    return 15.0; // Varsayılan %15
  }

  // Günlük NET kazanç istatistiklerini getir (komisyon düştükten sonra)
  Future<Map<String, dynamic>> getTodayEarnings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      
      debugPrint('🚖 getTodayEarnings - driver_id: $driverId');
      
      if (driverId == null) {
        debugPrint('❌ Driver ID null! Kazanç 0 döndürülüyor');
        return {'earnings': 0.0, 'rides': 0};
      }

      // Backend'den server tarihini al (emulator tarihi yanlış olabilir!)
      final serverTimeResponse = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_server_time.php'),
      ).timeout(const Duration(seconds: 5));
      
      String today;
      if (serverTimeResponse.statusCode == 200) {
        final serverData = jsonDecode(serverTimeResponse.body);
        today = serverData['server_time']['iso'].toString().split('T')[0];
        debugPrint('📅 Server tarihi kullanılıyor: $today');
      } else {
        today = DateTime.now().toIso8601String().split('T')[0];
        debugPrint('⚠️ Server tarihine ulaşılamadı, lokal tarih: $today');
      }
      
      final url = 'https://admin.funbreakvale.com/api/get_driver_rides.php?driver_id=$driverId&date=$today';
      debugPrint('📡 API çağrısı: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          // Backend'den gelen kazançlar
          double totalRevenue = 0.0;  // İNDİRİMLİ BRÜT (total_revenue - backend hesaplıyor)
          double grossEarnings = 0.0; // İNDİRİMSİZ BRÜT
          double netEarnings = 0.0;   // NET (komisyon sonrası)
          int rides = 0;
          
          // total_revenue (İNDİRİMLİ BRÜT - ana sayfada gösterilecek)
          if (data['total_revenue'] != null) {
            totalRevenue = double.tryParse(data['total_revenue'].toString()) ?? 0.0;
          } else if (data['gross_earnings'] != null) {
            totalRevenue = double.tryParse(data['gross_earnings'].toString()) ?? 0.0;
          }
          
          // gross_earnings (indirimsiz)
          if (data['gross_earnings'] != null) {
            grossEarnings = double.tryParse(data['gross_earnings'].toString()) ?? 0.0;
          }
          
          // earnings (NET)
          if (data['earnings'] != null) {
            netEarnings = double.tryParse(data['earnings'].toString()) ?? 0.0;
          }
          
          // rides
          if (data['rides'] != null) {
            rides = int.tryParse(data['rides'].toString()) ?? 0;
          }
          
          // ✅ Backend'den direk earnings ve rides kullan
          final backendEarnings = double.tryParse(data['earnings']?.toString() ?? '0') ?? 0.0;
          final backendRides = int.tryParse(data['rides']?.toString() ?? '0') ?? 0;
          
          debugPrint('✅ Kazanç alındı - Backend Earnings: ₺$backendEarnings, Rides: $backendRides');
          debugPrint('📊 Full data: $data');
          
          return {
            'earnings': backendEarnings, // Backend'den gelen NET kazanç
            'rides': backendRides,
          };
        } else {
          debugPrint('❌ API success=false: ${data['message'] ?? 'Bilinmeyen hata'}');
        }
      } else {
        debugPrint('❌ HTTP Hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ getTodayEarnings HATA: $e');
    }
    
    debugPrint('⚠️ Varsayılan değer döndürülüyor: earnings=0, rides=0');
    return {'earnings': 0.0, 'rides': 0};
  }

  // Toplam kazanç getir (NET - komisyon düştükten sonra)
  Future<Map<String, dynamic>> getTotalEarnings() async {
    final commissionRate = await _getCommissionRate();
    final totalNetEarnings = _completedRides.fold(0.0, (sum, ride) {
      final grossPrice = ride.estimatedPrice;
      final netPrice = grossPrice * (100 - commissionRate) / 100;
      return sum + netPrice;
    });
    
    final totalGrossEarnings = _completedRides.fold(0.0, (sum, ride) => sum + ride.estimatedPrice);
    
    return {
      'earnings': totalNetEarnings, // NET kazanç
      'gross_earnings': totalGrossEarnings,
      'commission': totalGrossEarnings - totalNetEarnings,
      'rides': _completedRides.length,
      'commission_rate': commissionRate,
    };
  }

  @override
  void dispose() {
    _ridePollingTimer?.cancel();
    super.dispose();
  }
}


