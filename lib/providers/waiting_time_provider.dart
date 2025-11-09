import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WaitingTimeProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  Timer? _waitingTimer;
  DateTime? _waitingStartTime;
  int _totalWaitingMinutes = 0;
  double _waitingFee = 0.0;
  bool _isWaiting = false;
  String? _currentRideId;
  
  // Admin panelden çekilen ayarlar
  int _freeWaitingMinutes = 15; // İlk 15 dakika ücretsiz
  double _waitingFeePerInterval = 100.0; // Her 15 dakika için 100 TL
  int _waitingInterval = 15; // 15 dakikalık aralıklar
  
  // Gecelik paket ayarları
  Map<String, dynamic> _nightlyPackages = {
    '0-4': {'hours': 4, 'price': 3000.0},
    '4-8': {'hours': 8, 'price': 4500.0},
    '8-12': {'hours': 12, 'price': 6000.0},
  };
  
  // Getters
  int get totalWaitingMinutes => _totalWaitingMinutes;
  double get waitingFee => _waitingFee;
  bool get isWaiting => _isWaiting;
  int get freeWaitingMinutes => _freeWaitingMinutes;
  double get waitingFeePerInterval => _waitingFeePerInterval;

  // Admin panelden bekleme ayarlarını yükle
  Future<void> loadWaitingSettings() async {
    try {
      // Genel ayarları getir
      final settingsResponse = await http.get(
        Uri.parse('$baseUrl/waiting_settings.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (settingsResponse.statusCode == 200) {
        final settingsData = jsonDecode(settingsResponse.body);
        if (settingsData['success'] == true) {
          _freeWaitingMinutes = int.parse(settingsData['free_minutes'].toString());
          _waitingFeePerInterval = double.parse(settingsData['fee_per_interval'].toString());
          _waitingInterval = int.parse(settingsData['interval_minutes'].toString());
        }
      }
      
      // Saatlik paketleri (gecelik paketler) mevcut pricing tablosundan getir
      final pricingResponse = await http.get(
        Uri.parse('$baseUrl/pricing.php'),
        headers: {'Content-Type': 'application/json'},
      );

      if (pricingResponse.statusCode == 200) {
        final pricingData = jsonDecode(pricingResponse.body);
        if (pricingData['success'] == true) {
          final pricing = List<Map<String, dynamic>>.from(pricingData['pricing']);
          
          // Saatlik paketleri filtrele ve _nightlyPackages'a dönüştür
          _nightlyPackages.clear();
          for (var item in pricing) {
            if (item['type'] == 'hourly') {
              String packageName = '${item['min_value']}-${item['max_value']}';
              _nightlyPackages[packageName] = {
                'hours': item['max_value'],
                'price': double.parse(item['price'].toString()),
              };
            }
          }
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Bekleme ayarları yükleme hatası: $e');
    }
  }

  // Bekleme süresini başlat
  Future<void> startWaiting(String rideId) async {
    if (_isWaiting) return;

    _currentRideId = rideId;
    _isWaiting = true;
    _waitingStartTime = DateTime.now();
    _totalWaitingMinutes = 0;
    _waitingFee = 0.0;
    
    // Admin panele bekleme başladı bilgisi
    await _updateWaitingStatus(rideId, 'started');
    
    // Her dakika güncelle
    _waitingTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateWaitingTime();
    });
    
    notifyListeners();
  }

  // Bekleme süresini durdur
  Future<void> stopWaiting() async {
    if (!_isWaiting || _currentRideId == null) return;

    _isWaiting = false;
    _waitingTimer?.cancel();
    
    // Admin panele bekleme durdu bilgisi
    await _updateWaitingStatus(_currentRideId!, 'stopped');
    
    _currentRideId = null;
    notifyListeners();
  }

  // Bekleme süresini güncelle
  void _updateWaitingTime() {
    if (_waitingStartTime == null) return;

    _totalWaitingMinutes = DateTime.now().difference(_waitingStartTime!).inMinutes;
    
    // Bekleme ücreti hesapla
    if (_totalWaitingMinutes > _freeWaitingMinutes) {
      int chargeableMinutes = _totalWaitingMinutes - _freeWaitingMinutes;
      int intervals = (chargeableMinutes / _waitingInterval).ceil();
      _waitingFee = intervals * _waitingFeePerInterval;
    } else {
      _waitingFee = 0.0;
    }
    
    // 2 saat (120 dakika) üzerinde ise gecelik pakete geç
    if (_totalWaitingMinutes >= 120) {
      _checkNightlyPackage();
    }
    
    // Admin panele anlık güncelleme gönder
    if (_currentRideId != null) {
      _sendWaitingUpdate(_currentRideId!, _totalWaitingMinutes, _waitingFee);
    }
    
    notifyListeners();
  }

  // Gecelik paket kontrolü
  void _checkNightlyPackage() {
    int hours = (_totalWaitingMinutes / 60).floor();
    
    for (var package in _nightlyPackages.entries) {
      int maxHours = package.value['hours'];
      double packagePrice = package.value['price'];
      
      if (hours <= maxHours) {
        // Gecelik paket fiyatı bekleme ücretinden daha uygunsa değiştir
        if (packagePrice < _waitingFee) {
          _waitingFee = packagePrice;
        }
        break;
      }
    }
  }

  // Admin panele bekleme durumu güncelleme
  Future<void> _updateWaitingStatus(String rideId, String status) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/update_waiting_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Bekleme durum güncelleme hatası: $e');
    }
  }

  // Admin panele anlık bekleme verisi gönder
  Future<void> _sendWaitingUpdate(String rideId, int minutes, double fee) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/update_waiting_time.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'waiting_minutes': minutes,
          'waiting_fee': fee,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Bekleme güncelleme hatası: $e');
    }
  }

  // Manuel bekleme ücreti hesapla (şoför tarafından)
  double calculateManualWaitingFee(int minutes) {
    if (minutes <= _freeWaitingMinutes) return 0.0;
    
    int chargeableMinutes = minutes - _freeWaitingMinutes;
    int intervals = (chargeableMinutes / _waitingInterval).ceil();
    double fee = intervals * _waitingFeePerInterval;
    
    // Gecelik paket kontrolü
    int hours = (minutes / 60).floor();
    for (var package in _nightlyPackages.entries) {
      int maxHours = package.value['hours'];
      double packagePrice = package.value['price'];
      
      if (hours <= maxHours && packagePrice < fee) {
        return packagePrice;
      }
    }
    
    return fee;
  }

  // Gecelik paket bilgilerini getir
  Map<String, dynamic> getNightlyPackageInfo(int minutes) {
    int hours = (minutes / 60).floor();
    
    for (var package in _nightlyPackages.entries) {
      int maxHours = package.value['hours'];
      double packagePrice = package.value['price'];
      
      if (hours <= maxHours) {
        return {
          'package_name': '${package.key} Saat Gecelik Paket',
          'price': packagePrice,
          'hours': maxHours,
          'is_nightly': true,
        };
      }
    }
    
    return {'is_nightly': false};
  }

  @override
  void dispose() {
    _waitingTimer?.cancel();
    super.dispose();
  }
}
