import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../services/ride_persistence_service.dart';
import '../messaging/ride_messaging_screen.dart';
import '../../services/company_contact_service.dart'; // ŞİRKET ARAMA SERVİSİ!
import '../chat/ride_chat_screen.dart'; // GERÇEK MESAJLAŞMA!
import '../../services/ride_service.dart';
import '../../providers/driver_ride_provider.dart'; // AKTİF YOLCULUK TEMİZLEME İÇİN!
import '../../services/location_tracking_service.dart'; // 📍 KONUM TRACKING İÇİN!
import 'dart:math' as math;
import '../../widgets/rating_dialog.dart';

class ModernDriverActiveRideScreen extends StatefulWidget {
  final Map<String, dynamic> rideDetails;
  final int waitingMinutes;
  
  const ModernDriverActiveRideScreen({
    Key? key, 
    required this.rideDetails,
    this.waitingMinutes = 0,
  }) : super(key: key);
  
  @override
  State<ModernDriverActiveRideScreen> createState() => _ModernDriverActiveRideScreenState();
}

class _ModernDriverActiveRideScreenState extends State<ModernDriverActiveRideScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _trackingTimer;
  // Timer? _waitingTimer;  // MANUEL TIMER KALDIRILDI - Backend TIMESTAMPDIFF kullanıyor!
  Map<String, dynamic> _currentRideStatus = {};
  bool _isLoading = true;
  
  // Tracking variables
  LatLng? _customerLocation;
  LatLng? _driverLocation;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  
  // Waiting system - MANUEL KONTROL
  int _waitingMinutes = 0;
  bool _waitingStarted = false;
  bool _isWaitingActive = false;
  
  // Yolculuk durum kontrol
  bool _isRideStarted = false; // YOLCULUK BAŞLADI MI?
  DateTime? _rideStartTime;    // BAŞLAMA ZAMANI
  
  // ✅ SAATLİK PAKET CACHE
  List<Map<String, double>> _cachedHourlyPackages = [];
  
  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;
  late Animation<Offset> _slideAnimation;
  
  // Earnings tracking
  double _estimatedEarnings = 0.0;
  double _waitingFee = 0.0;
  double _waitingFeeGross = 0.0; // KOMİSYONSUZ BEKLEME ÜCRETİ!
  double _calculatedTotalPrice = 0.0;
  
  // Panel bekleme ayarları
  double _waitingFeePerInterval = 200.0; // Varsayılan: Her 15 dakika ₺200
  int _waitingFreeMinutes = 15; // İlk 15 dakika ücretsiz
  int _waitingIntervalMinutes = 15; // 15 dakikalık aralıklar
  
  // SAATLİK PAKETTE BEKLEME BUTONU GİZLENMELİ!
  bool get _shouldShowWaitingButton {
    // DESTINATION ADRES KONTROLÜ - SAATLİK PAKET İSE "(Saatlik Paket)" YAZAR!
    final destination = widget.rideDetails['destination_address']?.toString().toLowerCase() ?? '';
    final pickupAddr = widget.rideDetails['pickup_address']?.toString().toLowerCase() ?? '';
    
    print('🔍 BEKLEME BUTON KONTROL:');
    print('   destination_address: ${widget.rideDetails['destination_address']}');
    print('   pickup_address: ${widget.rideDetails['pickup_address']}');
    
    // 1. DESTINATION'DA "(Saatlik Paket)" VARSA → SAATLİK PAKET!
    if (destination.contains('saatlik paket') || destination.contains('(saatlik paket)')) {
      print('   ✅ SAATLİK PAKET TESPİT EDİLDİ - BEKLEME BUTONU GİZLENECEK!');
      return false;
    }
    
    // 2. PICKUP ve DESTINATION AYNI İSE (saatlik paket için aynı konum) → SAATLİK PAKET!
    final destClean = destination.replaceAll('(saatlik paket)', '').trim();
    final pickupClean = pickupAddr.trim();
    if (destClean.isNotEmpty && destClean == pickupClean) {
      print('   ✅ PICKUP = DESTINATION - SAATLİK PAKET OLMA İHTİMALİ - BEKLEME BUTONU GİZLENECEK!');
      return false;
    }
    
    // 3. BACKEND'DEN GELEN service_type/ride_type KONTROL
    final serviceType = widget.rideDetails['service_type']?.toString().toLowerCase() ?? 
                        _currentRideStatus['service_type']?.toString().toLowerCase() ?? '';
    final rideType = widget.rideDetails['ride_type']?.toString().toLowerCase() ?? 
                     _currentRideStatus['ride_type']?.toString().toLowerCase() ?? '';
    
    if (serviceType == 'hourly' || rideType == 'hourly') {
      print('   ✅ service_type/ride_type = hourly - BEKLEME BUTONU GİZLENECEK!');
      return false;
    }
    
    // 4. NORMAL VALE AMA 2 SAAT GEÇTİYSE (otomatik hourly'ye dönmüş) → BEKLEME YOK
    if (_isRideStarted && _rideStartTime != null) {
      final duration = DateTime.now().difference(_rideStartTime!);
      if (duration.inMinutes >= 120) { // 2 saat = 120 dakika
        print('   ✅ 2 SAAT GEÇTİ (${duration.inMinutes} dk) - BEKLEME BUTONU GİZLENECEK!');
        return false;
      }
    }
    
    // 5. DİĞER DURUMLARDA BEKLEME GÖSTERİLEBİLİR
    print('   ⚪ NORMAL VALE - BEKLEME BUTONU GÖSTER!');
    return true;
  }
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ARKA PLAN OBSERVER!
    _initializeAnimations();
    
    // 📍 KRİTİK: KONUM TRAcKING BAŞLAT!
    LocationTrackingService.startLocationTracking();
    print('📍 Aktif yolculuk - Location tracking başlatıldı');
    
    // DEBUG: Widget verilerini kontrol et
    print('🔍 ŞOFÖR: Widget rideDetails debug:');
    widget.rideDetails.forEach((key, value) {
      print('   $key: $value');
    });
    
    // KRİTİK: ÖNCE RESTORE, SONRA DİĞER İŞLEMLER!
    final initialTotal = double.tryParse(
          widget.rideDetails['calculated_price']?.toString() ??
          widget.rideDetails['estimated_price']?.toString() ??
          '0',
        ) ??
        0.0;
    // ✅ Eğer 0 ise base_price kullan (minimum başlangıç fiyatı)
    _calculatedTotalPrice = initialTotal > 0 ? initialTotal : 50.0;
    print('💰 [ŞOFÖR] İlk fiyat: ₺${_calculatedTotalPrice} (initialTotal: ₺$initialTotal)');
    _initializeWithRestore();
  }
  
  // YENİ: RESTORE ÖNCE, SONRA HESAPLAMA
  Future<void> _initializeWithRestore() async {
    // 1. PANEL'DEN BEKLEME AYARLARINI ÇEK!
    await _fetchPanelWaitingSettings();
    
    // 2. SAATLİK PAKETLERI YÜ KLE!
    await _loadHourlyPackages();
    
    // 3. RESTORE ET
    await _restoreRideStartedFromPersistence();
    
    // 4. DİĞER İŞLEMLER
    _initializeRideTracking();
  }
  
  // PANEL'DEN BEKLEME AYARLARINI ÇEK
  Future<void> _fetchPanelWaitingSettings() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_pricing_settings.php'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['pricing'] != null) {
          final pricing = data['pricing'];
          
          setState(() {
            _waitingFeePerInterval = double.tryParse(pricing['waiting_fee_per_interval']?.toString() ?? '200') ?? 200.0;
            _waitingFreeMinutes = int.tryParse(pricing['waiting_fee_free_minutes']?.toString() ?? '15') ?? 15;
            _waitingIntervalMinutes = int.tryParse(pricing['waiting_interval_minutes']?.toString() ?? '15') ?? 15;
          });
          
          print('✅ ŞOFÖR: Panel bekleme ayarları çekildi - İlk $_waitingFreeMinutes dk ücretsiz, sonra her $_waitingIntervalMinutes dk ₺$_waitingFeePerInterval');
        }
      }
    } catch (e) {
      print('⚠️ ŞOFÖR: Panel ayar çekme hatası, varsayılan kullanılıyor: $e');
    }
  }
  
  // ✅ SAATLİK PAKETLERI PANEL'DEN ÇEK (CACHE!)
  Future<void> _loadHourlyPackages() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_hourly_packages.php'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['packages'] != null) {
          final packages = data['packages'] as List;
          
          _cachedHourlyPackages = packages.map((pkg) => {
            'start': double.tryParse(pkg['start_hour']?.toString() ?? '0') ?? 0.0,
            'end': double.tryParse(pkg['end_hour']?.toString() ?? '0') ?? 0.0,
            'price': double.tryParse(pkg['price']?.toString() ?? '0') ?? 0.0,
          }).toList();
          
          print('✅ [ŞOFÖR] ${_cachedHourlyPackages.length} saatlik paket yüklendi');
        }
      }
    } catch (e) {
      print('⚠️ [ŞOFÖR] Saatlik paket hatası: $e');
    }
  }
  
  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.elasticOut));
    
    _slideController.forward();
  }
  
  void _saveToPersistence() async {
    try {
      print('💾 ŞOFÖR: Persistence kaydetme başlıyor... (Waiting: $_waitingMinutes dk, Started: $_isRideStarted)');
      
      final prefs = await SharedPreferences.getInstance();
      
      // GÜÇLENDİRİLMİŞ PERSISTENCE - BEKLEME + BAŞLATMA DURUMLARI!
      final rideData = {
        'ride_id': widget.rideDetails['ride_id'],
        'status': _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted',
        'pickup_address': widget.rideDetails['pickup_address'] ?? '',
        'destination_address': widget.rideDetails['destination_address'] ?? '',
        'estimated_price': widget.rideDetails['estimated_price']?.toString() ?? '0',
      'calculated_price': _calculatedTotalPrice,
        'customer_name': _currentRideStatus['customer_name'] ?? widget.rideDetails['customer_name'] ?? 'Müşteri',
        'customer_phone': widget.rideDetails['customer_phone'] ?? '',
        'customer_id': widget.rideDetails['customer_id']?.toString() ?? '0',
        'saved_at': DateTime.now().toIso8601String(),
        'is_ride_started': _isRideStarted, // BAŞLATMA DURUMU!
        'ride_start_time': _rideStartTime?.toIso8601String(), // BAŞLATMA ZAMANI!
        'waiting_minutes': _waitingMinutes, // BEKLEME SÜRESİ - MEVCUT DEĞER!
        'is_waiting_active': _isWaitingActive, // BEKLEME AKTİF Mİ!
      };
      
      await prefs.setString('active_driver_ride_data', jsonEncode(rideData));
      await prefs.setString('driver_ride_state', 'active');
      
      print('✅ ŞOFÖR: Persistence kaydedildi - Ride: ${widget.rideDetails['ride_id']}, Started: $_isRideStarted, Waiting: $_waitingMinutes dk, Active: $_isWaitingActive');
      print('   📦 Kaydedilen waiting_minutes: ${rideData['waiting_minutes']}');
    } catch (e) {
      print('❌ ŞOFÖR: Persistence kaydetme hatası: $e');
    }
  }
  
  void _calculateEarnings() {
    // SADECE YOLCULUK BAŞLADIYSA HESAPLA!
    if (!_isRideStarted) {
      // Yolculuk başlamamışsa ama estimated_price varsa onu göster
      final estimatedPrice = double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0;
      if (estimatedPrice > 0) {
        setState(() {
          _calculatedTotalPrice = estimatedPrice;
          _estimatedEarnings = estimatedPrice * 0.7; // %30 komisyon
          _waitingFee = 0.0;
        });
        widget.rideDetails['calculated_price'] = estimatedPrice;
        print('💰 ŞOFÖR: Yolculuk başlamamış ama estimated_price var: ₺${estimatedPrice.toStringAsFixed(2)} → Net: ₺${_estimatedEarnings.toStringAsFixed(2)}');
      } else {
        setState(() {
          _calculatedTotalPrice = 0.0;
          _estimatedEarnings = 0.0;
          _waitingFee = 0.0;
        });
      }
      return;
    }

    // Panel fiyatlarını kullan
    _calculateEarningsFromPanel();
  }
  
  // PANEL FİYATLARIYLA KAZANÇ HESAPLAMA
  Future<void> _calculateEarningsFromPanel() async {
    try {
      // Panel'den fiyat bilgilerini çek
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_pricing_info.php'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['pricing'] != null) {
          final pricing = data['pricing'];
          
          // Panel'den gelen fiyatlar + BEKLEME AYARLARI CLASS DEĞİŞKENLERİNE!
          final basePrice = double.tryParse(pricing['base_price']?.toString() ?? '0') ?? 50.0;
          final kmPrice = double.tryParse(pricing['km_price']?.toString() ?? '0') ?? 8.0;
          
          // BEKLEME AYARLARINI CLASS DEĞİŞKENLERİNE KAYDEDİN!
          _waitingFreeMinutes = int.tryParse(pricing['waiting_fee_free_minutes']?.toString() ?? '15') ?? 15;
          _waitingFeePerInterval = double.tryParse(pricing['waiting_fee_per_interval']?.toString() ?? '200') ?? 200.0;
          _waitingIntervalMinutes = int.tryParse(pricing['waiting_interval_minutes']?.toString() ?? '15') ?? 15;
          
          final commissionRateRaw = double.tryParse(pricing['commission_rate']?.toString() ?? '0') ?? 0.0;
          final commissionRate = commissionRateRaw >= 1 ? commissionRateRaw / 100.0 : commissionRateRaw;
          
          print('✅ ŞOFÖR PANEL AYARLAR: İlk $_waitingFreeMinutes dk ücretsiz, her $_waitingIntervalMinutes dk ₺$_waitingFeePerInterval, Komisyon: %${(commissionRate * 100).toInt()}');
        final minimumFare = double.tryParse(pricing['minimum_fare']?.toString() ?? '0') ?? 0.0;
        final overnightThresholdHours = double.tryParse(pricing['overnight_package_threshold']?.toString() ?? '0') ?? 0.0;
        final hourlyPackagePrice = double.tryParse(pricing['hourly_package_price']?.toString() ?? '0') ?? 0.0;
        final driverRate = 1 - commissionRate;
        final currentKm = double.tryParse(
              _currentRideStatus['current_km']?.toString() ??
                  widget.rideDetails['current_km']?.toString() ??
                  '0',
            ) ??
            0.0;
        
        // ÖNCE ESTIMATED_PRICE KONTROL ET!
        final estimatedPriceFromRide = double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0;
        
        double totalPrice;
        double baseAndDistanceGross;
        
        if (estimatedPriceFromRide > 0 && currentKm == 0) {
          // BAŞLANGIÇ: estimated_price varsa ve henüz KM yoksa onu kullan
          totalPrice = estimatedPriceFromRide;
          baseAndDistanceGross = estimatedPriceFromRide;
          print('💰 ŞOFÖR: Estimated price kullanılıyor: ₺${estimatedPriceFromRide.toStringAsFixed(2)}');
        } else {
          // YOLCULUK DEVAM EDİYOR: KM bazlı hesaplama
          final kmComponent = currentKm * kmPrice;
          baseAndDistanceGross = basePrice + kmComponent;
          totalPrice = baseAndDistanceGross;
          print('💰 ŞOFÖR: KM bazlı hesaplama: Base ₺$basePrice + KM (${currentKm}km × ₺$kmPrice) = ₺${totalPrice.toStringAsFixed(2)}');
        }

        // ✅ SAATLİK PAKET KONTROLÜ ÖNCE YAPILMALI!
        bool isHourlyMode = false;
        
        // Service type direkt kontrol et!
        final serviceType = widget.rideDetails['service_type']?.toString().toLowerCase() ?? 
                           _currentRideStatus['service_type']?.toString().toLowerCase() ?? '';
        
        if (serviceType == 'hourly') {
          isHourlyMode = true;
          print('📦 [ŞOFÖR] SAATLİK PAKET (service_type=hourly) - Bekleme ücreti İPTAL!');
        } else if (_isRideStarted && _rideStartTime != null) {
          final rideDurationHours = DateTime.now().difference(_rideStartTime!).inMinutes / 60.0;
          if (rideDurationHours >= 2.0) {
            isHourlyMode = true;
            print('📦 [ŞOFÖR] 2+ SAAT GEÇTİ - Bekleme ücreti İPTAL!');
          }
        }

        // Bekleme ücreti hesaplama - SAATLİK PAKETTE İPTAL!
        double waitingFeeGross = 0.0;
        if (!isHourlyMode && _isRideStarted && _waitingMinutes > _waitingFreeMinutes) {
          final chargeableMinutes = _waitingMinutes - _waitingFreeMinutes;
          final intervals = (chargeableMinutes / _waitingIntervalMinutes).ceil();
          waitingFeeGross = intervals * _waitingFeePerInterval;
          totalPrice += waitingFeeGross;
          print('💰 ŞOFÖR: Bekleme ücreti eklendi: $_waitingMinutes dk (ücretsiz: $_waitingFreeMinutes dk) → $intervals aralık × ₺$_waitingFeePerInterval = +₺${waitingFeeGross.toStringAsFixed(2)}');
        } else if (isHourlyMode) {
          print('✅ [ŞOFÖR] SAATLİK PAKET - Bekleme ücreti 0!');
        }

        if (totalPrice < minimumFare && minimumFare > 0) {
          totalPrice = minimumFare;
        }

        // SAATLİK PAKET SİSTEMİ - 2 SAAT SONRA PAKET FİYATI!
        if (_isRideStarted && _rideStartTime != null) {
          final rideDurationHours = DateTime.now().difference(_rideStartTime!).inMinutes / 60.0;
          
          if (rideDurationHours >= 2.0) {
            // CACHE'LENMIŞ PAKETLERI KULLAN!
            if (_cachedHourlyPackages.isNotEmpty) {
              // Hangi pakette olduğunu belirle
              double? packagePrice;
              String packageLabel = '';
              
              for (var pkg in _cachedHourlyPackages) {
                final startHour = pkg["start"] ?? 0.0;
                final endHour = pkg["end"] ?? 0.0;
                final price = pkg["price"] ?? 0.0;
                
                if (rideDurationHours >= startHour && rideDurationHours < endHour) {
                  packagePrice = price;
                  packageLabel = "$startHour-$endHour saat";
                  break;
                }
              }
              
              // Bulunamazsa son paketi kullan
              if (packagePrice == null && _cachedHourlyPackages.isNotEmpty) {
                final lastPkg = _cachedHourlyPackages.last;
                packagePrice = lastPkg["price"];
                final startHour = lastPkg["start"] ?? 0.0;
                packageLabel = "$startHour+ saat";
              }
              
              if (packagePrice != null && packagePrice > 0) {
                totalPrice = packagePrice;
                print('📦 SAATLİK PAKET: $packageLabel (${rideDurationHours.toStringAsFixed(2)}saat) → ₺${totalPrice.toStringAsFixed(2)}');
                print('   ✅ PANELDEN CACHE - ${_cachedHourlyPackages.length} paket mevcut');
                print('   ⚠️ KM HESABI YOK - SADECE PAKET FİYATI!');
              }
            } else {
              // Fallback
              print('⚠️ [ŞOFÖR] Cache boş - fallback hourlyPackagePrice');
              if (hourlyPackagePrice > 0) {
                totalPrice = hourlyPackagePrice;
              }
            }
          }
        }

        final totalDriverNet = totalPrice * driverRate;
        final waitingFeeNet = waitingFeeGross * driverRate;
        final baseDriverNet = math.max(0.0, totalDriverNet - waitingFeeNet);

        setState(() {
          _waitingFee = waitingFeeNet; // Komisyonlu (şoför kazancı için)
          _waitingFeeGross = waitingFeeGross; // KOMİSYONSUZ (müşteriye göstermek için)!
          _estimatedEarnings = baseDriverNet;
          _calculatedTotalPrice = totalPrice;
        });
        
        widget.rideDetails['calculated_price'] = totalPrice;
        _currentRideStatus['calculated_price'] = totalPrice;
        _currentRideStatus['current_km'] = currentKm;
        _currentRideStatus['night_package_threshold_hours'] = overnightThresholdHours;

        print('💰 PANEL FİYAT HESAPLAMA:');
        print('   💵 Base: ₺$basePrice, KM: ₺$kmPrice, Komisyon: %${(commissionRate * 100).toInt()}');
        print('   📏 Güncel KM: $currentKm, Toplam (brüt): ₺${totalPrice.toStringAsFixed(2)}');
        print('   💰 Şoför Net Kazanç: ₺${totalDriverNet.toStringAsFixed(2)} (Taban: ₺${baseDriverNet.toStringAsFixed(2)} + Bekleme: ₺${waitingFeeNet.toStringAsFixed(2)})');
        print('   🔍 _estimatedEarnings SET EDİLDİ: ₺${_estimatedEarnings.toStringAsFixed(2)}, _waitingFee: ₺${_waitingFee.toStringAsFixed(2)}');
        
        return;
        }
      }
    } catch (e) {
      print('❌ Panel fiyat alma hatası: $e');
    }
    
    // Fallback - varsayılan hesaplama
    final basePriceFallback = double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0;
    final currentKmFallback = double.tryParse(
          widget.rideDetails['current_km']?.toString() ??
              _currentRideStatus['current_km']?.toString() ??
              '0',
        ) ??
        0.0;
    const kmPriceFallback = 8.0;
    const waitingFreeMinutesFallback = 30;
    const waitingIntervalMinutesFallback = 15;
    const waitingFeePerIntervalFallback = 150.0;
    const commissionRateFallback = 0.30;
    const driverRateFallback = 1 - commissionRateFallback;
    const overnightThresholdFallback = 2.0;
    const hourlyPackagePriceFallback = 300.0;

    final baseAndDistanceGrossFallback = basePriceFallback + (currentKmFallback * kmPriceFallback);
    double waitingFeeGrossFallback = 0.0;
    if (_isRideStarted && _waitingMinutes > waitingFreeMinutesFallback) {
      final chargeableMinutes = _waitingMinutes - waitingFreeMinutesFallback;
      final intervals = (chargeableMinutes / waitingIntervalMinutesFallback).ceil();
      waitingFeeGrossFallback = intervals * waitingFeePerIntervalFallback;
    }

    double totalPriceFallback = baseAndDistanceGrossFallback + waitingFeeGrossFallback;
    
    // Fallback - brüt bekleme ücretini de kaydet
    _waitingFeeGross = waitingFeeGrossFallback;

    // FALLBACK SAATLİK PAKET
    if (_isRideStarted && _rideStartTime != null) {
      final rideDurationHours = DateTime.now().difference(_rideStartTime!).inMinutes / 60.0;
      
      if (rideDurationHours >= 2.0) {
        // Varsayılan saatlik paketler
        const packages = [
          {'start': 0.0, 'end': 4.0, 'price': 3000.0},
          {'start': 4.0, 'end': 8.0, 'price': 4500.0},
          {'start': 8.0, 'end': 12.0, 'price': 6000.0},
        ];
        
        double? pkgPrice;
        for (var pkg in packages) {
          if (rideDurationHours >= pkg['start']! && rideDurationHours < pkg['end']!) {
            pkgPrice = pkg['price'];
            break;
          }
        }
        
        if (pkgPrice == null) {
          pkgPrice = packages.last['price'];
        }
        
        if (pkgPrice != null && pkgPrice > 0) {
          totalPriceFallback = pkgPrice;
          print('📦 FALLBACK SAATLİK PAKET: ₺${pkgPrice.toStringAsFixed(2)}');
        }
      }
    }

    final totalDriverNetFallback = totalPriceFallback * driverRateFallback;
    final waitingFeeNetFallback = waitingFeeGrossFallback * driverRateFallback;
    final baseDriverNetFallback = math.max(0.0, totalDriverNetFallback - waitingFeeNetFallback);

    setState(() {
      _waitingFee = waitingFeeNetFallback;
      _waitingFeeGross = waitingFeeGrossFallback; // FALLBACK - KOMİSYONSUZ!
      _estimatedEarnings = baseDriverNetFallback;
      _calculatedTotalPrice = totalPriceFallback;
    });
    widget.rideDetails['calculated_price'] = totalPriceFallback;
    _currentRideStatus['calculated_price'] = totalPriceFallback;
    _currentRideStatus['current_km'] = currentKmFallback;
    _currentRideStatus['night_package_threshold_hours'] = overnightThresholdFallback;

    print('💰 FALLBACK Kazanç hesaplama: Toplam (brüt)=₺${totalPriceFallback.toStringAsFixed(2)}, Şoför Net=₺${totalDriverNetFallback.toStringAsFixed(2)} (Taban=₺${baseDriverNetFallback.toStringAsFixed(2)} + Bekleme=₺${waitingFeeNetFallback.toStringAsFixed(2)})');
  }
  
  void _initializeRideTracking() async {
    try {
      print('🚗 [ŞOFÖR MODERN] Aktif yolculuk takibi başlatılıyor...');
      
      if (_waitingMinutes == 0 && widget.waitingMinutes > 0) {
        setState(() {
          _waitingMinutes = widget.waitingMinutes;
        });
      }
      
      // MÜŞTERİ BİLGİLERİNİ ÇEK!
      await _loadCustomerDetails();
      
      await _updateRideStatus();
      
      // Real-time tracking (her 5 saniye) + PERSISTENCE + REAL-TIME DATA AKTARIMI + İPTAL KONTROLÜ!
      _trackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _updateRideStatus();
        _saveToPersistence(); // SÜREKLI KAYDET!
        _checkRideCancellation(); // İPTAL KONTROLÜ EKLE!
        if (_isRideStarted) {
          _sendRealTimeDataToCustomer(); // MÜŞTERİYE ANLıK VERİ GÖNDER!
        }
      });
      
      // Waiting timer OTOMATIK BAŞLATMA!
      // _startWaitingTimer(); // KALDIRILDI - MANUEL BAŞLATMA
      
      setState(() {
        _isLoading = false;
      });
      
      print('✅ [ŞOFÖR MODERN] Yolculuk takibi aktif');
      
    } catch (e) {
      print('❌ [ŞOFÖR MODERN] Takip başlatma hatası: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // MÜŞTERİ BİLGİLERİ ÇEKME SİSTEMİ
  Future<void> _loadCustomerDetails() async {
    try {
      final customerId = widget.rideDetails['customer_id']?.toString() ?? '0';
      print('👤 ŞOFÖR: Müşteri bilgileri çekiliyor - ID: $customerId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_customer_details.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'customer_id': customerId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['customer'] != null) {
          final fetchedNameRaw = data['customer']['name']?.toString().trim() ?? '';
          final customerName = fetchedNameRaw.isNotEmpty ? fetchedNameRaw : 'Müşteri';
          final customerPhone = data['customer']['phone']?.toString() ?? '';
          final customerRating = data['customer']['rating'] ?? 5.0;
          setState(() {
            // Widget.rideDetails'i güncelle
            widget.rideDetails['customer_name'] = customerName;
            widget.rideDetails['customer_phone'] = customerPhone;
            widget.rideDetails['customer_rating'] = customerRating;
            _currentRideStatus['customer_name'] = customerName;
            _currentRideStatus['customer_phone'] = customerPhone;
            _currentRideStatus['customer_rating'] = customerRating;
          });
          unawaited(RidePersistenceService.updateRideData({
            'customer_name': customerName,
            'customer_phone': customerPhone,
            'customer_rating': customerRating,
          }));
          
          print('✅ ŞOFÖR: Müşteri bilgileri yüklendi - $customerName');
        }
      }
    } catch (e) {
      print('❌ ŞOFÖR: Müşteri bilgileri çekme hatası: $e');
    }
  }
  
  // MANUEL TIMER TAMAMEN KALDIRILDI!
  // Backend TIMESTAMPDIFF ile otomatik sayıyor, manuel sayma GEREKSİZ!
  // void _startWaitingTimer() {
  //   _waitingTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
  //     setState(() {
  //       _waitingMinutes++;
  //     });
  //     _calculateEarnings();
  //     
  //     // Bekleme durumunu persistence'a kaydet
  //     RidePersistenceService.updateRideMetrics(waitingMinutes: _waitingMinutes);
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // ALT BAR EKLENDİ - ŞOFÖR MODERN YOLCULUK EKRANI! ✅
      bottomNavigationBar: _buildDriverModernBottomBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading 
            ? _buildLoadingState()
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Üst Header - Kazanç ve Durum
                    _buildDriverHeader(),
                    
                    // Alt Kontrol Paneli
                    _buildDriverBottomPanel(),
                  ],
                ),
              ),
        ),
      ),
    );
  }
  
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFFD700),
                        Color(0xFFFF8C00),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.6),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_taxi,
                    size: 60,
                    color: Colors.black,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Yolculuk bilgileri hazırlanıyor...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDriverHeader() {
    return Container(
      padding: const EdgeInsets.all(15), // %25 küçültme (20->15)
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFD700),
            Color(0xFFFFA500),
            Color(0xFFFF8C00),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(35),
          bottomRight: Radius.circular(35),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.4),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Üst satır
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Geri butonu kaldırıldı - şoför yolculuk sırasında çıkamaz
              const SizedBox(width: 33), // Boş alan (%25 küçük)
              AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), // %25 küçültme
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(_glowAnimation.value * 0.4),
                          blurRadius: 15,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                      child: const Text(
                        '🚗 AKTİF YOLCULUK',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 12, // %25 küçültme (16->12)
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  );
                },
              ),
              // Sağ üst chat simgesi kaldırıldı - sadece alt barda mesaj butonu
              const SizedBox(width: 33), // Boş alan (%25 küçük)
            ],
          ),
          
          const SizedBox(height: 15), // %25 küçültme (20->15)
          
          // Kazanç Metrikleri
          _buildEarningsMetrics(),
          
          const SizedBox(height: 8),
          
          // Tahmini Tutar (ince gösterim)
          _buildPriceInfo(),
          
          const SizedBox(height: 12), // %25 küçültme (16->12)
          
          // Müşteri Bilgileri
          _buildCustomerInfoRow(),
        ],
      ),
    );
  }
  
  Widget _buildEarningsMetrics() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12), // %25 küçültme (16->12)
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.route,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(height: 6),
                  Text(
                    '${_getCurrentKm()} km',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Gidilen KM',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 9), // %25 küçültme (12->9)
        
        // Bekleme süresi
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12), // %25 küçültme (16->12)
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Icon(
                        Icons.timer,
                        color: _waitingMinutes > 0 ? Colors.orange : Colors.white,
                        size: 18, // %25 küçültme (24->18)
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _getWaitingOrDurationDisplay(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isHourlyPackageActive() ? 'Süre' : 'Bekleme Süresi',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPriceInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Text(
            'Tahmini Tutar: ₺${_calculatedTotalPrice.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCustomerInfoRow() {
    return Container(
      padding: const EdgeInsets.all(12), // %25 küçültme (16->12)
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Müşteri Avatar
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(_glowAnimation.value * 0.6),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 19, // %25 küçültme (25->19)
                  backgroundColor: Colors.blue,
                  child: Text(
                    (widget.rideDetails['customer_name'] ?? 'M')[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15, // %25 küçültme (20->15)
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12), // %25 küçültme (16->12)
          Expanded(
            child: Text(
              widget.rideDetails['customer_name'] ?? 
              _currentRideStatus['customer_name'] ?? 
              'Müşteri İsmi Yükleniyor...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // VALE/SAATLİK BADGE KALDIRILDI - SADECE MÜŞTERİ İSMİ GÖZÜKSÜN!
        ],
      ),
    );
  }
  
  Widget _buildDriverBottomPanel() {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A2A3E),
              Color(0xFF1A1A2E),
              Color(0xFF0A0A0A),
            ],
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(35),
            topRight: Radius.circular(35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 15),
              width: 60,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Durum Kartı
                  _buildDriverStatusCard(),
                  const SizedBox(height: 20),
                  
                  // Rota Bilgileri
                  _buildRouteInfoCard(),
                  const SizedBox(height: 20),
                  
                  // Aksiyon Butonları
                  _buildDriverActionButtons(),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDriverStatusCard() {
    final status = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted';
    final statusInfo = _getDriverStatusInfo(status);
    
    // 'accepted' durumunda kartı gizle
    if (status == 'accepted') {
      return const SizedBox.shrink();
    }
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: statusInfo['colors'],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: statusInfo['colors'][0].withOpacity(0.3),
                blurRadius: 12,
                spreadRadius: _pulseAnimation.value * 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  statusInfo['icon'],
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusInfo['title'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (statusInfo['subtitle'].toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        statusInfo['subtitle'],
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildRouteInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route, color: Color(0xFFFFD700), size: 20),
              SizedBox(width: 8),
              Text(
                'Rota Detayları',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Alış noktası - TIKLANABİLİR NAVİGASYON!
          InkWell(
            onTap: () => _openNavigationToPickup(),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.rideDetails['pickup_address'] ?? 
                    _currentRideStatus['pickup_address'] ?? 
                    'Alış konumu yükleniyor...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.navigation, color: Color(0xFFFFD700), size: 16),
              ],
            ),
          ),
          
          // Çizgi
          Container(
            margin: const EdgeInsets.only(left: 5, top: 8, bottom: 8),
            width: 2,
            height: 20,
            color: Colors.white.withOpacity(0.3),
          ),
          
          // Varış noktası - TIKLANABİLİR NAVİGASYON!
          InkWell(
            onTap: () => _openNavigationToDestination(),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.rideDetails['destination_address'] ?? 
                    _currentRideStatus['destination_address'] ?? 
                    'Varış konumu yükleniyor...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.navigation, color: Color(0xFFFFD700), size: 16),
              ],
            ),
          ),
          
          // VALE GELME SAATİ - MÜŞTERİNİN SEÇTİĞİ ZAMAN!
          if (widget.rideDetails['scheduled_time'] != null && 
              _getScheduledTimeDisplay() != 'Hemen') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⏰ Vale Gelme Saati',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _getScheduledTimeDisplay(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionRow() {
    final pickupAddress = widget.rideDetails['pickup_address'] ?? 'Alış konumu';
    final destinationAddress = widget.rideDetails['destination_address'] ?? 'Varış konumu';

    return Row(
      children: [
        Expanded(
          child: _buildQuickActionButton(
            title: 'Navigasyon',
            subtitle: _isRideStarted ? destinationAddress : pickupAddress,
            icon: Icons.navigation,
            startColor: const Color(0xFF4CAF50),
            endColor: const Color(0xFF81C784),
            onTap: () {
              if (_isRideStarted) {
                _openNavigationToDestination();
              } else {
                _openNavigationToPickup();
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickActionButton(
            title: 'Köprü Ara',
            subtitle: widget.rideDetails['customer_name'] ?? 'Müşteri',
            icon: Icons.phone_in_talk,
            startColor: const Color(0xFF42A5F5),
            endColor: const Color(0xFF1E88E5),
            onTap: _callCustomerDirectly,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color startColor,
    required Color endColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [startColor, endColor]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: endColor.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDriverActionButtons() {
    final status = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted';
    
    return Column(
      children: [
        // Ana aksiyon butonu
        Container(
          width: double.infinity,
          height: 65,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFFD700),
                Color(0xFFFF8C00),
              ],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton(
        onPressed: _isRideStarted ? _showCompleteRideConfirmation : _showStartRideConfirmation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: Text(
          _isRideStarted ? 'Yolculuğu Sonlandır' : 'Yolculuğu Başlat',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
        ),
        
        const SizedBox(height: 12),
        
                  // BEKLEME KONTROL BUTONU - SAATLİK PAKETTE GİZLENİR!
                  if (_shouldShowWaitingButton) ...[
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: !_isRideStarted 
                            ? [Colors.grey, Colors.grey[400]!]
                            : _isWaitingActive 
                              ? [Colors.red, Colors.redAccent] 
                              : [Colors.orange, Colors.deepOrange],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: (!_isRideStarted ? Colors.grey : (_isWaitingActive ? Colors.red : Colors.orange)).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: !_isRideStarted ? null : (_isWaitingActive ? _stopWaiting : _startWaiting),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              !_isRideStarted 
                                ? Icons.lock
                                : _isWaitingActive ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  !_isRideStarted 
                                    ? 'Önce Yolculuğu Başlatın'
                                    : _isWaitingActive ? 'Bekleme Durdur' : 'Bekleme Başlat',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_isRideStarted && _waitingMinutes > 0) ...[
                                  Text(
                                    '$_waitingMinutes dakika (₺${_waitingFeeGross.toStringAsFixed(0)})',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
        
        // Alt aksiyon butonları
        Row(
          children: [
            // DİREKT MÜŞTERİ ARAMA SİSTEMİ! ✅
            Expanded(
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.blue, Colors.indigo],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ElevatedButton(
                  onPressed: () => _callCustomerDirectly(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone, color: Colors.white, size: 20),
                      SizedBox(width: 4),
                      Text(
                        'Müşteriyi Ara',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            
            // Mesaj butonu
            Expanded(
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.deepPurple],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: ElevatedButton(
                  onPressed: () => _openMessaging(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.message, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Mesaj',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Map<String, dynamic> _getDriverStatusInfo(String status) {
    switch (status) {
      case 'accepted':
        return {
          'title': '', // Boş bırakıldı
          'subtitle': '', // Boş bırakıldı
          'icon': Icons.directions_car,
          'colors': [const Color(0xFF4CAF50), const Color(0xFF81C784)],
        };
      case 'driver_arrived':
        return {
          'title': '📍 Müşteri Yanındasınız',
          'subtitle': 'Müşteriyi bekleyin',
          'icon': Icons.location_on,
          'colors': [const Color(0xFFFF9800), const Color(0xFFFFCC02)],
        };
      case 'ride_started':
      case 'in_progress':
        return {
          'title': '🚗 Yolculuk Devam Ediyor',
          'subtitle': 'İyi yolculuklar',
          'icon': Icons.directions_car,
          'colors': [const Color(0xFF2196F3), const Color(0xFF64B5F6)],
        };
      case 'waiting_customer':
        return {
          'title': '⏳ Müşteri Bekleniyor',
          'subtitle': 'Bekleme süresi: $_waitingMinutes dakika',
          'icon': Icons.timer,
          'colors': [const Color(0xFFFF9800), const Color(0xFFFFA726)],
        };
      default:
        return {
          'title': '📡 Bilgiler senkronize ediliyor',
          'subtitle': 'Durum kısa süre içinde güncellenecek',
          'icon': Icons.sync,
          'colors': [const Color(0xFF9C27B0), const Color(0xFFBA68C8)],
        };
    }
  }
  
  String _getMainActionText(String status) {
    switch (status) {
      case 'accepted':
        return '🚗 Müşteri Yanına Git';
      case 'driver_arrived':
        return '✅ Yolculuğu Başlat';
      case 'ride_started':
      case 'in_progress':
        return '🏁 Yolculuğu Tamamla';
      case 'waiting_customer':
        return '⏳ Müşteri Bekleniyor';
      default:
        return '🔄 Durum Güncelleniyor';
    }
  }
  
  Future<void> _handleMainAction(String status) async {
    switch (status) {
      case 'accepted':
        await _markDriverArrived();
        break;
      case 'driver_arrived':
        await _startRide();
        break;
      case 'ride_started':
        await _completeRide();
        break;
    }
  }
  
  Future<void> _updateRideStatus() async {
    try {
      print('🚗 [ŞOFÖR] Yolculuk durumu güncellemesi başlıyor...');

      final prefs = await SharedPreferences.getInstance();
      final storedDriverId = prefs.getString('driver_id') ?? prefs.getInt('driver_id')?.toString();
      final driverId = storedDriverId ?? widget.rideDetails['driver_id']?.toString() ?? '0';
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';

      if (driverId == '0' || rideId == '0') {
        print('⚠️ [ŞOFÖR] Güncelleme atlandı (driverId:$driverId rideId:$rideId)');
        return;
      }

      final uri = Uri.parse(
        'https://admin.funbreakvale.com/api/check_driver_active_ride.php?driver_id=$driverId&ride_id=$rideId',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        print('❌ [ŞOFÖR] Durum API HTTP ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['has_active_ride'] != true) {
        print('🚫 [ŞOFÖR] BACKEND: Aktif yolculuk yok veya iptal edildi!');
        print('📋 Backend response: $data');
        
        // PERSİSTENCE TEMİZLE!
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_driver_ride_data');
        await prefs.remove('driver_ride_state');
        await prefs.remove('current_ride'); // DriverRideProvider için!
        await prefs.remove('ride_cancelled_flag'); // Flag'i de temizle!
        print('✅ [ŞOFÖR] Tüm persistence temizlendi!');
        
        // PERİODİC TIMER DURDUR!
        _trackingTimer?.cancel();
        print('⏹️ [ŞOFÖR] Tracking timer durduruldu!');
        
        // ANA SAYFAYA DÖN!
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (route) => false);
          print('🏠 [ŞOFÖR] Ana sayfaya yönlendirild - yeni talep alabilir!');
        }
        
        return;
      }

      // Backend direkt data döndürüyor, ride_info wrapper YOK!
      final rideInfo = Map<String, dynamic>.from(data);

      // Panel ile sürücü status senkronunu doğrula
      final latestStatus = await RideService.fetchRideStatus(rideId, driverId);
      if (latestStatus != null) {
        rideInfo.addAll(latestStatus);
      }

      final status = (rideInfo['status'] ?? widget.rideDetails['status'] ?? 'accepted').toString();
      final isStartedStatus = {
        'in_progress',
        'started',
        'ride_started',
        'arrived',
        'completed',
      }.contains(status);

      final pickupLat = double.tryParse(rideInfo['pickup_latitude']?.toString() ?? '') ??
          _customerLocation?.latitude ?? 0.0;
      final pickupLng = double.tryParse(rideInfo['pickup_longitude']?.toString() ?? '') ??
          _customerLocation?.longitude ?? 0.0;
      final destinationLat = double.tryParse(rideInfo['destination_latitude']?.toString() ?? '') ??
          _currentRideStatus['destination_latitude'] ?? pickupLat;
      final destinationLng = double.tryParse(rideInfo['destination_longitude']?.toString() ?? '') ??
          _currentRideStatus['destination_longitude'] ?? pickupLng;

      final currentKmFromApi = double.tryParse(rideInfo['current_km']?.toString() ?? '') ??
          double.tryParse(_currentRideStatus['current_km']?.toString() ?? '') ??
          0.0;

      // BACKEND'DEN GELEN BEKLEME SÜRESİNİ KULLAN (TIMESTAMPDIFF otomatik!)
      final waitingFromApi = int.tryParse(
            (rideInfo['waiting_minutes'] ?? rideInfo['waiting_time_minutes'])?.toString() ??
                '',
          ) ??
          0;
      
      // Backend bekleme durumu kontrolü - Aktif mi?
      final waitingStartTime = rideInfo['waiting_start_time'];
      final backendWaitingActive = waitingStartTime != null && 
                                    waitingStartTime.toString() != 'null' && 
                                    waitingStartTime.toString().isNotEmpty;
      
      // SADECE waiting_minutes kullan!
      if (waitingFromApi != _waitingMinutes) {
        print('⏳ ŞOFÖR: Backend bekleme: $_waitingMinutes → $waitingFromApi dk');
      }
      
      // Backend bekleme durumunu senkronize et (setState ÖNCE!)
      if (backendWaitingActive != _isWaitingActive) {
        print('🔄 ŞOFÖR: Bekleme durumu backend\'den güncellendi: $_isWaitingActive → $backendWaitingActive');
        _isWaitingActive = backendWaitingActive;
      }
      
      setState(() {
        _currentRideStatus = rideInfo;
        _currentRideStatus['customer_name'] = rideInfo['customer_name'] ?? widget.rideDetails['customer_name'];
        widget.rideDetails['status'] = status;
        widget.rideDetails['customer_name'] = rideInfo['customer_name'] ?? widget.rideDetails['customer_name'];
        widget.rideDetails['customer_phone'] = rideInfo['customer_phone'] ?? widget.rideDetails['customer_phone'];
        widget.rideDetails['pickup_address'] = rideInfo['pickup_address'] ?? widget.rideDetails['pickup_address'];
        widget.rideDetails['destination_address'] = rideInfo['destination_address'] ?? widget.rideDetails['destination_address'];
        widget.rideDetails['estimated_price'] = rideInfo['estimated_price'] ?? widget.rideDetails['estimated_price'];
        widget.rideDetails['current_km'] = currentKmFromApi;
        
        // SAATLİK PAKET TESPİTİ İÇİN BACKEND'DEN GELEN DEĞERLER!
        widget.rideDetails['service_type'] = rideInfo['service_type'] ?? widget.rideDetails['service_type'];
        widget.rideDetails['ride_type'] = rideInfo['ride_type'] ?? widget.rideDetails['ride_type'];

        _customerLocation = LatLng(pickupLat, pickupLng);
        _markers = {
          if (_customerLocation != null)
            Marker(
              markerId: const MarkerId('pickup'),
              position: _customerLocation!,
              infoWindow: InfoWindow(title: widget.rideDetails['pickup_address'] ?? 'Alış Konumu'),
            ),
          Marker(
            markerId: const MarkerId('destination'),
            position: LatLng(destinationLat, destinationLng),
            infoWindow: InfoWindow(title: widget.rideDetails['destination_address'] ?? 'Varış Konumu'),
          ),
        };

        // Backend'den gelen bekleme süresini direkt ata
        _waitingMinutes = waitingFromApi;
        _currentRideStatus['waiting_minutes'] = waitingFromApi;
        _currentRideStatus['current_km'] = currentKmFromApi;
        _currentRideStatus['service_type'] = rideInfo['service_type'];
        _currentRideStatus['ride_type'] = rideInfo['ride_type'];

        if (isStartedStatus && !_isRideStarted) {
          _isRideStarted = true;
          _rideStartTime = DateTime.tryParse(rideInfo['started_at']?.toString() ?? '') ?? _rideStartTime;
        }
      });

      await RidePersistenceService.saveActiveRide(
        rideId: int.tryParse(rideId) ?? 0,
        status: status,
        pickupAddress: widget.rideDetails['pickup_address'] ?? '',
        destinationAddress: widget.rideDetails['destination_address'] ?? '',
        estimatedPrice: double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0,
        customerName: widget.rideDetails['customer_name'] ?? 'Müşteri',
        customerPhone: widget.rideDetails['customer_phone'] ?? '',
        customerId: widget.rideDetails['customer_id']?.toString() ?? '0',
      );

      _calculateEarnings();
    } catch (e) {
      print('❌ [ŞOFÖR] Yolculuk durumu güncelleme hatası: $e');
    }
  }
  
  // MANUEL BEKLEME KONTROLÜ
  void _startWaiting() async {
    setState(() {
      _isWaitingActive = true;
    });
    
    // BACKEND'E BEKLEME BAŞLATILDIĞINI BİLDİR!
    try {
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_ride_realtime_data.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'waiting_started': true, // BEKLEME BAŞLATILDI!
          'waiting_minutes': _waitingMinutes,
          'current_km': 0,
          'driver_lat': 0,
          'driver_lng': 0,
        }),
      ).timeout(const Duration(seconds: 10));
      print('⏰ ŞOFÖR: Backend\'e bekleme BAŞLATILDI bildirimi gönderildi');
    } catch (e) {
      print('⚠️ ŞOFÖR: Bekleme başlatma bildirimi hatası: $e');
    }
    
    // MANUEL TIMER KALDIRILDI - Backend TIMESTAMPDIFF ile otomatik sayıyor!
    // Backend'den gelen waiting_minutes direkt kullanılacak
    print('✅ ŞOFÖR: Bekleme backend\'den otomatik hesaplanacak (TIMESTAMPDIFF)');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.play_circle_filled, color: Colors.white),
            SizedBox(width: 8),
            Text('⏳ Bekleme süresi başlatıldı'),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    print('⏳ ŞOFÖR: Manuel bekleme başlatıldı');
    _saveToPersistence(); // BEKLEME DURUMUNU KAYDET!
    if (_isRideStarted) {
      unawaited(_sendRealTimeDataToCustomer());
    }
  }
  
  void _stopWaiting() async {
    print('⏹️ ŞOFÖR: Bekleme durdurma butonu tıklandı');
    
    setState(() {
      _isWaitingActive = false;
    });
    
    // MANUEL TIMER KALDIRILDI - Backend TIMESTAMPDIFF kullanıyor!
    // _waitingTimer?.cancel();
    // _waitingTimer = null;
    
    // BACKEND'E BEKLEME DURDURULDUĞUNU BİLDİR!
    try {
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_ride_realtime_data.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'waiting_started': false, // BEKLEME DURDURULDU!
          'waiting_minutes': _waitingMinutes, // SON DEĞER!
          'current_km': 0,
          'driver_lat': 0,
          'driver_lng': 0,
        }),
      ).timeout(const Duration(seconds: 10));
      print('⏹️ ŞOFÖR: Backend\'e bekleme DURDURULDU bildirimi gönderildi ($_waitingMinutes dk)');
    } catch (e) {
      print('⚠️ ŞOFÖR: Bekleme durdurma bildirimi hatası: $e');
    }
    
    _saveToPersistence(); // BEKLEME DURUMUNU KAYDET!
    if (_isRideStarted) {
      unawaited(_sendRealTimeDataToCustomer());
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.pause_circle_filled, color: Colors.white),
            const SizedBox(width: 8),
            Text('⏹️ Bekleme durduruldu ($_waitingMinutes dk)'),
          ],
        ),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    print('⏹️ ŞOFÖR: Manuel bekleme durduruldu - $_waitingMinutes dakika');
  }

  // YOLCULUK BAŞLATMA ONAYI!
  Future<void> _showStartRideConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.play_arrow, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Yolculuğu Başlat', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Müşteri araçta mı? Yolculuğu başlatmak istediğinize emin misiniz?',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '✅ Kilometre ve bekleme hesaplaması başlayacak',
              style: TextStyle(color: Colors.green, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '⏱️ Fiyat hesaplaması aktif hale gelecek',
              style: TextStyle(color: Colors.orange, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '📲 Müşteri uygulamasına bildirim gönderilecek',
              style: TextStyle(color: Colors.blue, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text('Başlat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _startRide();
      // ❌ BİLDİRİM KALDIRILDI - _startRide() içinde zaten gönderiliyor
      // await _notifyCustomerRideStarted();
      await _saveRideStartedToPersistence();
      _calculateEarnings();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.play_arrow, color: Colors.white),
              SizedBox(width: 8),
              Text('🚗 Yolculuk başlatıldı! Müşteri bilgilendirildi.'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      print('🚗 ŞOFÖR: Yolculuk başlatıldı - ${_rideStartTime}');
    }
  }
  
  // BAŞLATMA DURUMUNU PERSİSTENCE'A KAYDET!
  Future<void> _saveRideStartedToPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingData = prefs.getString('active_driver_ride_data');
      
      if (existingData != null) {
        final rideData = jsonDecode(existingData);
        
        // Başlatma bilgilerini ekle
        rideData['is_ride_started'] = true;
        rideData['ride_start_time'] = _rideStartTime?.toIso8601String();
        rideData['status'] = 'in_progress'; // Durum değiştir
        rideData['updated_at'] = DateTime.now().toIso8601String();
        
        await prefs.setString('active_driver_ride_data', jsonEncode(rideData));
        
        print('✅ ŞOFÖR: Başlatma durumu persistence a kaydedildi');
      }
    } catch (e) {
      print('❌ ŞOFÖR: Başlatma persistence hatası: $e');
    }
  }
  
  // MÜŞTERİYİ BİLGİLENDİR - YOLCULUK BAŞLADI!
  Future<void> _notifyCustomerRideStarted() async {
    try {
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      final prefs = await SharedPreferences.getInstance();
      final driverId = int.tryParse(prefs.getString('driver_id') ?? '0') ?? 0;

      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/notify_ride_started.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': int.tryParse(rideId) ?? 0,
          'driver_id': driverId,
          'status': 'in_progress',
          'started_at': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ ŞOFÖR: Müşteri yolculuk başlatma bildirimi gönderildi');
        }
      }
    } catch (e) {
      print('❌ ŞOFÖR: Müşteri bildirim hatası: $e');
    }
  }
  
  // PERSİSTENCE'DAN BAŞLATMA DURUMUNU KURTAR - GÜÇLENDİRİLMİŞ!
  Future<void> _restoreRideStartedFromPersistence() async {
    try {
      print('🔄 ŞOFÖR: Başlatma durumu restore başlıyor...');
      
      final prefs = await SharedPreferences.getInstance();
      final existingData = prefs.getString('active_driver_ride_data');
      
      print('🔍 ŞOFÖR: Persistence data: ${existingData != null ? "VAR" : "YOK"}');
      
    // RESTORE DEĞERLERİ
    bool isStarted = false;
    String? startTimeStr;
    int waitingMinutes = 0;
    bool isWaitingActive = false;
    double? restoredTotalPrice;
      
      if (existingData != null) {
        final rideData = jsonDecode(existingData);
        
        isStarted = rideData['is_ride_started'] ?? false;
        startTimeStr = rideData['ride_start_time'];
        waitingMinutes = rideData['waiting_minutes'] ?? 0;
      isWaitingActive = rideData['is_waiting_active'] ?? false;
      
      // KRİTİK: Backend'den gelen bekleme süresini de kullan (arka planda geçen süre için!)
      final backendWaiting = widget.rideDetails['waiting_minutes'];
      if (backendWaiting != null) {
        final backendWaitingInt = int.tryParse(backendWaiting.toString()) ?? 0;
        if (backendWaitingInt > waitingMinutes) {
          print('🔄 ŞOFÖR: Backend\'den daha güncel bekleme süresi: $waitingMinutes → $backendWaitingInt dk');
          waitingMinutes = backendWaitingInt;
        }
      }
      if (rideData.containsKey('calculated_price') && rideData['calculated_price'] != null) {
        restoredTotalPrice = double.tryParse(rideData['calculated_price'].toString());
      }
        
        print('🔍 ŞOFÖR: Persistence restore değerleri:');
        print('   🚗 is_ride_started: $isStarted');
        print('   ⏰ ride_start_time: $startTimeStr'); 
        print('   ⏳ waiting_minutes: $waitingMinutes');
        print('   ⏸️ is_waiting_active: $isWaitingActive');
      }
      
      // WIDGET.RIDEDETAILS FALLBACK - PERSISTENCE YOK AMA YOLCULUK BAŞLAMIŞ!
      if (!isStarted && widget.rideDetails['is_ride_started'] != null) {
        isStarted = widget.rideDetails['is_ride_started'] == true || widget.rideDetails['is_ride_started'] == 'true';
        print('🔄 ŞOFÖR: widget.rideDetails\'den is_ride_started restore edildi: $isStarted');
      }
      
      if (startTimeStr == null && widget.rideDetails['ride_start_time'] != null) {
        startTimeStr = widget.rideDetails['ride_start_time'].toString();
        print('🔄 ŞOFÖR: widget.rideDetails\'den ride_start_time restore edildi: $startTimeStr');
      }
      
      if (waitingMinutes == 0 && widget.rideDetails['waiting_minutes'] != null) {
        waitingMinutes = int.tryParse(widget.rideDetails['waiting_minutes'].toString()) ?? 0;
        print('🔄 ŞOFÖR: widget.rideDetails\'den waiting_minutes restore edildi: $waitingMinutes');
      }
      
      if (!isWaitingActive && widget.rideDetails['is_waiting_active'] != null) {
        isWaitingActive = widget.rideDetails['is_waiting_active'] == true || widget.rideDetails['is_waiting_active'] == 'true';
        print('🔄 ŞOFÖR: widget.rideDetails\'den is_waiting_active restore edildi: $isWaitingActive');
      }

    if (restoredTotalPrice == null && widget.rideDetails['calculated_price'] != null) {
      restoredTotalPrice = double.tryParse(widget.rideDetails['calculated_price'].toString());
      print('🔄 ŞOFÖR: widget.rideDetails\'den calculated_price restore edildi: $restoredTotalPrice');
    }

    restoredTotalPrice ??= double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0');
      
      // STATUS KONTROLÜ - SON FALLBACK!
      final currentStatus = widget.rideDetails['status'] ?? 'accepted';
      if (!isStarted && currentStatus == 'in_progress') {
        isStarted = true;
        if (startTimeStr == null) {
          startTimeStr = DateTime.now().toIso8601String();
        }
        print('🔄 ŞOFÖR: Status in_progress, is_ride_started otomatik true yapıldı');
      }
      
      setState(() {
        _isRideStarted = isStarted;
        _rideStartTime = startTimeStr != null ? DateTime.tryParse(startTimeStr) : null;
        _waitingMinutes = waitingMinutes;
        _isWaitingActive = isWaitingActive;
      if (restoredTotalPrice != null) {
        _calculatedTotalPrice = restoredTotalPrice!;
        widget.rideDetails['calculated_price'] = restoredTotalPrice;
      }
      });
      
      print('✅ ŞOFÖR: Tüm durumlar RESTORE EDİLDİ!');
      print('   🚗 Yolculuk başlatıldı mı: $_isRideStarted');
      print('   ⏰ Başlatma zamanı: $_rideStartTime');
      print('   ⏳ Bekleme süresi: $_waitingMinutes dakika');
      print('   ⏸️ Bekleme timer aktif: $_isWaitingActive');
      
      // KRİTİK: RESTORE EDİLEN BEKLEME SÜRESİNİ KORU!
      final restoredWaitingMinutes = _waitingMinutes;
      final restoredIsWaitingActive = _isWaitingActive;
      
      // UI güncelle - Bu çağrı artık restore edilen değerleri kullanacak
      _calculateEarnings();
      
      // BEKLEME VERİLERİNİ GERİ YAZ - _calculateEarnings() ASLA DEĞİŞTİRMESİN!
      setState(() {
        _waitingMinutes = restoredWaitingMinutes;
        _isWaitingActive = restoredIsWaitingActive;
      });
      print('🔄 ŞOFÖR: Bekleme restore korundu: $_waitingMinutes dk, Active: $_isWaitingActive');
      
      // MANUEL TIMER KALDIRILDI - Backend TIMESTAMPDIFF ile otomatik sayıyor!
      // Bekleme süresi backend'den check_driver_active_ride.php'den gelecek
      print('✅ ŞOFÖR: Backend otomatik bekleme sistemi aktif (TIMESTAMPDIFF)');
      
      // Yolculuk başlamışsa süreyi hesapla ve göster
      if (_isRideStarted && _rideStartTime != null) {
        final elapsed = DateTime.now().difference(_rideStartTime!);
        print('⏱️ ŞOFÖR: Yolculuk süresi: ${elapsed.inMinutes} dakika');
      }

      if (_isRideStarted) {
        unawaited(_sendRealTimeDataToCustomer());
      }
    } catch (e) {
      print('❌ ŞOFÖR: Persistence restore hatası: $e');
    }
  }
  
  // REAL-TIME DATA MÜŞTERİYE AKTARIM SİSTEMİ!
  Future<void> _sendRealTimeDataToCustomer() async {
    try {
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      
      final pickupLat = double.tryParse(widget.rideDetails['pickup_lat']?.toString() ?? '') ??
          double.tryParse(widget.rideDetails['pickup_latitude']?.toString() ?? '') ??
          0.0;
      final pickupLng = double.tryParse(widget.rideDetails['pickup_lng']?.toString() ?? '') ??
          double.tryParse(widget.rideDetails['pickup_longitude']?.toString() ?? '') ??
          0.0;

      final destLat = double.tryParse(widget.rideDetails['destination_lat']?.toString() ?? '') ??
          double.tryParse(widget.rideDetails['destination_latitude']?.toString() ?? '') ??
          0.0;
      final destLng = double.tryParse(widget.rideDetails['destination_lng']?.toString() ?? '') ??
          double.tryParse(widget.rideDetails['destination_longitude']?.toString() ?? '') ??
          0.0;

      final driverLat = _driverLocation?.latitude ?? pickupLat;
      final driverLng = _driverLocation?.longitude ?? pickupLng;

      final backendKm = double.tryParse(_currentRideStatus['current_km']?.toString() ?? 
                                        widget.rideDetails['current_km']?.toString() ?? '0') ?? 0.0;
      
      double currentKm = backendKm;
      
      if (pickupLat != 0.0 && pickupLng != 0.0 && destLat != 0.0 && destLng != 0.0) {
        final totalDistance = _calculateDistanceMeters(pickupLat, pickupLng, destLat, destLng) / 1000.0;
        final travelledDistance = _calculateDistanceMeters(pickupLat, pickupLng, driverLat, driverLng) / 1000.0;
        final calculatedKm = travelledDistance.clamp(0.0, totalDistance);
        
        if (calculatedKm > backendKm) {
          currentKm = calculatedKm;
          print('✅ KM ARTIŞI: Backend=$backendKm → Yeni=$currentKm');
        } else {
          print('🔒 KM KORUMA: Backend=$backendKm korundu (Hesaplanan=$calculatedKm)');
        }
      }
      
        final currentPriceValue = _calculatedTotalPrice > 0
            ? _calculatedTotalPrice
            : double.tryParse((widget.rideDetails['calculated_price'] ?? _currentRideStatus['calculated_price'] ?? widget.rideDetails['estimated_price'] ?? 0).toString()) ?? 0.0;
        final driverNetValue = (_estimatedEarnings + _waitingFee).clamp(0, double.infinity);

        print('📤 ŞOFÖR: Real-time data gönderiliyor - Ride: $rideId, Bekleme: $_waitingMinutes dk (Active: $_isWaitingActive), KM: ${currentKm.toStringAsFixed(1)} (Backend: $backendKm)');
        
        final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_ride_realtime_data.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': int.tryParse(rideId) ?? 0,
          'current_km': currentKm.toStringAsFixed(1),
          'waiting_minutes': _waitingMinutes,
          // waiting_started SİLİNDİ! Her 5sn gönderince backend sıfırlıyor!
          // Sadece BAŞLAT/DURDUR butonlarında gönderilecek!
          'driver_lat': _driverLocation?.latitude ?? 0.0,
          'driver_lng': _driverLocation?.longitude ?? 0.0,
            'current_price': currentPriceValue.toStringAsFixed(2),
            'driver_net': driverNetValue.toStringAsFixed(2),
          'updated_at': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📥 ŞOFÖR: Real-time data API yanıtı: ${response.body}');
        if (data['success'] == true) {
          print('✅ ŞOFÖR: Real-time data BAŞARIYLA gönderildi - KM: ${currentKm.toStringAsFixed(1)}, Bekleme: $_waitingMinutes dk');
        } else {
          print('❌ ŞOFÖR: Real-time data API success=false: ${data['message']}');
        }
      } else {
        print('❌ ŞOFÖR: Real-time data HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ŞOFÖR: Real-time data gönderim hatası: $e');
      // Hata olsa bile devam et - kritik değil
    }
  }
  
  // YOLCULUK SONLANDIRMA ONAYI!
  Future<void> _showCompleteRideConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Yolculuğu Sonlandır', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Müşteriyi hedefe ulaştırdınız mı? Yolculuğu sonlandırmak istediğinize emin misiniz?',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '✅ Müşteri ödeme sayfasına yönlendirilecek',
              style: TextStyle(color: Colors.green, fontSize: 14),
            ),
            SizedBox(height: 8),
            Text(
              '💰 Kazancınız hesaplanarak kaydedilecek',
              style: TextStyle(color: Colors.orange, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text('Sonlandır', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _completeRide();
    }
  }
  
  // YOLCULUK SONLANDIRMA İŞLEMİ
  Future<void> _completeRide() async {
    try {
      print('🏁 ŞOFÖR: Yolculuk sonlandırılıyor...');
      print('📊 RIDE DETAILS: ${widget.rideDetails}');
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          backgroundColor: Color(0xFF1A1A2E),
          content: Row(
            children: [
              CircularProgressIndicator(color: Color(0xFFFFD700)),
              SizedBox(width: 20),
              Text('Yolculuk sonlandırılıyor...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      print('🆔 ŞOFÖR: Ride ID: $rideId');
      
      final totalKm = _calculateDistanceMeters(
            double.tryParse(widget.rideDetails['pickup_lat']?.toString() ?? '') ??
                double.tryParse(widget.rideDetails['pickup_latitude']?.toString() ?? '') ??
                0.0,
            double.tryParse(widget.rideDetails['pickup_lng']?.toString() ?? '') ??
                double.tryParse(widget.rideDetails['pickup_longitude']?.toString() ?? '') ??
                0.0,
            double.tryParse(widget.rideDetails['destination_lat']?.toString() ?? '') ??
                double.tryParse(widget.rideDetails['destination_latitude']?.toString() ?? '') ??
                0.0,
            double.tryParse(widget.rideDetails['destination_lng']?.toString() ?? '') ??
                double.tryParse(widget.rideDetails['destination_longitude']?.toString() ?? '') ??
                0.0,
          ) /
          1000.0;
      
      print('📏 ŞOFÖR: Total KM: $totalKm');
      print('⏰ ŞOFÖR: Waiting Minutes: $_waitingMinutes');
      
      // ✅ KRİTİK FIX: Backend'e BRÜT fiyat gönder (komisyon öncesi)!
      // 🚨 KRİTİK FIX: Backend'e TOPLAM FİYAT GÖNDER (BEKLEME DAHİL!)
      final totalEarningsToSend = _calculatedTotalPrice > 0 ? _calculatedTotalPrice : (double.tryParse(widget.rideDetails['estimated_price']?.toString() ?? '0') ?? 0.0);
      
      print('💰 ŞOFÖR: Total Earnings (BRÜT - BEKLEME DAHİL): $totalEarningsToSend (_calculatedTotalPrice: $_calculatedTotalPrice)');
      print('🌐 ŞOFÖR: completeRide API çağrısı başlıyor...');

      final completionData = await RideService.completeRide(
        rideId: int.tryParse(rideId) ?? 0,
        totalKm: totalKm,
        waitingMinutes: _waitingMinutes,
        totalEarnings: totalEarningsToSend, // ✅ BRÜT fiyat (komisyon öncesi)
        dropoffLat: _driverLocation?.latitude, // ✅ BIRAKILAN KONUM
        dropoffLng: _driverLocation?.longitude, // ✅ BIRAKILAN KONUM
      );
      
      print('📦 ŞOFÖR: completeRide yanıtı: $completionData');

      print('✅ ŞOFÖR: API çağrısı tamamlandı, dialog kapatılıyor...');

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Loading dialog'u kapat
      }

      if (completionData != null) {
        print('✅ ŞOFÖR: Completion data mevcut, işleniyor...');
        final finalPrice = double.tryParse(completionData['final_price']?.toString() ?? '0') ?? 0.0;
        final driverNet = double.tryParse(completionData['driver_net']?.toString() ?? '0') ?? _estimatedEarnings;
        final completionWaiting = completionData['waiting_minutes'] is int
            ? completionData['waiting_minutes'] as int
            : int.tryParse(completionData['waiting_minutes']?.toString() ?? '') ?? _waitingMinutes;
        final completionKm = double.tryParse(completionData['total_km']?.toString() ?? '0') ?? 0.0;

        setState(() {
          _waitingMinutes = completionWaiting;
          _currentRideStatus['calculated_price'] = finalPrice;
          _currentRideStatus['final_price'] = finalPrice;
          _currentRideStatus['driver_net'] = driverNet;
          _currentRideStatus['total_km'] = completionKm;
          _estimatedEarnings = driverNet;
          _waitingFee = math.max(0, finalPrice - driverNet);
          _calculatedTotalPrice = finalPrice;
        });

        // YOLCULUK BİTTİ - PERSİSTENCE TEMİZLE! (KAYDETME!)
        await RidePersistenceService.clearActiveRide();
        print('🗑️ [ŞOFÖR] Persistence tamamen temizlendi - yeni talep aranabilir!');

        // DriverRideProvider'daki aktif yolculuğu temizle - POLLING YENİDEN BAŞLASIN!
        try {
          final driverRideProvider = Provider.of<DriverRideProvider>(context, listen: false);
          await driverRideProvider.completeRide(rideId, finalPrice);
          print('✅ [ŞOFÖR] DriverRideProvider aktif yolculuk temizlendi - polling yeniden başlayacak!');
        } catch (e) {
          print('⚠️ [ŞOFÖR] Provider temizleme hatası: $e');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('🏁 Yolculuk tamamlandı! Müşteri ödeme yapacak.'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        
        // Ana sayfaya dön - GÜÇLENDİRİLMİŞ NAVİGASYON
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          _showPaymentAndRatingFlow(completionData);
        }
        
        return;
      }
      throw Exception('Yolculuk tamamlanamadı');
      
    } catch (e) {
      print('❌ ŞOFÖR: Yolculuk sonlandırma hatası: $e');
      
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Loading dialog'u kapat
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Sonlandırma hatası: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  Future<void> _showPaymentAndRatingFlow(Map<String, dynamic> completionData) async {
    final totalAmount = double.tryParse(completionData['final_price']?.toString() ?? '0') ??
        (_calculatedTotalPrice > 0 ? _calculatedTotalPrice : (_estimatedEarnings + _waitingFee));
    final driverNet = double.tryParse(completionData['driver_net']?.toString() ?? '0') ?? _estimatedEarnings;
    final customerName = widget.rideDetails['customer_name'] ?? 'Müşteri';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ödeme Onayı', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Müşteri: $customerName', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Text('Toplam Tutar: ₺${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Sürücü Payı: ₺${driverNet.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam', style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Müşteri puanlamasını tetikle - KULLANICI İSTEĞİ İLE İPTAL EDİLDİ
    // RatingDialog.show(
    //   context,
    //   rideId: widget.rideDetails['ride_id']?.toString() ?? '0',
    //   driverId: widget.rideDetails['driver_id']?.toString() ?? '',
    //   customerId: widget.rideDetails['customer_id']?.toString() ?? '',
    //   driverName: widget.rideDetails['driver_name'] ?? 'Vale',
    // );
  }
  
  // KÖPRÜ SİSTEMİ - PANELDEN DESTEK TELEFONU ÇEK! ✅
  Future<void> _startBridgeCall() async {
    try {
      print('📞 [ŞOFÖR] Köprü sistemi başlatılıyor...');
      
      // Panel'den destek telefonu çek
      final supportPhone = await _getSupportPhoneFromPanel();
      
      if (supportPhone == null || supportPhone.isEmpty) {
        throw Exception('Destek telefonu alınamadı');
      }
      
      print('📞 [ŞOFÖR] Destek telefonu alındı: $supportPhone');
      
      // Köprü sistemi parametreleri
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      final customerId = widget.rideDetails['customer_id']?.toString() ?? '0';
      final customerPhone = widget.rideDetails['customer_phone'] ?? '';
      
      // Destek hattını ara (köprü sistemi)
      await _executePhoneCall(
        supportPhone,
        onDial: () => print('Köprü arandı'),
      );
      
    } catch (e) {
      print('❌ [ŞOFÖR] Köprü sistemi hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Arama hatası: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  // PANEL'DEN DESTEK TELEFONU ÇEK
  Future<String?> _getSupportPhoneFromPanel() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_support_phone.php'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['phone'] != null) {
          return data['phone'].toString();
        }
      }
      
      // Fallback numara
      return '+90 850 460 78 46';
    } catch (e) {
      print('❌ [ŞOFÖR] Destek telefonu alma hatası: $e');
      return '+90 850 460 78 46'; // Fallback
    }
  }
  
  // TELEFON ÇAĞRISI YAP - GÜÇLENDİRİLMİŞ
  Future<void> _executePhoneCall(
    String phoneNumber, {
    String? fallback,
    VoidCallback? onDial,
  }) async {
    try {
      if (phoneNumber.isEmpty) {
        throw Exception('Telefon numarası boş');
      }

      final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      final Uri phoneUri = Uri(scheme: 'tel', path: cleanPhone);

      if (await canLaunchUrl(phoneUri)) {
        print('📞 [ŞOFÖR] Telefon araması → $cleanPhone');
        onDial?.call();
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
        return;
      }

      if (fallback != null && fallback.isNotEmpty) {
        final fallbackClean = fallback.replaceAll(RegExp(r'[^\d+]'), '');
        final Uri fallbackUri = Uri(scheme: 'tel', path: fallbackClean);
        if (await canLaunchUrl(fallbackUri)) {
          print('📞 [ŞOFÖR] Telefon fallback → $fallbackClean');
          onDial?.call();
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      throw Exception('Hiçbir arama uygulaması açılamadı');
    } catch (e) {
      print('❌ [ŞOFÖR] Telefon çağrısı hatası: $e');
      try {
        final cleanPhone = (fallback ?? phoneNumber).replaceAll(RegExp(r'[^\d+]'), '');
        final Uri alternativeUri = Uri.parse('tel:$cleanPhone');
        print('📞 [ŞOFÖR] Alternatif deneme → $cleanPhone');
        await launchUrl(alternativeUri, mode: LaunchMode.externalApplication);
      } catch (altError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Arama yapılamadı: $phoneNumber\nHata: $altError'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _logBridgeInfo(String phone, {String? bridgeCode, String? customerPhone}) {
    print('🌉 [ŞOFÖR] Köprü bilgisi → Telefon: $phone | Köprü kodu: ${bridgeCode ?? '-'} | Müşteri: ${customerPhone ?? '-'}');
  }
  
  void _openMessaging() {
    print('💬 ŞOFÖR Gerçek mesaj sistemi açılıyor...');
    
    // Ride ID'yi farklı alanlardan dene
    final rideId = widget.rideDetails['ride_id']?.toString() ?? 
                   widget.rideDetails['id']?.toString() ?? 
                   '0';
    final customerName = widget.rideDetails['customer_name'] ?? 'Müşteri';
    
    print('📋 ŞOFÖR: Mesaj ekranına gidiliyor - Ride ID: $rideId, Müşteri: $customerName');
    
    if (rideId == '0') {
      print('❌ ŞOFÖR: Geçersiz Ride ID - mesaj ekranı açılamıyor');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Mesajlaşma için yolculuk ID bulunamadı'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RideChatScreen(
          rideId: rideId,
          customerName: customerName,
          isDriver: true, // ŞOFÖR OLARAK GİRİYOR
        ),
      ),
    );
  }
  
  Future<void> _callCustomer() async {
    final phone = widget.rideDetails['customer_phone'] ?? '';
    print('📞 [ŞOFÖR] Müşteri araması: $phone');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📞 $phone aranıyor...'),
        backgroundColor: Colors.green,
      ),
    );
  }
  

  Future<void> _launchNavigationApp(Uri uri, {Uri? fallback}) async {
    try {
      if (await canLaunchUrl(uri)) {
        print('🧭 [ŞOFÖR] Navigasyon açılıyor → $uri');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (fallback != null && await canLaunchUrl(fallback)) {
        print('🧭 [ŞOFÖR] Navigasyon fallback → $fallback');
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
        return;
      }
      throw Exception('Uygulama bulunamadı');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Navigasyon açılamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  Future<void> _markDriverArrived() async {
    // Şoför geldi durumu
    print('📍 [ŞOFÖR] Müşteri yanına vardı');
  }
  
  Future<void> _startRide() async {
    final rideId = int.tryParse(widget.rideDetails['ride_id']?.toString() ?? '0') ?? 0;

    if (_isRideStarted) {
      print('⚠️ [ŞOFÖR] Yolculuk ZATEN BAŞLAMIŞ - Duplicate başlatma engellendi!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ℹ️ Yolculuk zaten başlatılmış durumda'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (rideId == 0) {
      print('❌ [ŞOFÖR] Geçersiz ride ID');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Geçersiz yolculuk bilgisi'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final driverId = int.tryParse(prefs.getString('driver_id') ?? '0') ?? 0;

    print('🚗 [ŞOFÖR] Yolculuk başlatma isteği gönderiliyor - ride:$rideId driver:$driverId');

    final success = await RideService.startRide(rideId, driverId);
    if (!success) {
      print('❌ [ŞOFÖR] API başarısız - yolculuk başlatılamadı');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Yolculuk başlatılamadı, lütfen tekrar deneyin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('✅ [ŞOFÖR] API başarılı - durum güncelleniyor');

    setState(() {
      _isRideStarted = true;
      _rideStartTime = DateTime.now();
      widget.rideDetails['status'] = 'in_progress';
    });

    print('💾 [ŞOFÖR] Persistence kaydediliyor...');
    await _saveRideStartedToPersistence();
    await _notifyCustomerRideStarted();
    _calculateEarnings();
    _saveToPersistence(); // BAŞLATMA DURUMUNU HEMEN KAYDET!

    print('✅ [ŞOFÖR] Yolculuk başlatma işlemi TAMAMLANDI!');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚗 Yolculuk başarıyla başlatıldı'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    await _updateRideStatus();
  }
  
  // ESKİ _completeRide kaldırıldı - YENİ VERSİYON KULLANILIYOR
  
  // OTOMATİK MÜŞTERİ KÖPRÜ SİSTEMİ - DİREKT BAĞLAMA! ✅
  // ✅ NETGSM KÖPRÜ ARAMA SİSTEMİ - ŞOFÖR! 🔥
  Future<void> _callCustomerDirectly() async {
    final customerName = _currentRideStatus['customer_name'] ?? widget.rideDetails['customer_name'] ?? 'Müşteri';
    
    // ✅ Müşteri telefonu - tüm kaynaklardan dene!
    String customerPhone = _currentRideStatus['customer_phone'] ?? widget.rideDetails['customer_phone'] ?? '';
    
    // Eğer hala boşsa, backend'den çek!
    if (customerPhone.isEmpty) {
      print('⚠️ [ŞOFÖR] Müşteri telefonu boş - backend\'den çekiliyor...');
      await _loadCustomerDetails();
      customerPhone = _currentRideStatus['customer_phone'] ?? widget.rideDetails['customer_phone'] ?? '';
    }
    
    // rideId int'e parse et!
    final rideIdRaw = widget.rideDetails['ride_id'] ?? 0;
    final rideId = rideIdRaw is int ? rideIdRaw : int.tryParse(rideIdRaw.toString()) ?? 0;
    
    print('📋 [ŞOFÖR] Arama bilgileri: Ride=$rideId, Müşteri telefon=$customerPhone');
    
    // ✅ Müşteri telefonu kontrolü!
    if (customerPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('❌ Müşteri telefon numarası bulunamadı'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    
    // Köprü hattı numarası (SABİT!)
    const bridgeNumber = '0216 606 45 10';
    
    print('📞 [ŞOFÖR] Köprü arama başlatılıyor - Müşteri: $customerName');
    
    // Bilgilendirme ve onay dialogu
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('🔒 Güvenli Köprü Arama', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_in_talk, color: Color(0xFFFFD700), size: 60),
            const SizedBox(height: 16),
            const Text(
              'Köprü hattımız sizi müşterinizle güvenli bir şekilde bağlayacaktır.',
              style: TextStyle(color: Colors.white, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                children: [
                  const Text(
                    '📞 Köprü Hattı',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    bridgeNumber,
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '👤 Bağlanacak: $customerName',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              '🔐 Gizlilik: İki taraf da sadece köprü numarasını görür',
              style: TextStyle(color: Colors.green, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _initiateBridgeCallToCustomer(rideId, customerPhone, customerName);
            },
            icon: const Icon(Icons.phone, color: Colors.white),
            label: const Text('Aramayı Başlat', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
  
  // ✅ KÖPRÜ ARAMASI BAŞLAT - BACKEND ÜZERİNDEN!
  Future<void> _initiateBridgeCallToCustomer(int rideId, String customerPhone, String customerName) async {
    try {
      // Şoför numarasını al
      final prefs = await SharedPreferences.getInstance();
      final driverPhone = prefs.getString('user_phone') ?? prefs.getString('driver_phone') ?? '';
      
      if (driverPhone.isEmpty) {
        throw Exception('Şoför telefon numarası bulunamadı');
      }
      
      print('📤 Backend köprü API çağrılıyor...');
      print('   Ride ID: $rideId');
      print('   🟢 ARAYAN (caller): Şoför = $driverPhone');
      print('   🔵 ARANAN (called): Müşteri = $customerPhone');
      
      // Backend'e istek at (NetGSM API credentials gizli!)
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/bridge_call.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'caller': driverPhone,        // ✅ Arayan: Şoför!
          'called': customerPhone,      // ✅ Aranan: Müşteri!
        }),
      ).timeout(const Duration(seconds: 15));
      
      print('📥 Bridge Call Response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          // BAŞARILI - Köprü numarasını ara!
          final bridgeNumber = data['bridge_number'] ?? '02166064510';
          
          print('✅ Köprü arama başarılı - Numara: $bridgeNumber');
          
          // Telefon uygulamasını aç
          final uri = Uri(scheme: 'tel', path: bridgeNumber);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
            
            // Başarı mesajı
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.phone_forwarded, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('📞 Köprü hattı $customerName ile bağlantı kuruyor...'),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            throw Exception('Telefon uygulaması açılamadı');
          }
          
        } else {
          throw Exception(data['message'] ?? 'Köprü arama başlatılamadı');
        }
      } else {
        throw Exception('Backend hatası: ${response.statusCode}');
      }
      
    } catch (e) {
      print('❌ Köprü arama hatası: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('❌ Arama hatası: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  void _executeBridgeCall(String companyPhone, String? bridgeCode) {
    print('📞 [ŞOFÖR] Otomatik köprü çağrısı başlatılıyor...');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.phone_in_talk, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '📞 Otomatik müşteri bağlantısı başlatılıyor...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Sistem müşterinizi arayıp size bağlayacak',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
    
    _executePhoneCall(
      companyPhone,
      onDial: () => _logBridgeInfo(
        companyPhone,
        bridgeCode: bridgeCode,
        customerPhone: widget.rideDetails['customer_phone']?.toString(),
      ),
    );
  }
  
  void _makeDirectCustomerCall() {
    final customerPhone = widget.rideDetails['customer_phone'] ?? '';
    print('📞 [ŞOFÖR] Direkt müşteri araması: $customerPhone');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📞 Müşteriniz ${widget.rideDetails['customer_name']} aranıyor...'),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    _executePhoneCall(customerPhone);
  }
  
  Future<String> _getDriverPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_phone') ?? widget.rideDetails['driver_phone'] ?? '';
  }
  
  void _makeDriverCall(String phone, String title) {
    print('📞 [ŞOFÖR] Arama: $title - $phone');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📞 $title aranıyor... Ride #${widget.rideDetails['ride_id']}'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    _executePhoneCall(phone);
  }

  // ŞOFÖR ARAMA SEÇENEKLERİ - EKSİK OLAN! ✅
  void _showDriverCallOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A2A3E), Color(0xFF1A1A2E)],
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '📞 Arama Seçenekleri',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Müşteri arama
            // Müşteri arama seçeneği
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _makeDriverCall(widget.rideDetails['customer_phone'] ?? '', 
                                   '👤 ${widget.rideDetails['customer_name'] ?? 'Müşteri'}');
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.green, Colors.teal]),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone, color: Colors.white, size: 24),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '👤 ${widget.rideDetails['customer_name'] ?? 'Müşteri'}',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const Text(
                                'Direkt müşteriyle iletişim',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const Text(
                                'Güvenli köprü sistemi',
                                style: TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Şirket merkezi arama seçeneği  
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _makeDriverCall('+90 555 123 45 67', '🏢 FunBreak Vale Merkezi');
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.business, color: Colors.white, size: 24),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🏢 FunBreak Vale Merkezi',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Şoför operasyon hattı',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              Text(
                                '+90 555 123 45 67',
                                style: TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Acil durum arama seçeneği
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _makeDriverCall('+90 555 123 45 67', '🚨 Acil Durum');
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.red, Colors.redAccent]),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.white, size: 24),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🚨 Acil Durum Hattı',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '7/24 acil destek',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              Text(
                                '+90 555 123 45 67',
                                style: TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // OBSERVER KALDIR!
    _pulseController.dispose();
    _slideController.dispose();
    _glowController.dispose();
    _trackingTimer?.cancel();
    // _waitingTimer?.cancel();  // MANUEL TIMER KALDIRILDI!
    
    // Persistence sadece tamamlanmışsa temizle
    final currentStatus = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? '';
    if (currentStatus == 'completed' || currentStatus == 'cancelled') {
      RidePersistenceService.clearActiveRide();
      print('🗑️ [ŞOFÖR] Yolculuk bitti - Persistence temizlendi');
    } else {
      print('💾 [ŞOFÖR] Yolculuk devam ediyor - Persistence korundu');
    }
    
    super.dispose();
  }
  
  // ARKA PLAN LIFECYCLE KONTROL - BEKLEME DEVAM ETSİN!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    print('📱 ŞOFÖR APP LIFECYCLE: $state');
    
    switch (state) {
      case AppLifecycleState.paused:
        print('⏸️ ŞOFÖR: Uygulama arka plana alındı - Bekleme devam ediyor...');
        // BEKLEME TİMER DEVAM ETSİN - DURDURMA!
        if (_isWaitingActive) {
          print('✅ ŞOFÖR: Bekleme timer aktif ve arka planda ÇALIŞIYOR!');
        }
        break;
        
      case AppLifecycleState.resumed:
        print('▶️ ŞOFÖR: Uygulama ön plana geldi - SADECE backend çek!');
        // SADECE BACKEND ÇEK - Persistence SİLİNDİ!
        unawaited(_updateRideStatus());
        break;
        
      case AppLifecycleState.inactive:
        print('💤 ŞOFÖR: Uygulama inactive durumda');
        break;
        
      case AppLifecycleState.detached:
        print('🔌 ŞOFÖR: Uygulama detached - kapanıyor...');
        break;
        
      case AppLifecycleState.hidden:
        print('👁️ ŞOFÖR: Uygulama hidden durumda');
        break;
    }
  }
  
  // ŞOFÖR MODERN ALT BAR! ✅
  Widget _buildDriverModernBottomBar() {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF0A0A0A),
          ],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Ana Sayfa Butonu (Yolculuk ekranı ana sayfa oldu)
            _buildDriverBottomBarItem(
              icon: Icons.home,
              label: 'Ana Sayfa',
              isActive: true, // Şoför yolculuk ekranı aktif ana sayfa
              onTap: () {
                print('🏠 [ŞOFÖR] Ana sayfa - Modern yolculuk ekranı zaten ana sayfa');
              },
            ),
            
            // Kazanç Butonu
            _buildDriverBottomBarItem(
              icon: Icons.currency_lira,
              label: 'Kazanç',
              isActive: false,
              onTap: () => _showEarningsDialog(),
            ),
            
            // Mesaj Butonu  
            _buildDriverBottomBarItem(
              icon: Icons.chat_bubble_outline,
              label: 'Mesajlar',
              isActive: false,
              onTap: () => _openMessaging(),
            ),
            
            // Telefon Butonu
            _buildDriverBottomBarItem(
              icon: Icons.phone,
              label: 'Ara',
              isActive: false,
              onTap: () => _startBridgeCall(), // KÖPRÜ SİSTEMİ!
            ),
            
            // Durum Butonu
            _buildDriverBottomBarItem(
              icon: Icons.info_outline,
              label: 'Durum',
              isActive: false,
              onTap: () => _showDriverStatusDialog(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDriverBottomBarItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isActive 
                ? const Color(0xFFFFD700).withOpacity(0.2)
                : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: isActive 
                ? Border.all(color: const Color(0xFFFFD700).withOpacity(0.5))
                : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: isActive ? _pulseAnimation.value : 1.0,
                  child: Icon(
                    icon,
                    color: isActive ? const Color(0xFFFFD700) : Colors.white70,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFFFFD700) : Colors.white70,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  void _showEarningsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Color(0xFFFFD700)),
            SizedBox(width: 12),
            Text(
              'Kazanç Bilgileri',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
                child: Column(
                  children: [
                    Text(
                      '₺${_calculatedTotalPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Tahmini Toplam Tutar',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    if ((_estimatedEarnings + _waitingFee) > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Net: ₺${(_estimatedEarnings + _waitingFee).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Tahmini Net Kazanç',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _getWaitingOrDurationDisplay(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _isHourlyPackageActive() ? 'Süre' : 'Bekleme Süresi',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_waitingFee > 0) 
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '₺${_waitingFee.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Bekleme Ücreti',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Kapat',
              style: TextStyle(color: Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showDriverStatusDialog() {
    final status = _currentRideStatus['status'] ?? widget.rideDetails['status'] ?? 'accepted';
    final statusInfo = _getDriverStatusInfo(status);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(statusInfo['icon'], color: statusInfo['colors'][0]),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Yolculuk Durumu',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: statusInfo['colors']),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusInfo['title'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusInfo['subtitle'],
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Müşteri: ${widget.rideDetails['customer_name'] ?? 'Bilgi yükleniyor...'}',
              style: const TextStyle(color: Colors.white70),
            ),
            const Text(
              'İletişim: Şirket hattı üzerinden güvenli arama',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              _isHourlyPackageActive() ? 'Süre: ${_getWaitingOrDurationDisplay()}' : 'Bekleme: $_waitingMinutes dakika',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Kapat',
              style: TextStyle(color: Color(0xFFFFD700)),
            ),
          ),
        ],
      ),
    );
  }
  
  // SCHEDULED TIME GÖSTER İM - SÜRÜCÜ AKTİF YOLCULUK EKRANINDA!
  String _getScheduledTimeDisplay() {
    try {
      final scheduledTime = widget.rideDetails['scheduled_time']?.toString();
      
      if (scheduledTime == null || 
          scheduledTime.isEmpty || 
          scheduledTime == 'null' || 
          scheduledTime == '0000-00-00 00:00:00') {
        return 'Hemen';
      }
      
      final scheduledDateTime = DateTime.tryParse(scheduledTime);
      if (scheduledDateTime == null) {
        return 'Hemen';
      }
      
      final now = DateTime.now();
      final difference = scheduledDateTime.difference(now);
      
      // Eğer gelecekte bir zaman ise saat göster
      if (difference.inMinutes > 15) {
        if (scheduledDateTime.day == now.day) {
          // Aynı gün - sadece saat:dakika
          return '${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
        } else {
          // Farklı gün - gün.ay saat:dakika
          return '${scheduledDateTime.day}.${scheduledDateTime.month} ${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
        }
      }
      
      return 'Hemen';
      
    } catch (e) {
      print('❌ Sürücü aktif ride scheduled time hatası: $e');
      return 'Hemen';
    }
  }

  // İPTAL KONTROLÜ - MÜŞTERİ İPTAL ETTİ Mİ?
  Future<void> _checkRideCancellation() async {
    try {
      final rideId = widget.rideDetails['ride_id']?.toString() ?? '0';
      print('🔍 ŞOFÖR: İptal kontrolü yapılıyor - Ride ID: $rideId');
      
      if (rideId == '0') {
        print('❌ ŞOFÖR: Geçersiz Ride ID - iptal kontrolü atlandı');
        return;
      }
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/check_ride_cancellation.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': int.tryParse(rideId) ?? 0,
        }),
      ).timeout(const Duration(seconds: 8));
      
      print('🌐 ŞOFÖR: İptal API yanıtı - Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📋 ŞOFÖR: İptal API data: ${data.toString()}');
        
        if (data['success'] == true && data['cancelled'] == true) {
          print('🚫 ŞOFÖR: MÜŞTERİ YOLCULUĞU İPTAL ETTİ! Timer durduruluyor...');
          _trackingTimer?.cancel();
          _showCancellationNotification();
        } else if (data['success'] == true && data['status'] == 'completed') {
          print('✅ ŞOFÖR: YOLCULUK TAMAMLANMIŞ! Ana sayfaya dönülüyor...');
          _trackingTimer?.cancel();
          if (mounted) {
            // Persistence temizle
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('active_driver_ride_data');
            await prefs.remove('driver_ride_state');
            print('🗑️ Yolculuk ekranı persistence temizlendi');
            
            // Ana sayfaya git (pop değil, pushReplacement - crash olmasın!)
            Navigator.of(context).popUntil((route) => route.isFirst);
            print('✅ Ana sayfaya dönüldü - Yolculuk tamamlandı!');
          }
        } else {
          print('✅ ŞOFÖR: Yolculuk aktif - iptal yok');
        }
      } else {
        print('❌ ŞOFÖR: İptal API HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ŞOFÖR: İptal kontrolü hatası: $e');
    }
  }
  
  // İPTAL BİLDİRİMİ GÖSTER - MODERN DESİGN!
  void _showCancellationNotification() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false, // Kapatmaya zorla
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        content: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // İptal ikonu - animasyonlu
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.red],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.cancel,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              
              const SizedBox(height: 20),
              
              const Text(
                '🚫 Rezervasyon İptal Edildi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              const Text(
                'Müşteri yolculuğu iptal etmiştir.\nAna sayfaya yönlendiriliyorsunuz.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          Container(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                // Persistence temizle
                await RidePersistenceService.clearActiveRide();
                
                // Ana sayfaya dön - GÜÇLENDİRİLMİŞ NAVİGASYON
                if (mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Ana Sayfaya Dön',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // metre

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }
  
  // NAVİGASYON FONKSİYONLARI - ADRESLERE TIKLANABİLİR!
  void _openNavigationToPickup() {
    final pickupLat = widget.rideDetails['pickup_lat'] ?? 41.0082;
    final pickupLng = widget.rideDetails['pickup_lng'] ?? 28.9784;
    final pickupAddress = widget.rideDetails['pickup_address'] ?? 'Alış konumu';
    
    print('🗺️ [ŞOFÖR] Pickup navigasyon açılıyor...');
    _openDirectNavigation(pickupLat, pickupLng, pickupAddress);
  }
  
  void _openNavigationToDestination() {
    final destLat = widget.rideDetails['destination_lat'] ?? 41.0082;
    final destLng = widget.rideDetails['destination_lng'] ?? 28.9784;
    final destAddress = widget.rideDetails['destination_address'] ?? 'Varış konumu';
    
    print('🗺️ [ŞOFÖR] Destination navigasyon açılıyor...');
    _openDirectNavigation(destLat, destLng, destAddress);
  }
  
  void _openDirectNavigation(double lat, double lng, String label) async {
    try {
      print('🗺️ [ŞOFÖR] Navigasyon seçim dialog açılıyor: lat=$lat lng=$lng label=$label');
      
      // Yandex Maps veya Google Maps seçim dialog'u
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('🗺️ Harita Uygulaması Seç'),
            content: const Text('Hangi harita uygulaması ile navigasyon başlatalım?'),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.map, color: Colors.red),
                label: const Text('Yandex Maps'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _openYandexMaps(lat, lng, label);
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.navigation, color: Colors.blue),
                label: const Text('Google Maps'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _openGoogleMaps(lat, lng, label);
                },
              ),
              TextButton(
                child: const Text('İptal'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('❌ [ŞOFÖR] Navigasyon hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Navigasyon açılamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 🗺️ YANDEX MAPS AÇMA
  Future<void> _openYandexMaps(double lat, double lng, String label) async {
    try {
      print('🗺️ [ŞOFÖR] Yandex Maps açılıyor: $label');
      
      // Yandex Maps deep link (iOS ve Android)
      final yandexUri = Uri.parse('yandexmaps://maps.yandex.com/?pt=$lng,$lat&z=16&l=map');
      final yandexWebFallback = Uri.parse('https://yandex.com/maps/?pt=$lng,$lat&z=16&l=map');
      
      if (await canLaunchUrl(yandexUri)) {
        await launchUrl(yandexUri, mode: LaunchMode.externalApplication);
        print('✅ [ŞOFÖR] Yandex Maps app açıldı');
      } else {
        await launchUrl(yandexWebFallback, mode: LaunchMode.externalApplication);
        print('✅ [ŞOFÖR] Yandex Maps web açıldı');
      }
    } catch (e) {
      print('❌ [ŞOFÖR] Yandex Maps hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Yandex Maps açılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // 🧭 GOOGLE MAPS AÇMA
  Future<void> _openGoogleMaps(double lat, double lng, String label) async {
    try {
      print('🗺️ [ŞOFÖR] Google Maps açılıyor: $label');
      
      // Google Maps deep link (iOS ve Android)
      final googleUri = Uri.parse('google.navigation:q=$lat,$lng');
      final googleWebFallback = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      
      if (await canLaunchUrl(googleUri)) {
        await launchUrl(googleUri, mode: LaunchMode.externalApplication);
        print('✅ [ŞOFÖR] Google Maps app açıldı');
      } else {
        await launchUrl(googleWebFallback, mode: LaunchMode.externalApplication);
        print('✅ [ŞOFÖR] Google Maps web açıldı');
      }
    } catch (e) {
      print('❌ [ŞOFÖR] Google Maps hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Google Maps açılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // ✅ KM GÖSTERİMİ
  String _getCurrentKm() {
    final currentKm = _currentRideStatus['current_km']?.toString() ?? 
                      widget.rideDetails['current_km']?.toString() ?? '0';
    final kmValue = double.tryParse(currentKm) ?? 0.0;
    return kmValue.toStringAsFixed(1);
  }
  
  // ✅ SAATLİK PAKET AKTİF Mİ KONTROL
  bool _isHourlyPackageActive() {
    final serviceType = widget.rideDetails['service_type']?.toString().toLowerCase() ?? 
                       _currentRideStatus['service_type']?.toString().toLowerCase() ?? '';
    return serviceType == 'hourly';
  }
  
  // ✅ SAATLİK PAKETTE SÜRE, NORMAL VALEDE BEKLEME
  String _getWaitingOrDurationDisplay() {
    if (_isHourlyPackageActive()) {
      // Saatlik pakette: "28 saat 43 dk" formatında
      final rideDurationHours = _currentRideStatus['ride_duration_hours'] ?? 
                                widget.rideDetails['ride_duration_hours'];
      
      if (rideDurationHours != null) {
        final totalHours = double.tryParse(rideDurationHours.toString()) ?? 0.0;
        final hours = totalHours.floor();
        final minutes = ((totalHours - hours) * 60).round();
        
        if (hours > 0 && minutes > 0) {
          return '$hours saat $minutes dk';
        } else if (hours > 0) {
          return '$hours saat';
        } else if (minutes > 0) {
          return '$minutes dk';
        }
      }
      return '0 saat';
    } else {
      // Normal vale: Bekleme dakikası
      return '$_waitingMinutes dk';
    }
  }
}
