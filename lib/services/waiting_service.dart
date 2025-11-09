import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class WaitingService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static Timer? _waitingTimer;
  static DateTime? _waitingStartTime;
  static StreamController<int> _waitingController = StreamController<int>.broadcast();
  static Map<String, dynamic>? _cachedSettings;
  
  // Bekleme süresi stream'i
  static Stream<int> get waitingStream => _waitingController.stream;
  
  // Sistem ayarlarını çek
  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      if (_cachedSettings != null) {
        return _cachedSettings;
      }
      
      print('Waiting settings çekiliyor...');
      final response = await http.get(
        Uri.parse('$baseUrl/get_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _cachedSettings = data['data'];
          print('Waiting settings alındı');
          return _cachedSettings;
        }
      }
      
      print('Waiting settings alınamadı');
      return null;
    } catch (e) {
      print('Waiting settings hatası: $e');
      return null;
    }
  }
  
  // Bekleme başlat
  static Future<void> startWaiting() async {
    if (_waitingTimer != null) {
      print('Bekleme zaten başlatılmış');
      return;
    }
    
    _waitingStartTime = DateTime.now();
    print('Bekleme başlatıldı: $_waitingStartTime');
    
    _waitingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_waitingStartTime != null) {
        int elapsedSeconds = DateTime.now().difference(_waitingStartTime!).inSeconds;
        _waitingController.add(elapsedSeconds);
      }
    });
  }
  
  // Bekleme durdur
  static Future<double> stopWaiting() async {
    if (_waitingTimer == null || _waitingStartTime == null) {
      print('Bekleme başlatılmamış');
      return 0.0;
    }
    
    _waitingTimer!.cancel();
    _waitingTimer = null;
    
    int totalMinutes = DateTime.now().difference(_waitingStartTime!).inMinutes;
    _waitingStartTime = null;
    
    print('Bekleme durduruldu. Toplam süre: $totalMinutes dakika');
    
    // Bekleme ücretini hesapla
    double waitingFee = await calculateWaitingFee(totalMinutes);
    
    _waitingController.add(0); // Reset
    return waitingFee;
  }
  
  // Bekleme ücreti hesapla
  static Future<double> calculateWaitingFee(int totalMinutes) async {
    try {
      final settings = await getSettings();
      
      if (settings == null) {
        print('Settings alınamadı, varsayılan hesaplama');
        return _calculateDefaultWaitingFee(totalMinutes);
      }
      
      // Panel'den ayarları al
      double freeMinutes = double.tryParse(settings['waiting_free_minutes'] ?? 
                                         settings['waiting_fee_free_minutes'] ?? '30') ?? 30;
      double feePerInterval = double.tryParse(settings['waiting_fee_per_15min'] ?? '150') ?? 150;
      
      print('Ücretsiz bekleme: $freeMinutes dk, 15dk ücreti: $feePerInterval TL');
      
      if (totalMinutes <= freeMinutes) {
        print('Ücretsiz bekleme süresi içinde: $totalMinutes dk');
        return 0.0;
      }
      
      double chargeableMinutes = totalMinutes - freeMinutes;
      double intervals = (chargeableMinutes / 15).ceil(); // 15 dakikalık aralıklar
      double totalFee = intervals * feePerInterval;
      
      print('Ücretli bekleme: $chargeableMinutes dk = $totalFee TL');
      return totalFee;
      
    } catch (e) {
      print('Bekleme ücreti hesaplama hatası: $e');
      return _calculateDefaultWaitingFee(totalMinutes);
    }
  }
  
  // Varsayılan bekleme ücreti hesaplama
  static double _calculateDefaultWaitingFee(int totalMinutes) {
    const double defaultFreeMinutes = 30;
    const double defaultFeePerInterval = 150;
    
    if (totalMinutes <= defaultFreeMinutes) {
      return 0.0;
    }
    
    double chargeableMinutes = totalMinutes - defaultFreeMinutes;
    double intervals = (chargeableMinutes / 15).ceil();
    return intervals * defaultFeePerInterval;
  }
  
  // Mevcut bekleme süresini al (dakika)
  static int getCurrentWaitingMinutes() {
    if (_waitingStartTime == null) return 0;
    return DateTime.now().difference(_waitingStartTime!).inMinutes;
  }
  
  // Mevcut bekleme süresini al (saniye)
  static int getCurrentWaitingSeconds() {
    if (_waitingStartTime == null) return 0;
    return DateTime.now().difference(_waitingStartTime!).inSeconds;
  }
  
  // Bekleme durumu kontrolü
  static bool get isWaiting => _waitingTimer != null && _waitingStartTime != null;
  
  // Tahmini bekleme ücreti (anlık)
  static Future<double> getEstimatedWaitingFee() async {
    if (!isWaiting) return 0.0;
    
    int currentMinutes = getCurrentWaitingMinutes();
    return await calculateWaitingFee(currentMinutes);
  }
  
  // Cache temizle
  static void clearCache() {
    _cachedSettings = null;
    print('Waiting settings cache temizlendi');
  }
  
  // Servisi temizle
  static void dispose() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
    _waitingStartTime = null;
    _waitingController.add(0);
    clearCache();
    print('Waiting service temizlendi');
  }
}
