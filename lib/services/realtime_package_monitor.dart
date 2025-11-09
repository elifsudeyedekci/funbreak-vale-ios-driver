import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class RealtimePackageMonitor {
  static Timer? _monitorTimer;
  static int? _currentRideId;
  static DateTime? _rideStartTime;
  static Function(Map<String, dynamic>)? _onPackageUpdate;
  
  // Gerçek zamanlı paket monitörünü başlat (Sürücü versiyonu)
  static void startMonitoring({
    required int rideId,
    required Function(Map<String, dynamic>) onPackageUpdate,
  }) {
    print('🔄 [ŞOFÖR] Gerçek zamanlı paket monitör başlatıldı - Ride ID: $rideId');
    
    _currentRideId = rideId;
    _rideStartTime = DateTime.now();
    _onPackageUpdate = onPackageUpdate;
    
    // Şoför için her 1 dakikada bir kontrol et (daha sık)
    _monitorTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkPackageStatus();
    });
    
    // İlk kontrolü hemen yap
    _checkPackageStatus();
  }
  
  // Monitörü durdur
  static void stopMonitoring() {
    print('⏹️ [ŞOFÖR] Gerçek zamanlı paket monitör durduruldu');
    
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _currentRideId = null;
    _rideStartTime = null;
    _onPackageUpdate = null;
  }
  
  // Paket durumunu kontrol et
  static Future<void> _checkPackageStatus() async {
    if (_currentRideId == null || _rideStartTime == null) return;
    
    try {
      final currentSeconds = DateTime.now().difference(_rideStartTime!).inSeconds;
      
      print('⏱️ [ŞOFÖR] Paket kontrol - Ride: $_currentRideId, Seconds: $currentSeconds');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/realtime_package_monitor.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': _currentRideId,
          'current_seconds': currentSeconds,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final packageData = data['data'];
          
          print('📊 [ŞOFÖR] Paket durumu: ${packageData['current_hours']}h, Fiyat: ₺${packageData['current_price']}');
          
          // Paket yükseltme olmuş mu kontrol et
          if (packageData['package_upgraded'] == true && packageData['price_changed'] == true) {
            print('🔝 [ŞOFÖR] PAKET YÜKSELTİLDİ! Yeni fiyat: ₺${packageData['current_price']}');
            
            // Callback ile UI'ya bildir
            _onPackageUpdate?.call({
              'type': 'package_upgraded',
              'data': packageData,
              'message': 'Müşteri paketi otomatik yükseltildi!',
              'for_driver': true,
            });
          } else {
            // Normal güncelleme
            _onPackageUpdate?.call({
              'type': 'status_update',
              'data': packageData,
              'for_driver': true,
            });
          }
          
        } else {
          print('❌ [ŞOFÖR] Paket kontrol hatası: ${data['message']}');
        }
      }
      
    } catch (e) {
      print('❌ [ŞOFÖR] Paket monitör hatası: $e');
    }
  }
  
  // Şoför için kazanç hesaplama (komisyon düşülmüş)
  static double calculateDriverEarning(double totalPrice, {double commissionRate = 0.25}) {
    return totalPrice * (1 - commissionRate); // %25 komisyon düşülmüş
  }
  
  // Şoför için paket bilgisi formatla
  static String formatPackageInfoForDriver(Map<String, dynamic> packageData) {
    final currentHours = (packageData['current_hours'] ?? 0).toStringAsFixed(1);
    final currentPrice = packageData['current_price'] ?? 0;
    final driverEarning = calculateDriverEarning(currentPrice.toDouble());
    
    return 'Süre: ${currentHours}h | Toplam: ₺${currentPrice.toStringAsFixed(0)} | Kazancınız: ₺${driverEarning.toStringAsFixed(0)}';
  }
  
  // Manuel paket kontrolü (şoför versiyonu)
  static Future<Map<String, dynamic>?> checkPackageNow({
    required int rideId,
    required DateTime rideStartTime,
  }) async {
    try {
      final currentSeconds = DateTime.now().difference(rideStartTime).inSeconds;
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/realtime_package_monitor.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'current_seconds': currentSeconds,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          return data['data'];
        }
      }
      
      return null;
      
    } catch (e) {
      print('❌ [ŞOFÖR] Manuel paket kontrol hatası: $e');
      return null;
    }
  }
  
  // Aktif monitör var mı kontrol et
  static bool get isMonitoring => _monitorTimer != null && _monitorTimer!.isActive;
  
  // Mevcut ride ID'yi al
  static int? get currentRideId => _currentRideId;
  
  // Yolculuk süresini al (saat cinsinden)
  static double? get currentHours {
    if (_rideStartTime == null) return null;
    return DateTime.now().difference(_rideStartTime!).inSeconds / 3600;
  }
}
