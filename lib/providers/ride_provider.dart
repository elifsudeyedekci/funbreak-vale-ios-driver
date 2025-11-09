import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/ride.dart';
import 'admin_api_provider.dart';
import 'dart:async';

class RideProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminApiProvider _adminApi = AdminApiProvider();
  Timer? _ridePollingTimer;
  
  Ride? _currentRide;
  List<Ride> _rideHistory = [];
  List<Ride> _availableRides = [];
  bool _isLoading = false;
  String? _error;

  Ride? get currentRide => _currentRide;
  List<Ride> get rideHistory => _rideHistory;
  List<Ride> get availableRides => _availableRides;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ADMİN API İLE TALEP YÜKLEMESİ - KRİTİK DÜZELTİLMİŞ!
  Future<void> loadAvailableRides() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Mevcut sürücü ID'sini al
      final currentUser = await _adminApi.getCurrentUser();
      if (currentUser == null || currentUser['id'] == null) {
        _error = 'Sürücü bilgisi bulunamadı';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final driverId = currentUser['id'].toString();
      
      print('🚗 Sürücü $driverId için talepler yükleniyor...');

      // ADMİN API İLE MEVCUT TALEPLERİ ÇEK
      final apiResult = await _adminApi.getAvailableRidesForDriver(driverId);
      
      if (apiResult['success'] == true) {
        final ridesData = apiResult['rides'] as List;
        
        // API verilerini Ride modellerine çevir
        _availableRides = ridesData.map((rideData) {
          try {
            return Ride(
              id: rideData['id']?.toString() ?? '',
              customerId: rideData['customer_id']?.toString() ?? '',
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
              status: rideData['status'] ?? 'pending',
              estimatedPrice: double.tryParse((rideData['estimated_price'] ?? 0).toString()) ?? 0.0,
              estimatedTime: rideData['estimated_time'] ?? 15,
              paymentMethod: rideData['payment_method'] ?? 'cash',
              createdAt: DateTime.tryParse(rideData['created_at'] ?? '') ?? DateTime.now(),
            );
          } catch (e) {
            print('❌ Ride verisi çevrilemedi: $e');
            return null;
          }
        }).where((ride) => ride != null).cast<Ride>().toList();

        print('✅ ${_availableRides.length} talep yüklendi');
      } else {
        _error = apiResult['message'];
        print('❌ API hatası: ${apiResult['message']}');
        _availableRides = [];
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Talep yükleme hatası: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // Eksik method - getAvailableRides
  Future<List<Ride>> getAvailableRides() async {
    try {
      final snapshot = await _firestore
          .collection('rides')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Ride.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Mevcut yolculuklar yüklenemedi: $e');
      return [];
    }
  }

  Future<void> loadRideHistory() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final snapshot = await _firestore
          .collection('rides')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      _rideHistory = snapshot.docs
          .map((doc) => Ride.fromMap(doc.data(), doc.id))
          .toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // ADMİN API İLE TALEP KABUL ETME - KRİTİK DÜZELTİLMİŞ!
  Future<void> acceptRide(String rideId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Mevcut sürücü ID'sini al
      final currentUser = await _adminApi.getCurrentUser();
      if (currentUser == null || currentUser['id'] == null) {
        _error = 'Sürücü bilgisi bulunamadı';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final driverId = currentUser['id'].toString();
      
      print('✅ Talep kabul ediliyor - ride: $rideId, driver: $driverId');

      // ADMİN API İLE TALEBİ KABUL ET
      final apiResult = await _adminApi.acceptRideRequest(
        rideId: rideId,
        driverId: driverId,
      );
      
      if (apiResult['success'] == true) {
        print('✅ Talep başarıyla kabul edildi!');
        
        // Kabul edilen talebi current ride olarak ayarla
        final rideData = apiResult['ride'];
        if (rideData != null) {
          try {
            _currentRide = Ride(
              id: rideData['id']?.toString() ?? rideId,
              customerId: rideData['customer_id']?.toString() ?? '',
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
              status: 'accepted',
              estimatedPrice: double.tryParse((rideData['estimated_price'] ?? 0).toString()) ?? 0.0,
              estimatedTime: rideData['estimated_time'] ?? 15,
              paymentMethod: rideData['payment_method'] ?? 'cash',
              createdAt: DateTime.tryParse(rideData['created_at'] ?? '') ?? DateTime.now(),
              driverId: driverId,
            );
          } catch (e) {
            print('❌ Kabul edilen ride verisi çevrilemedi: $e');
          }
        }
        
        // Mevcut talepleri yenile
        await loadAvailableRides();
      } else {
        _error = apiResult['message'];
        print('❌ Talep kabul edilemedi: ${apiResult['message']}');
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Talep kabul hatası: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startRide(String rideId) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'status': 'started',
        'startedAt': FieldValue.serverTimestamp(),
      });

      await _loadCurrentRide(rideId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> startWaiting(String rideId) async {
    try {
      await _firestore.collection('rides').doc(rideId).update({
        'status': 'waiting',
        'waitingStartTime': FieldValue.serverTimestamp(),
      });
      await _loadCurrentRide(rideId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> stopWaiting(String rideId) async {
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (rideDoc.exists) {
        final data = rideDoc.data()!;
        final waitingStartTime = data['waitingStartTime'] as Timestamp?;
        
        if (waitingStartTime != null) {
          final now = DateTime.now();
          final waitingDuration = now.difference(waitingStartTime.toDate());
          final waitingMinutes = waitingDuration.inMinutes;
          
          // Calculate waiting fee (first 15 minutes free, then 100 TL per 15 minutes)
          double waitingFee = 0.0;
          if (waitingMinutes > 15) {
            final chargeableMinutes = waitingMinutes - 15;
            final chargeablePeriods = (chargeableMinutes / 15.0).ceil();
            waitingFee = chargeablePeriods * 100.0;
          }

          await _firestore.collection('rides').doc(rideId).update({
            'status': 'started',
            'waitingMinutes': waitingMinutes,
            'waitingFee': waitingFee,
          });
        }
      }
      await _loadCurrentRide(rideId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> completeRide(String rideId, double actualPrice) async {
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (rideDoc.exists) {
        final data = rideDoc.data()!;
        final estimatedTime = data['estimatedTime'] ?? 0;
        final actualTime = data['actualTime'] ?? estimatedTime;
        
        // Check if should switch to night package (2 hours or more)
        bool isNightPackage = false;
        if (actualTime >= 120) { // 2 hours = 120 minutes
          isNightPackage = true;
          actualPrice *= 1.5; // Night package multiplier
        }

        await _firestore.collection('rides').doc(rideId).update({
          'status': 'completed',
          'actualPrice': actualPrice,
          'completedAt': FieldValue.serverTimestamp(),
          'isNightPackage': isNightPackage,
        });
      }
      _currentRide = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _loadCurrentRide(String rideId) async {
    try {
      final doc = await _firestore.collection('rides').doc(rideId).get();
      if (doc.exists) {
        _currentRide = Ride.fromMap(doc.data()!, doc.id);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // OTOMATİK TALEP YENİLEME SİSTEMİ BAŞLAT - KRİTİK!
  void startRidePolling() {
    // Mevcut timer'ı durdur
    _ridePollingTimer?.cancel();
    
    // Her 5 saniyede bir talepleri yenile (çevrimiçi sürücüler için)
    _ridePollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        print('🔄 Otomatik talep yenileme...');
        await loadAvailableRides();
      } catch (e) {
        print('❌ Otomatik talep yenileme hatası: $e');
      }
    });
    
    print('🚀 Otomatik talep yenileme sistemi başlatıldı (5 saniyede bir)');
  }

  // OTOMATİK TALEP YENİLEME SİSTEMİ DURDUR
  void stopRidePolling() {
    _ridePollingTimer?.cancel();
    _ridePollingTimer = null;
    print('⏹️ Otomatik talep yenileme sistemi durduruldu');
  }

  // SÜRÜCÜ DURUMUNU GÜNCELLE - ÇEVRİMİÇİ/ÇEVRİMDIŞI
  Future<void> updateDriverStatus({
    required bool isOnline,
    required bool isAvailable,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Mevcut sürücü ID'sini al
      final currentUser = await _adminApi.getCurrentUser();
      if (currentUser == null || currentUser['id'] == null) {
        print('❌ Sürücü bilgisi bulunamadı');
        return;
      }

      final driverId = currentUser['id'].toString();
      
      print('📍 Sürücü durum güncelleme: $driverId - ${isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');

      // ADMİN API İLE SÜRÜCÜ DURUMUNU GÜNCELLE
      final apiResult = await _adminApi.updateDriverStatus(
        driverId: driverId,
        isOnline: isOnline,
        isAvailable: isAvailable,
        latitude: latitude,
        longitude: longitude,
      );
      
      if (apiResult['success'] == true) {
        print('✅ Sürücü durumu başarıyla güncellendi!');
        
        // Çevrimiçi olunca talep polling'i başlat
        if (isOnline && isAvailable) {
          startRidePolling();
          // İlk yükleme
          await loadAvailableRides();
        } else {
          // Çevrimdışı olunca polling'i durdur
          stopRidePolling();
          // Mevcut talepleri temizle
          _availableRides.clear();
          notifyListeners();
        }
      } else {
        print('❌ Sürücü durumu güncellenemedi: ${apiResult['message']}');
      }
    } catch (e) {
      print('❌ Sürücü durum güncelleme hatası: $e');
    }
  }

  // SÜRÜCÜ ÇEVRİMİÇİ YAP
  Future<void> goOnline({double? latitude, double? longitude}) async {
    await updateDriverStatus(
      isOnline: true,
      isAvailable: true,
      latitude: latitude,
      longitude: longitude,
    );
  }

  // SÜRÜCÜ ÇEVRİMDIŞI YAP
  Future<void> goOffline() async {
    await updateDriverStatus(
      isOnline: false,
      isAvailable: false,
    );
  }

  // PROVIDER TEMİZLE
  @override
  void dispose() {
    stopRidePolling();
    super.dispose();
  }
} 