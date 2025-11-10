import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // LOCAL NOTIFICATION!
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart'; // EKLENDİ!
import 'package:http/http.dart' as http; // AKILLI TALEP İÇİN!
import 'dart:convert'; // JSON İÇİN!
import 'services/session_service.dart';
import 'services/location_tracking_service.dart';
import 'services/dynamic_contact_service.dart';
import 'services/advanced_notification_service.dart'; // GELİŞMİŞ BİLDİRİM SERVİSİ!
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/admin_api_provider.dart'; // KRİTİK EKSİK - BİLDİRİMler İÇİN!
import 'providers/ride_provider.dart';
import 'providers/pricing_provider.dart';
import 'providers/driver_ride_provider.dart';
import 'providers/real_time_tracking_provider.dart';
import 'providers/waiting_time_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/driver_home_screen.dart';
import 'screens/services/services_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/permissions/permission_check_screen.dart';
// import 'screens/ride/active_ride_screen.dart'; // ESKİ - KALDIRILDI
import 'screens/ride/modern_active_ride_screen.dart'; // MODERN ELİT YOLCULUK EKRANI!
import 'screens/splash/persistence_aware_splash.dart'; // PERSİSTENCE KONTROLLÜ SPLASH!
import 'screens/auth/auth_wrapper.dart'; // AUTH WRAPPER!
import 'screens/main/persistence_aware_driver_main.dart'; // PERSİSTENCE AWARE ANA SAYFA!
import 'screens/main/main_screen.dart'; // NORMAL ANA SAYFA!
import 'services/ride_persistence_service.dart'; // PERSİSTENCE SERVİS!
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

// GLOBAL NAVIGATOR KEY - TALEP POPUP İÇİN!
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// GLOBAL DUPLICATE POPUP KONTROL!
final Set<String> _shownPopupRideIds = {};

bool _sharedPrefsBackgroundRegistered = false;

void _ensureBackgroundSharedPrefsRegistered() {
  if (_sharedPrefsBackgroundRegistered) {
    return;
  }

  try {
    if (Platform.isAndroid) {
      SharedPreferencesAndroid.registerWith();
      print('✅ [ŞOFÖR BACKGROUND] SharedPreferencesAndroid registerWith çağrıldı');
    } else if (Platform.isIOS || Platform.isMacOS) {
      SharedPreferencesFoundation.registerWith();
      print('✅ [ŞOFÖR BACKGROUND] SharedPreferencesFoundation registerWith çağrıldı');
    }
  } catch (e) {
    print('❌ [ŞOFÖR BACKGROUND] SharedPreferences registerWith hatası: $e');
  }

  _sharedPrefsBackgroundRegistered = true;
}

// BACKGROUND MESSAGE HANDLER - SÜRÜCÜ UYGULAMA KAPALI - ULTRA GÜÇLÜ!
@pragma('vm:entry-point')
Future<void> _driverFirebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  _ensureBackgroundSharedPrefsRegistered();

  try {
    // Firebase'i başlat - duplicate safe (iOS'te AppDelegate tarafından yapıldı)
    if (Platform.isAndroid) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
          print('🔥 Firebase background handler için başlatıldı (Android)');
      } else {
        print('🔥 Firebase zaten başlatılmış - background handler ready!');
      }
    } catch (e) {
      // Duplicate app hatası normalize - çalışmaya devam et
      if (e.toString().contains('duplicate-app')) {
        print('🔥 Firebase already initialized - background handler working!');
      } else {
        print('❌ Firebase background init error: $e');
        }
      }
    }
    
    print('🔔🔔🔔 BACKGROUND HANDLER TRIGGERED! 🔔🔔🔔');
    print('📱 === ŞOFÖR BACKGROUND BİLDİRİM ALINDI ===');
    print('   📋 Title: ${message.notification?.title}');
    print('   💬 Body: ${message.notification?.body}');
    print('   📊 Data: ${message.data}');
    print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
    print('   🌐 From: ${message.from ?? 'Unknown'}');
    print('   🆔 Message ID: ${message.messageId ?? 'No ID'}');
    print('   ⏰ Timestamp: ${DateTime.now()}');
    print('🔔 ŞOFÖR UYGULAMA KAPALI - System notification düştü!');
    print('🔔🔔🔔 BACKGROUND HANDLER WORKING! 🔔🔔🔔');
    
    // ⚠️ iOS APNs otomatik gösterir, Android manuel!
    if (Platform.isIOS) {
      print('📱 iOS background notification - APNs tarafından otomatik gösterildi');
      // iOS'te ek işlem gerekmez, APNs notification'ı gösterir
      // State güncelleme ve persistence işlemleri yapılabilir
    } else {
      // 🔥 ANDROID İÇİN DATA-ONLY notification oluştur!
    RemoteMessage finalMessage = message;
    if (message.notification == null && message.data.isNotEmpty) {
      print('   🔥 DATA-ONLY mesaj - notification oluşturuluyor...');
      final title = message.data['title'] ?? 'FunBreak Vale Şoför';
      final body = message.data['body'] ?? 'Yeni bildirim';
      
      finalMessage = RemoteMessage(
        senderId: message.senderId,
        category: message.category,
        collapseKey: message.collapseKey,
        contentAvailable: message.contentAvailable,
        data: message.data,
        from: message.from,
        messageId: message.messageId,
        messageType: message.messageType,
        mutableContent: message.mutableContent,
        notification: RemoteNotification(title: title, body: body),
        sentTime: message.sentTime,
        threadId: message.threadId,
        ttl: message.ttl,
      );
      print('   ✅ Notification eklendi: $title');
    }
    
      // 🔥 ANDROID AdvancedNotificationService kullan!
    try {
      await AdvancedNotificationService.showBackgroundNotification(finalMessage);
      print('✅ AdvancedNotificationService background bildirim gösterildi!');
    } catch (e) {
      print('⚠️ Background notification hatası: $e');
      }
    }
    
    print('✅ SÜRÜCÜ Background handler tamamlandı');

    try {
      // ÇEVRİMDIŞI KONTROLÜ - ÇEVRİMDIŞIYSA TALEP KAYDETME!
      final prefs = await SharedPreferences.getInstance();
      final isOnline = prefs.getBool('driver_is_online') ?? false;
      
      final type = message.data['type'] ?? message.data['notification_type'] ?? '';
      
      if (type == 'new_ride_request' || type == 'manual_assignment') {
        if (isOnline) {
          print('📦 [ŞOFÖR BACKGROUND] Çevrimiçi - Talep kaydediliyor...');
          await RidePersistenceService.savePendingRideRequest(message.data);
        } else {
          print('🔴 [ŞOFÖR BACKGROUND] ÇEVRİMDIŞI - Talep GÖRMEZDEN GELİNİYOR!');
        }
      } else if (type == 'ride_cancelled_by_customer' || type == 'requests_expired') {
        print('🗑️ [ŞOFÖR BACKGROUND] Talep iptal bildirimi - persistence temizleniyor');
        await RidePersistenceService.clearPendingRideRequest();
      } else if (type == 'ride_completed') {
        print('✅ [ŞOFÖR BACKGROUND] YOLCULUK TAMAMLANDI - Persistence temizleniyor!');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_driver_ride_data');
        await prefs.remove('driver_ride_state');
        await prefs.remove('current_ride_id');
        await RidePersistenceService.clearPendingRideRequest();
        print('✅ Tüm sürücü persistence temizlendi - Ana sayfaya dönecek!');
      }
    } catch (e) {
      print('❌ [ŞOFÖR BACKGROUND] Talep persistence hatası: $e');
    }
  } catch (e) {
    print('❌ SÜRÜCÜ Background handler hatası: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // KRİTİK: BACKGROUND HANDLER FIREBASE'DEN ÖNCE KAYDET!
  FirebaseMessaging.onBackgroundMessage(_driverFirebaseBackgroundHandler);
  print('BACKGROUND HANDLER MAIN DE KAYDEDILDI!');
  
  // ⚠️ Firebase initialization - Flutter plugin tüm platformlarda!
  try {
    if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
      print('✅ ŞOFÖR Firebase başlatıldı (${Platform.isAndroid ? "Android" : "iOS"})');
    } else {
      print('⚠️ ŞOFÖR Firebase zaten başlatılmış');
    }
  } catch (e) {
    print('⚠️ ŞOFÖR Firebase init hatası (duplicate normal): $e');
  }
  
  // GELİŞMİŞ SÜRÜCÜ BİLDİRİM SERVİSİ BAŞLAT!
  print('🔥 [ŞOFÖR] AdvancedNotificationService başlatılıyor...');
  try {
    await AdvancedNotificationService.initialize();
    print('✅ [ŞOFÖR] Gelişmiş bildirim sistemi başlatıldı');
  } catch (e, stack) {
    print('❌ [ŞOFÖR] AdvancedNotificationService HATASI: $e');
    print('📋 Stack: $stack');
  }
  
  await requestPermissions();
  
  // Session servisini başlat
  await SessionService.initializeSession();
  
  runApp(const MyApp());
}

// Basit ve hızlı izin sistemi
Future<void> requestPermissions() async {
  try {
    // SÜRÜCÜ İÇİN KRİTİK BILDIRIM İZINLERI (Platform-aware!)
    if (Platform.isAndroid) {
    final notificationStatus = await Permission.notification.request();
      print('📱 Android SÜRÜCÜ Bildirim izni: $notificationStatus');
    
    if (notificationStatus.isDenied) {
      print('❌ SÜRÜCÜ: Bildirim izni reddedildi - background bildirimler çalışmayacak!');
    } else {
      print('✅ SÜRÜCÜ: Bildirim izni verildi - background bildirimler çalışacak!');
    }
    } else if (Platform.isIOS) {
      // iOS'ta Firebase Messaging üzerinden izin istenir
      final fcmSettings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('📱 iOS SÜRÜCÜ Bildirim izni: ${fcmSettings.authorizationStatus}');
    }
    
    // PİL OPTİMİZASYONU BYPASS - SADECE ANDROID!
    if (Platform.isAndroid) {
    try {
      final batteryOptimization = await Permission.ignoreBatteryOptimizations.request();
        print('🔋 Android SÜRÜCÜ Pil optimizasyonu bypass: $batteryOptimization');
      
      if (batteryOptimization.isDenied) {
        print('⚠️ SÜRÜCÜ: Pil optimizasyonu bypass edilmedi - background bildirimler kısıtlanabilir!');
      } else {
        print('✅ SÜRÜCÜ: Pil optimizasyonu bypass edildi - background bildirimler güvende!');
      }
    } catch (e) {
      print('❌ Pil optimizasyonu kontrol hatası: $e');
      }
    } else if (Platform.isIOS) {
      print('📱 iOS: Arka planda yenileme Info.plist UIBackgroundModes var (programatik kontrol gerekmez)');
    }
    
    // Konum izni
    await Permission.location.request();
    await Permission.locationAlways.request();
    
    print('Izinler istendi');
  } catch (e) {
    print('Izin hatası: $e');
  }
}


class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);
  
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  DriverRideProvider? _driverRideProvider;
  final Set<String> _pollingNotifiedRideIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // İZİNLERİ ARKA PLANDA KONTROL ET - POPUP YOK! ✅
    _checkPermissionsInBackground();
    
    // ŞOFÖR UYGULAMASI PERSİSTENCE KONTROL! ✅
    _checkAndRestoreDriverActiveRide();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final provider = context.read<DriverRideProvider>();
        _driverRideProvider?.removeListener(_handleDriverRideUpdates);
        _driverRideProvider = provider;
        _driverRideProvider?.addListener(_handleDriverRideUpdates);
      } catch (e) {
        print('❌ [ŞOFÖR] DriverRideProvider dinleyicisi eklenemedi: $e');
      }
    });
  }

  @override
  void dispose() {
    _driverRideProvider?.removeListener(_handleDriverRideUpdates);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('🔔 [ŞOFÖR] App resumed - pending talep kontrol ediliyor');
      _restorePendingRideRequestPopup();
    }
  }
  
  Future<void> _checkAndRestoreDriverActiveRide() async {
    try {
      print('🔄 [ŞOFÖR] Ana uygulama - Aktif yolculuk kontrol ediliyor...');
      
      // KRİTİK: main.dart'ta aktif yolculuk kontrolü YAPMA!
      // driver_home_screen.dart zaten backend ile doğrulayıp açıyor!
      // Burada açarsak completed yolculuklar da açılır!
      
      print('ℹ️ [ŞOFÖR] Aktif yolculuk kontrolü driver_home_screen.dart\'a bırakıldı');
      
      // Sadece pending talebi kontrol et
      await _restorePendingRideRequestPopup();
    } catch (e) {
      print('❌ [ŞOFÖR] Ana uygulama persistence kontrol hatası: $e');
    }
  }

  Future<void> _restorePendingRideRequestPopup() async {
    try {
      print('🔍 [ŞOFÖR] _restorePendingRideRequestPopup başladı');
      
      final pending = await RidePersistenceService.getPendingRideRequest();
      print('📊 [ŞOFÖR] Pending request: ${pending != null ? "VAR (ID: ${pending['ride_id']})" : "YOK"}');
      
      if (pending == null) {
        print('ℹ️ [ŞOFÖR] Bekleyen talep yok - çıkılıyor');
        return;
      }

      final type = pending['type'] ?? pending['notification_type'] ?? '';
      print('📊 [ŞOFÖR] Talep tipi: $type');
      
      if (type != 'new_ride_request') {
        print('⚠️ [ŞOFÖR] Talep tipi new_ride_request değil - temizleniyor');
        await RidePersistenceService.clearPendingRideRequest();
        return;
      }

      final rideId = pending['ride_id']?.toString() ?? '';
      print('📊 [ŞOFÖR] Ride ID: $rideId');
      
      if (rideId.isEmpty) {
        print('⚠️ [ŞOFÖR] Ride ID boş - temizleniyor');
        await RidePersistenceService.clearPendingRideRequest();
        return;
      }

      final persistedAtStr = pending['persisted_at']?.toString();
      print('📊 [ŞOFÖR] Persisted at: $persistedAtStr');
      
      if (persistedAtStr != null && persistedAtStr.isNotEmpty) {
        final persistedAt = DateTime.tryParse(persistedAtStr);
        if (persistedAt != null) {
          final difference = DateTime.now().difference(persistedAt);
          print('⏰ [ŞOFÖR] Zaman farkı: ${difference.inSeconds} saniye (limit: 120 saniye)');
          
          if (difference > const Duration(minutes: 2)) {
            print('⌛️ [ŞOFÖR] Bekleyen talep süresi dolmuş - temizleniyor');
            await RidePersistenceService.clearPendingRideRequest();
            _shownPopupRideIds.remove(rideId);
            return;
          }
        }
      }

      print('📊 [ŞOFÖR] Shown popup IDs: $_shownPopupRideIds');
      print('🔍 [ŞOFÖR] Ride ID zaten gösterildi mi: ${_shownPopupRideIds.contains(rideId)}');

      if (!_shownPopupRideIds.contains(rideId)) {
        _shownPopupRideIds.add(rideId);
        print('✅ [ŞOFÖR] Ride ID sete eklendi: $rideId');
      } else {
        print('ℹ️ [ŞOFÖR] Ride ID zaten sette var: $rideId');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        print('🔍 [ŞOFÖR] PostFrameCallback - context: ${ctx != null}');
        if (ctx != null) {
          print('🔔 [ŞOFÖR] Bekleyen talep popup yeniden gösteriliyor (app launch)');
          _showRideRequestPopup(ctx, pending);
        } else {
          print('❌ [ŞOFÖR] Context null - popup gösterilemiyor');
        }
      });
    } catch (e) {
      print('❌ [ŞOFÖR] Bekleyen talep restore hatası: $e');
    }
  }

  void _handleDriverRideUpdates() {
    print('🔔 [ŞOFÖR] _handleDriverRideUpdates çağrıldı');
    
    if (_driverRideProvider == null) {
      print('❌ [ŞOFÖR] _driverRideProvider null - çıkılıyor');
      return;
    }

    final pendingQueue = _driverRideProvider!.consumePendingRideRequests();
    print('📊 [ŞOFÖR] Pending queue boyutu: ${pendingQueue.length}');
    
    if (pendingQueue.isEmpty) {
      print('ℹ️ [ŞOFÖR] Pending queue boş - çıkılıyor');
      return;
    }

    final activeIds = _driverRideProvider!.availableRides.map((ride) => ride.id).toSet();
    _pollingNotifiedRideIds.removeWhere((id) => !activeIds.contains(id));
    
    print('📊 [ŞOFÖR] Active ride IDs: $activeIds');
    print('📊 [ŞOFÖR] Polling notified IDs: $_pollingNotifiedRideIds');

    for (final raw in pendingQueue) {
      if (raw is! Map) {
        print('⚠️ [ŞOFÖR] Queue item Map değil, atlanıyor');
        continue;
      }

      final normalized = _normalizeRideDataForPopup(Map<String, dynamic>.from(raw as Map));
      final rideId = normalized['ride_id']?.toString() ?? '';

      print('🔍 [ŞOFÖR] İşlenen talep ID: $rideId');

      if (rideId.isEmpty) {
        print('⚠️ [ŞOFÖR] Ride ID boş, atlanıyor');
        continue;
      }

      if (_pollingNotifiedRideIds.contains(rideId)) {
        print('⚠️ [ŞOFÖR] Ride ID zaten gösterildi: $rideId - duplicate engellendi');
        continue;
      }

      _pollingNotifiedRideIds.add(rideId);
      print('✅ [ŞOFÖR] Ride ID sete eklendi: $rideId');

      RidePersistenceService.savePendingRideRequest(normalized);

      final ctx = navigatorKey.currentContext;
      print('🔍 [ŞOFÖR] Context kontrol: ${ctx != null}');
      
      if (ctx != null) {
        print('✅ [ŞOFÖR] Context hazır, popup gösterilecek - addPostFrameCallback');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final currentCtx = navigatorKey.currentContext;
          print('🔍 [ŞOFÖR] PostFrameCallback - context: ${currentCtx != null}');
          if (currentCtx != null) {
            print('🚀 [ŞOFÖR] _showRideRequestPopup çağrılıyor!');
            _showRideRequestPopup(currentCtx, normalized);
          } else {
            print('❌ [ŞOFÖR] PostFrameCallback context null!');
          }
        });
      } else {
        print('📦 [ŞOFÖR] Popup gösterimi ertelendi - context hazır değil');
      }
    }
  }

  Map<String, dynamic> _normalizeRideDataForPopup(Map<String, dynamic> raw) {
    final rideId = raw['ride_id']?.toString() ?? raw['id']?.toString() ?? '';
    final estimatedPrice = raw['estimated_price']?.toString() ?? '0';
    final distance = raw['distance']?.toString() ?? raw['distance_km']?.toString() ?? '';
    final scheduledTimeFormatted = raw['scheduled_time_formatted'] ?? raw['scheduled_time']?.toString() ?? '';

    return {
      'ride_id': rideId,
      'type': raw['type'] ?? 'new_ride_request',
      'pickup_address': raw['pickup_address'] ?? raw['pickupAddress'] ?? '',
      'destination_address': raw['destination_address'] ?? raw['destinationAddress'] ?? '',
      'estimated_price': estimatedPrice,
      'distance': distance,
      'scheduled_time': raw['scheduled_time']?.toString() ?? '',
      'scheduled_time_formatted': scheduledTimeFormatted,
      'customer_name': raw['customer_name'] ?? raw['customerName'] ?? 'Müşteri',
      'customer_phone': raw['customer_phone'] ?? '',
      'customer_id': raw['customer_id']?.toString() ?? '',
      'service_type': raw['service_type'] ?? 'vale',
    };
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AdminApiProvider()), // KRİTİK EKSİK - BİLDİRİMler İÇİN!
        ChangeNotifierProvider(create: (_) => RideProvider()),
        ChangeNotifierProvider(create: (_) => PricingProvider()),
        ChangeNotifierProvider(create: (_) => DriverRideProvider()),
        ChangeNotifierProvider(create: (_) => RealTimeTrackingProvider()),
        ChangeNotifierProvider(create: (_) => WaitingTimeProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey, // TALEP POPUP İÇİN!
        title: 'FunBreak Vale Driver',
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.amber,
          primaryColor: const Color(0xFFFFD700),
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFFFFD700),
            elevation: 0,
            titleTextStyle: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.white,
            selectedItemColor: Color(0xFFFFD700),
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 8,
              shadowColor: const Color(0xFFFFD700).withOpacity(0.3),
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 8,
            shadowColor: Colors.black.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFFD700),
            brightness: Brightness.light,
          ),
        ),
        home: const AuthWrapper(), // NORMAL AKIŞ - İZİN KONTROL ARKA PLANDA!
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const MainScreen(), // NORMAL ANA SAYFA - PERSİSTENCE İÇİNDE!
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Session yükle ve izinleri iste
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).checkAuthStatus();
      
      // İzinleri iste (arka planda)
      requestPermissions();
      
      // Firebase messaging ve diğer servisleri başlat
      _initializeServices();
    });
  }
  
  Future<void> _initializeServices() async {
    try {
      // Firebase messaging + HANDLER EKLE - TIMEOUT İLE!
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      
        // Topic subscription'ları timeout ile koru - BACKGROUND İÇİN KRİTİK!
        print('🔔 === TOPIC SUBSCRIPTION BAŞLADI ===');
        await Future.wait([
          messaging.subscribeToTopic('funbreak_drivers'),
          messaging.subscribeToTopic('funbreak_all'),
        ]).timeout(
          const Duration(seconds: 5), // Background için daha uzun timeout
          onTimeout: () {
            print('⚠️ SÜRÜCÜ Firebase topic subscription timeout (5s) - hızlı devam');
            return [];
          },
        );
        print('✅ Topic subscription tamamlandı: funbreak_drivers, funbreak_all');
      
      // ANDROID NOTIFICATION CHANNEL OLUŞTUR - PROGRAMATIK!
      try {
        print('📱 SÜRÜCÜ: Android notification channel oluşturuluyor...');
        
        // Flutter local notifications ile channel oluştur
        FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
            FlutterLocalNotificationsPlugin();
            
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'funbreak_driver_channel', // AndroidManifest ile eşleşmeli
          'FunBreak Driver Notifications',
          description: 'Şoför için önemli bildirimler',
          importance: Importance.max,
          sound: RawResourceAndroidNotificationSound('notification'), // Custom notification sound!
        );
        
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
            
        print('✅ SÜRÜCÜ: Android notification channel OLUŞTURULDU!');
        print('📱 Channel ID: funbreak_driver_channel');
      } catch (e) {
        print('❌ SÜRÜCÜ: Notification channel oluşturma hatası: $e');
      }
      
        // FIREBASE MESSAGE HANDLER - TAM ÖZELLİKLİ!
        try {
          // Uygulama açıkken gelen bildirimler (Foreground)
          FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
            print('📱 === ŞOFÖR BİLDİRİM ALINDI (FOREGROUND) ===');
            print('   📋 Title: ${message.notification?.title}');
            print('   💬 Body: ${message.notification?.body}');
            print('   📊 Data: ${message.data}');
            print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
            print('   🌐 From: ${message.from ?? 'Unknown'}');
            print('   🆔 Message ID: ${message.messageId ?? 'No ID'}');
            
            // YENİ TALEP BİLDİRİMİ İŞLEME - AKILLI TALEP SİSTEMİ!
            final messageType = message.data['type'] ?? '';
            if (messageType == 'new_ride_request') {
              print('🚗 === YENİ VALE TALEBİ ALINDI ===');
              final rideId = message.data['ride_id'] ?? '';
              
              // DUPLİCATE KONTROL - FOREGROUND!
              if (_shownPopupRideIds.contains(rideId)) {
                print('⚠️ Popup zaten gösterildi (foreground duplicate) - atlandı: $rideId');
                return;
              }
              
              final distance = message.data['distance'] ?? '';
              print('   🆔 Ride ID: $rideId');
              print('   📍 Mesafe: ${distance}km');
              
              _shownPopupRideIds.add(rideId); // İŞARETLE!
              
              // TALEP POPUP GÖSTER (Uygulama açıksa)
              if (navigatorKey.currentContext != null) {
                RidePersistenceService.savePendingRideRequest(message.data);
                _showRideRequestPopup(navigatorKey.currentContext!, message.data);
              }
            }
            
            // MANUEL ATAMA BİLDİRİMİ İŞLEME - PANEL'DEN ATAMA - DİREKT YOLCULUK EKRANI!
            if (messageType == 'manual_assignment' || messageType == 'driver_assigned_goto_ride') {
              print('🏢 === MANUEL VALE ATAMA ALINDI - DİREKT YOLCULUK EKRANI ===');
              final rideId = message.data['ride_id'] ?? '';
              print('   🆔 Ride ID: $rideId');
              print('   📋 Yönetici tarafından iş atandı');
              print('   ⚡ POPUP YOK - Direkt yolculuk ekranına gidiliyor!');
              
              // DİREKT YOLCULUK EKRANINA GİT!
              if (navigatorKey.currentContext != null) {
                _goDirectToActiveRideScreen(navigatorKey.currentContext!, rideId);
              }
            }
            
            // YOLCULUK TAMAMLANDI BİLDİRİMİ - PERSİSTENCE TEMİZLE VE TALEP ARAMAYA BAŞLA!
            if (messageType == 'ride_completed') {
              print('✅ [ŞOFÖR FOREGROUND] YOLCULUK TAMAMLANDI - Persistence temizleniyor!');
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('active_driver_ride_data');
                await prefs.remove('driver_ride_state');
                await prefs.remove('current_ride_id');
                await RidePersistenceService.clearPendingRideRequest();
                print('✅ [FOREGROUND] Tüm sürücü persistence temizlendi!');
                
                // Provider'dan da temizle
                if (navigatorKey.currentContext != null) {
                  try {
                    final provider = Provider.of<DriverRideProvider>(navigatorKey.currentContext!, listen: false);
                    provider.clearCurrentRide();
                    print('✅ [FOREGROUND] DriverRideProvider temizlendi - talep aramaya başlayacak!');
                  } catch (e) {
                    print('⚠️ [FOREGROUND] Provider temizleme hatası (context sorunu): $e');
                  }
                }
              } catch (e) {
                print('❌ [ŞOFÖR FOREGROUND] Persistence temizleme hatası: $e');
              }
            }
            
            // GÖRSEL FEEDBACK + UI REFRESH!
            if (message.notification != null) {
              print('🎉 SÜRÜCÜ: Panel duyurusu başarıyla alındı!');
              print('📢 ${message.notification!.title}: ${message.notification!.body}');
              print('🔔 BİLDİRİM GELECEK - System notification tray\'de gözükecek');
              print('🔄 DUYURU UI REFRESH tetikleniyor...');
            } else {
              print('⚠️ SÜRÜCÜ: notification null - sadece data var');
            }
          });
        
        // Uygulama kapalıyken bildirime tıklanınca (Background)
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('📱 ŞOFÖR: Kapalıyken gelen bildirime tıklandı');
          print('   📋 Title: ${message.notification?.title}');
          print('   📊 Data: ${message.data}');
          print('🔔 Background notification çalışıyor - System tray\'den açıldı');
          
          // YENİ TALEP BİLDİRİMİ İŞLEME - BACKGROUND'DAN AÇILINCA!
          final messageType = message.data['type'] ?? '';
          if (messageType == 'new_ride_request') {
            final rideId = message.data['ride_id']?.toString() ?? '';
            
            // DUPLİCATE KONTROL!
            if (_shownPopupRideIds.contains(rideId)) {
              print('⚠️ Popup zaten gösterildi - duplicate atlandı: $rideId');
              return;
            }
            
            print('🚗 === BACKGROUND\'DAN YENİ VALE TALEBİ POPUP AÇILIYOR ===');
            final distance = message.data['distance_km'] ?? '';
            print('   🆔 Ride ID: $rideId');
            print('   📍 Mesafe: ${distance}km');
            
            _shownPopupRideIds.add(rideId); // İŞARETLE!
            
            // Biraz bekle ki uygulama tamamen yüklensin, sonra popup aç
            Future.delayed(const Duration(milliseconds: 1500), () async {
              // ÇEVRİMDIŞI KONTROLÜ!
              final prefs = await SharedPreferences.getInstance();
              final isOnline = prefs.getBool('driver_is_online') ?? false;
              
              if (!isOnline) {
                print('🔴 [POPUP ENGELLENDI] Sürücü çevrimdışı - talep popup\'ı açılmıyor!');
                return;
              }
              
              if (navigatorKey.currentContext != null) {
                print('🚗 POPUP AÇILIYOR - Background\'dan gelen bildirim için (ÇEVRİMİÇİ)');
                RidePersistenceService.savePendingRideRequest(message.data);
                _showRideRequestPopup(navigatorKey.currentContext!, message.data);
              } else {
                print('❌ Context yok - popup açılamadı');
              }
            });
          }
          
          // MANUEL ATAMA BİLDİRİMİ İŞLEME - BACKGROUND'DAN DİREKT YOLCULUK EKRANI!
          if (messageType == 'manual_assignment' || messageType == 'driver_assigned_goto_ride') {
            print('🏢 === BACKGROUND\'DAN MANUEL VALE ATAMA - DİREKT YOLCULUK EKRANI ===');
            final rideId = message.data['ride_id'] ?? '';
            print('   🆔 Ride ID: $rideId');
            print('   ⚡ POPUP YOK - Direkt yolculuk ekranına gidiliyor!');
            
            Future.delayed(const Duration(milliseconds: 1500), () async {
              if (navigatorKey.currentContext != null) {
                print('🏢 MANUEL ATAMA - Yolculuk bilgileri çekiliyor...');
                await _goDirectToActiveRideScreen(navigatorKey.currentContext!, rideId);
              } else {
                print('❌ Context yok - yolculuk ekranı açılamadı');
              }
            });
          }
        });
        
        // NOTIFICATION PERMISSION KONTROL - SÜRÜCÜ İÇİN ZORUNLU!
        final permission = await messaging.requestPermission(
          alert: true,
          announcement: true,
          badge: true,
          carPlay: false,
          criticalAlert: true,
          provisional: false,
          sound: true,
        );
        
        print('📱 === SÜRÜCÜ NOTIFICATION PERMISSION ===');
        print('   🔔 Authorization Status: ${permission.authorizationStatus}');
        print('   📢 Alert: ${permission.alert}');
        print('   🔊 Sound: ${permission.sound}');
        print('   🏷️ Badge: ${permission.badge}');
        
        if (permission.authorizationStatus == AuthorizationStatus.denied) {
          print('❌ SÜRÜCÜ: Notification permission DENIED!');
          return; // Permission yoksa token alamazsın!
        } else {
          print('✅ SÜRÜCÜ: Notification permission GRANTED!');
        }
        
        // ⏱️ iOS'TA TOKEN ALMA 10 SANİYE SÜREBİLİR - AWAIT İLE BEKLEYELİM!
        try {
          final token = await messaging.getToken().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⏱️ iOS FCM Token timeout - tekrar denenecek');
              return null;
            },
          );
          
          print('📱 === SÜRÜCÜ FCM TOKEN KONTROL ===');
          print('📱 FCM Token (ŞOFÖR): $token');
          
          // TOKEN KONTROL BİLGİSİ - TELEFONDA GÖREBİLİRSİNİZ!
          if (token != null && token.isNotEmpty) {
            print('🎉 ŞOFÖR: FCM Token BAŞARILI!');
            print('🔔 ŞOFÖR: Firebase bağlantısı ÇALIŞIYOR');
            print('📋 Token (ilk 20): ${token.substring(0, 20)}...');
            print('🔥 ŞOFÖR TOPIC: funbreak_drivers subscription VAR');
            print('💬 Panel duyuru gönderilince bu token\'a bildirim düşecek!');
            
            // FCM TOKEN'I DATABASE'E KAYDET!
            await _saveFCMTokenToDatabase(token);
          } else {
            print('❌ ŞOFÖR: FCM Token alınamadı - KRITIK SORUN!');
            print('🚨 ŞOFÖR: Firebase bağlantı sorunu - bildirimler düşmeyecek!');
            
            // 5 saniye sonra tekrar dene
            Future.delayed(const Duration(seconds: 5), () async {
              final retryToken = await messaging.getToken();
              if (retryToken != null) {
                print('🔄 ŞOFÖR: İkinci FCM token denemesi BAŞARILI!');
                await _saveFCMTokenToDatabase(retryToken);
              }
            });
          }
        } catch (e) {
          print('❌ === SÜRÜCÜ FCM TOKEN CRİTİK HATA ===');
          print('🐛 HATA: $e');
          print('💡 ÇÖZÜM: Internet/Firebase permission kontrol et');
        }
        
        print('✅ ŞOFÖR Push notification handler\'ları TAMAMI kuruldu');
      } catch (e) {
        print('❌ ŞOFÖR notification setup hatası: $e');
      }
      
      // Dinamik contact service
      await DynamicContactService.initialize();
      
      // Location tracking HER ZAMAN ÇALIŞMALI - ÇEVRİMDIŞI ŞOFÖR DE TAKİP EDİLSİN!
      await LocationTrackingService.startLocationTracking();
      print('📍 Location tracking sürekli başlatıldı - çevrimiçi/çevrimdışı fark etmez');
      
      print('Servisler başlatıldı');
    } catch (e) {
      print('Servis başlatma hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
              ),
            ),
          );
        }
        
        if (authProvider.isLoggedIn) {
          return const MainScreen();
        }
        
        return const LoginScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _permissionsChecked = false;
  bool _wasInBackground = false;
  
  final List<Widget> _screens = [
    const DriverHomeScreen(),
    const ServicesScreen(),
    const SettingsScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndRequestPermissions();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  // APP LIFECYCLE YÖNETİMİ - DETAYLI DEBUG TRACKING!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    print('🔄 === LIFECYCLE DEĞİŞİKLİĞİ ===');
    print('   State: $state');
    print('   Timestamp: ${DateTime.now()}');
    print('   _wasInBackground: $_wasInBackground');
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 RESUMED: Uygulama ön plana geldi');
        _handleAppResumed();
        break;
        
      case AppLifecycleState.paused:
        print('🏠 PAUSED: Uygulama arka plana gitti - ÇEVRİMDIŞI YAPILMAMALI!');
        _handleAppPaused();
        break;
        
      case AppLifecycleState.detached:
        print('🔴 DETACHED: Uygulama kapanıyor - ÇEVRİMDIŞI YAPILACAK!');
        _handleAppStopped();
        break;
        
      case AppLifecycleState.inactive:
        print('⚪ INACTIVE: Uygulama geçici deaktif - ÇEVRİMDIŞI YAPILMAYACAK');
        // Inactive durumunda hiçbir şey yapma
        break;
        
      default:
        print('🔵 OTHER STATE: $state');
        break;
    }
    
    print('🔄 === LIFECYCLE İŞLEMİ TAMAMLANDI ===');
  }
  
  // UYGULAMA ÖN PLANA GELDİ - SADECE ARKA PLANDAN GELDİĞİNİ İŞARETLE
  Future<void> _handleAppResumed() async {
    print('🟢 Uygulama ön plana geldi');
    
    // Arka plandan geliyorsa flag'i temizle
    if (_wasInBackground) {
      _wasInBackground = false;
      print('⚪ Arka plandan geldi - durum korunuyor (çevrimiçi kaldı)');
      return;
    }
    
    print('🔄 Uygulama yeni açıldı - DriverRideProvider zaten çevrimdışı başlatmış');
  }
  
  // UYGULAMA ARKA PLANA GİTTİ - ÇEVRİMİÇİ KALSIN!
  Future<void> _handleAppPaused() async {
    print('🟡 === _handleAppPaused ÇAĞRILDI ===');
    print('   📝 SADECE FLAG AYARLANIYOR - ÇEVRİMDIŞI YAPILMIYOR!');
    
    _wasInBackground = true;
    
    print('   ✅ _wasInBackground = true ayarlandı');
    print('   ❌ ÇEVRİMDIŞI YAPAN KOD YOK!');
    print('   📍 Location tracking DEVAM ETMELI');
    print('   📞 Talep alabilir OLMALI');
    print('🟡 === _handleAppPaused TAMAMLANDI ===');
  }
  
  // UYGULAMA KAPANDI - ÇEVRİMDIŞI YAP
  Future<void> _handleAppStopped() async {
    print('🔴 Uygulama KAPANIYOR - çevrimdışı yapılıyor');
    
    try {
      final driverProvider = Provider.of<DriverRideProvider>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id');
      
      if (driverId != null) {
        await driverProvider.updateOnlineStatus(false, driverId);
        print('✅ Uygulama kapanırken çevrimdışı yapıldı');
      }
    } catch (e) {
      print('❌ Çevrimdışı yapma hatası: $e');
    }
  }
  
  // KONUM İZNİ "HER ZAMAN" ZORUNLU DIALOG!
  void _showLocationAlwaysRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('Konum İzni "Her Zaman" Gerekli!')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Vale takibi için konum izninizi "HER ZAMAN İZİN VER" olarak ayarlayın.',
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📱 ZORUNLU ADIMLAR:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('1. Ayarlar → Uygulamalar → FunBreak Vale'),
                  Text('2. İzinler → Konum'),
                  Text('3. "Her zaman izin ver" seçin'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Ayarlara Git', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  // GERESİZ METODLAR KALDIRILDI - BASIT LİFECYCLE YÖNETİMİ
  
  Future<void> _checkAndRequestPermissions() async {
    if (_permissionsChecked) return;
    
    try {
      // Bildirim izni kontrol et (Platform-aware!)
      if (Platform.isAndroid) {
      var notificationStatus = await Permission.notification.status;
      if (notificationStatus.isDenied) {
        await _requestPermissionWithDialog('Bildirim', Permission.notification);
        }
      } else if (Platform.isIOS) {
        // iOS'ta Firebase Messaging ile kontrol
        final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
        if (fcmSettings.authorizationStatus != AuthorizationStatus.authorized &&
            fcmSettings.authorizationStatus != AuthorizationStatus.provisional) {
          await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
        }
      }
      
      // KONUM İZNİ "HER ZAMAN" ZORUNLU KONTROL!
      LocationPermission locationPermission = await Geolocator.checkPermission();
      debugPrint('📍 Mevcut konum izni: $locationPermission');
      
      if (locationPermission != LocationPermission.always) {
        debugPrint('❌ KONUM İZNİ "HER ZAMAN" DEĞİL - ZORUNLU UYARI!');
        _showLocationAlwaysRequiredDialog();
        return; // İzin alınana kadar dur
      }
      
      debugPrint('✅ Konum izni "Her Zaman" - devam edilebilir');
      
      // Arka plan izinleri kontrol et (SADECE ANDROID!)
      if (Platform.isAndroid) {
      var batteryOptimization = await Permission.ignoreBatteryOptimizations.status;
      if (batteryOptimization.isDenied) {
        await _requestPermissionWithDialog('Pil Optimizasyonu', Permission.ignoreBatteryOptimizations);
        }
      }
      
      _permissionsChecked = true;
    } catch (e) {
      print('İzin kontrol hatası: $e');
    }
  }
  
  Future<void> _requestPermissionWithDialog(String permissionName, Permission permission) async {
    // Özel konum izni işlemi
    if (permission == Permission.locationAlways) {
      await _requestLocationAlwaysPermission();
      return;
    }
    
    // Diğer izinler için normal işlem
    var result = await permission.request();
    
    if (result.isDenied) {
      result = await permission.request();
    }
    
    if (result.isDenied || result.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$permissionName İzni Gerekli'),
            content: Text('$permissionName izni uygulama için gereklidir. Lütfen ayarlardan izin verin.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Ayarlara Git'),
              ),
            ],
          ),
        );
      }
    }
  }
  
  Future<void> _requestLocationAlwaysPermission() async {
    try {
      // 1. Önce normal konum izni iste
      var locationResult = await Permission.location.request();
      
      if (locationResult.isGranted) {
        // 2. Sonra "her zaman" izni iste
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Her Zaman Konum İzni'),
              content: const Text('Sürücü takibi için konum iznini "Her zaman izin ver" olarak ayarlayın.\n\nAyarlar → Konum → Her zaman izin ver'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('Ayarlara Git'),
                ),
              ],
            ),
          );
        }
        
        // Her zaman izni iste
        await Permission.locationAlways.request();
      }
    } catch (e) {
      print('Konum izni hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Ana Sayfa'),
                _buildNavItem(1, Icons.history_rounded, 'Geçmiş Yolculuklar'),
                _buildNavItem(2, Icons.settings_rounded, 'Ayarlar'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFFFFD700) 
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: isSelected ? 26 : 22,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[600],
                fontSize: isSelected ? 11 : 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(
                label,
                overflow: TextOverflow.clip,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// YENİ TALEP POPUP - AKILLI TALEP SİSTEMİ İÇİN!
void _showRideRequestPopup(BuildContext context, Map<String, dynamic> data) {
  final rideId = data['ride_id'] ?? '';
  // BACKEND'DEN distance_km VE arrival_minutes GELİYOR!
  final distance = data['distance_km']?.toString() ?? data['distance']?.toString() ?? '0';
  final arrivalMinutes = data['arrival_minutes']?.toString() ?? '0';
  final pickupAddress = data['pickup_address'] ?? 'Konum belirtilmedi';
  final destinationAddress = data['destination_address'] ?? 'Varış belirtilmedi';
  final scheduledTimeRaw = data['scheduled_time'] ?? '';
  final estimatedPrice = data['estimated_price'] ?? '0';
  final customerName = data['customer_name'] ?? 'Müşteri';
  
  // SCHEDULED TIME FORMATLAMA - MÜŞTERİNİN SEÇTİĞİ ZAMAN!
  String scheduledTime = 'Hemen';
  if (scheduledTimeRaw != null && scheduledTimeRaw.toString().isNotEmpty) {
    try {
      final scheduled = DateTime.parse(scheduledTimeRaw.toString());
      final now = DateTime.now();
      final diff = scheduled.difference(now);
      
      if (diff.inMinutes <= 30) {
        scheduledTime = 'Hemen (30 dk)';
      } else if (diff.inMinutes <= 60) {
        scheduledTime = '1 Saat Sonra';
      } else if (diff.inMinutes <= 120) {
        scheduledTime = '2 Saat Sonra';
      } else {
        scheduledTime = '${(diff.inHours)} Saat Sonra';
      }
    } catch (e) {
      scheduledTime = 'Hemen';
    }
  }
  
  print('📊 POPUP VERİLERİ:');
  print('   📍 Mesafe: ${distance}km');
  print('   ⏰ Müşteri seçimi: $scheduledTime');
  print('   💰 Fiyat: ₺$estimatedPrice');
  
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
                // MÜŞTERİ BİLGİSİ
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.blue, size: 24),
                    const SizedBox(width: 8),
                    Text(customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                
                // ALIŞ NOKTASI
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Alış Noktası:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(pickupAddress, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // VARIŞ NOKTASI
                Row(
                  children: [
                    const Icon(Icons.flag, color: Colors.red, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Varış Noktası:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(destinationAddress, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // MESAFE, FİYAT VE VARIŞI TAHMİNİ - DETAYLI!
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.social_distance, color: Colors.green, size: 22),
                            const SizedBox(height: 4),
                            Text('${distance} km', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                            const SizedBox(height: 2),
                            const Text('Müşteriye', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.payment, color: Color(0xFFFFD700), size: 22),
                            const SizedBox(height: 4),
                            Text('₺$estimatedPrice', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                            const SizedBox(height: 2),
                            const Text('Tutar', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.schedule, color: Colors.orange, size: 22),
                            const SizedBox(height: 4),
                            Text(
                              scheduledTime,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            const Text('Zaman', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
                onPressed: () async {
                  await RidePersistenceService.clearPendingRideRequest();
                  Navigator.pop(ctx);
                  _shownPopupRideIds.remove(rideId);
                  print('❌ Talep reddedildi: $rideId');
                },
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
                onPressed: () async {
                  await RidePersistenceService.clearPendingRideRequest();
                  Navigator.pop(ctx);
                  _shownPopupRideIds.remove(rideId);
                  _acceptRideRequest(rideId, rideData: data);
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

// MANUEL ATAMA POPUP GÖSTER - PANEL'DEN ATAMA!
void _showManualAssignmentPopup(BuildContext context, Map<String, dynamic> data) {
  final rideId = data['ride_id']?.toString() ?? '';

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.admin_panel_settings, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '🏢 Manuel Vale Ataması',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Yönetici tarafından size yeni bir iş atandı!',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🆔 İş Numarası: $rideId', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('📋 İş Türü: Manuel Atama', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('⏰ Zaman: ${DateTime.now().toString().substring(11, 16)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
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
                onPressed: () {
                  Navigator.pop(ctx);
                  print('❌ Manuel atama reddedildi: $rideId');
                },
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
                  _acceptManualAssignment(rideId);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
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

// MANUEL ATAMA KABUL ETME - PANEL'DEN ATAMA!
void _acceptManualAssignment(String rideId) async {
  try {
    print('✅ Manuel atama kabul ediliyor: $rideId');
    
    // Gerçek driver ID'yi al
    final prefs = await SharedPreferences.getInstance();
    final driverId = int.tryParse(prefs.getString('admin_user_id') ?? '1') ?? 1;
    
    final response = await http.post(
      Uri.parse('https://admin.funbreakvale.com/api/accept_ride_request.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'ride_id': int.parse(rideId),
        'driver_id': driverId,
      }),
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        print('🎉 MANUEL ATAMA BAŞARIYLA KABUL EDİLDİ!');
        
        // DETAYLI YOLCULUK BİLGİLERİNİ HAZIRLA
        final rideDetails = {
          'ride_id': rideId,
          'customer_id': '0',
          'customer_name': 'Müşteri',
          'customer_phone': '+90 XXX XXX XX XX',
          'pickup_address': 'Alış konumu',
          'destination_address': 'Varış konumu',
          'estimated_price': '0',
          'scheduled_time': '',
          'status': 'accepted',
          'accepted_at': DateTime.now().toIso8601String(),
        };
        
        // PERSİSTENCE KAYDET VE MODERN EKRANA GEÇ!
        await RidePersistenceService.saveActiveRide(
          rideId: int.parse(rideId),
          status: 'accepted',
          pickupAddress: 'Alış konumu',
          destinationAddress: 'Varış konumu',
          estimatedPrice: 0.0,
          customerName: 'Müşteri',
          customerPhone: '+90 XXX XXX XX XX',
          customerId: '0',
        );
        
        if (navigatorKey.currentContext != null) {
          Navigator.pushReplacement(
            navigatorKey.currentContext!,
            MaterialPageRoute(
              builder: (context) => ModernDriverActiveRideScreen(
                rideDetails: rideDetails,
                waitingMinutes: 0,
              ),
            ),
          );
          
          print('🚗 MODERN yolculuk ekranı açıldı - Manuel atama kabul edildi!');
        }
      }
    }
  } catch (e) {
    print('❌ Manuel atama kabul hatası: $e');
  }
}

// TALEP KABUL ETME - AKILLI TALEP SİSTEMİ ENTEGRASYONU!
void _acceptRideRequest(String rideId, {Map<String, dynamic>? rideData}) async {
  try {
    print('✅ Talep kabul ediliyor: $rideId');
    
    // Gerçek driver ID'yi al
    final prefs = await SharedPreferences.getInstance();
    final driverId = int.tryParse(prefs.getString('admin_user_id') ?? '1') ?? 1;
    
    final response = await http.post(
      Uri.parse('https://admin.funbreakvale.com/api/accept_ride_request.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'ride_id': int.parse(rideId),
        'driver_id': driverId,
      }),
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        print('🎉 TALEP BAŞARIYLA KABUL EDİLDİ!');
        
        // DETAYLI YOLCULUK BİLGİLERİNİ HAZIRLA
        final rideDetails = {
          'ride_id': rideId,
          'customer_id': rideData?['customer_id'] ?? '0',
          'customer_name': rideData?['customer_name'] ?? 'Müşteri',
          'customer_phone': rideData?['customer_phone'] ?? '+90 543 123 45 67',
          'pickup_address': rideData?['pickup_address'] ?? 'Alış konumu',
          'destination_address': rideData?['destination_address'] ?? 'Varış konumu',
          'estimated_price': rideData?['estimated_price'] ?? '0',
          'scheduled_time': rideData?['scheduled_time'] ?? '',
          'status': 'accepted',
          'accepted_at': DateTime.now().toIso8601String(),
        };
        
        // DriverRideProvider'a aktif yolculuk bilgisini ver
        try {
          final driverRideProvider = Provider.of<DriverRideProvider>(navigatorKey.currentContext!, listen: false);
          // TODO: Ride objesi oluşturup provider'a set et
          print('🔄 DriverRideProvider\'a aktif yolculuk bilgisi verilecek');
        } catch (e) {
          print('❌ DriverRideProvider erişim hatası: $e');
        }
        
        // PERSİSTENCE KAYDET VE MODERN EKRANA GEÇ! ✅
        await RidePersistenceService.saveActiveRide(
          rideId: int.parse(rideId),
          status: 'accepted',
          pickupAddress: rideDetails['pickup_address'] ?? 'Alış konumu',
          destinationAddress: rideDetails['destination_address'] ?? 'Varış konumu',
          estimatedPrice: double.tryParse((rideDetails['estimated_price'] ?? 0).toString()) ?? 0.0,
          customerName: rideDetails['customer_name'] ?? 'Müşteri',
          customerPhone: rideDetails['customer_phone'] ?? '+90 XXX XXX XX XX',
          customerId: rideDetails['customer_id'] ?? '0',
        );
        
        if (navigatorKey.currentContext != null) {
          Navigator.pushReplacement(
            navigatorKey.currentContext!,
            MaterialPageRoute(
              builder: (context) => ModernDriverActiveRideScreen(
                rideDetails: rideDetails,
                waitingMinutes: 0,
              ),
            ),
          );
          
          print('🚗 MODERN yolculuk ekranı açıldı - Persistence kaydedildi!');
        }

        _shownPopupRideIds.remove(rideId);
        await RidePersistenceService.clearPendingRideRequest();
      }
    }
  } catch (e) {
    print('❌ Talep kabul hatası: $e');
  }
}

// ZAMAN FORMATLAMA FONKSİYONU - ŞOFÖR İÇİN! ✅
String _formatScheduledTimeForDriver(String? scheduledTime) {
  if (scheduledTime == null || scheduledTime.isEmpty || scheduledTime == '0000-00-00 00:00:00') {
    return 'Hemen';
  }
  
  try {
    final scheduled = DateTime.parse(scheduledTime);
    final now = DateTime.now();
    final difference = scheduled.difference(now);
    
    if (difference.inMinutes <= 5) {
      return 'Hemen';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} dk sonra';
    } else if (difference.inDays == 0) {
      return '${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yarın ${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';
    } else {
      return '${scheduled.day}/${scheduled.month} ${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}';
    }
  } catch (e) {
    return 'Hemen';
  }
}

// FCM TOKEN'I DATABASE'E KAYDET!
Future<void> _saveFCMTokenToDatabase(String fcmToken) async {
  try {
    print('💾 FCM Token database\'e kaydediliyor...');

    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getString('admin_user_id');

    if (driverId == null) {
      print('❌ Driver ID bulunamadı - FCM token kaydedilemedi');
      return;
    }

    print('🔍 FCM Token Kaydetme - Driver ID: $driverId');
    print('📱 Token: ${fcmToken.substring(0, 20)}...');

    final response = await http.post(
      Uri.parse('https://admin.funbreakvale.com/api/update_fcm_token.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'driver_id': int.parse(driverId), // Integer olarak gönder
        'fcm_token': fcmToken,
        'user_type': 'driver', // Tip belirt
      }),
    ).timeout(const Duration(seconds: 10));

    print('📡 FCM Token API Response: ${response.statusCode}');
    print('📋 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('📊 API Success: ${data['success']}');
      print('💬 Message: ${data['message']}');

      if (data['success'] == true) {
        print('✅ FCM Token database\'e başarıyla kaydedildi!');
        print('🔔 Artık bildirimler gelecek!');
        print('🔥 Şoför uygulaması bildirimlere hazır!');
      } else {
        print('❌ FCM Token kaydetme hatası: ${data['message']}');

        // Eğer şoför bulunamadıysa, belki farklı driver ID var
        if (data['message'].toString().contains('bulunamad')) {
          print('⚠️ Driver ID bulunamadı - farklı ID deneyebiliriz');
        }
      }
    } else {
      print('❌ FCM Token kaydetme HTTP hatası: ${response.statusCode}');
      print('🚨 API endpoint çalışmıyor olabilir');
    }
  } catch (e) {
    print('❌ FCM Token kaydetme hatası: $e');
    print('💡 İnternet bağlantısı veya API sorunu olabilir');
  }
}

// İZİN KONTROL - ARKA PLANDA SESSİZ! ✅
Future<void> _checkPermissionsInBackground() async {
  try {
    print('🔒 [ŞOFÖR] İzinler arka planda kontrol ediliyor...');
    
    // Konum izni
    final locationStatus = await Permission.location.status;
    if (locationStatus.isDenied) {
      await Permission.location.request();
      print('📍 [ŞOFÖR] Konum izni istendi');
    }
    
    // Bildirim izni (Platform-aware!)
    if (Platform.isAndroid) {
    final notificationStatus = await Permission.notification.status;
    if (notificationStatus.isDenied) {
      await Permission.notification.request();
        print('🔔 [ŞOFÖR Android] Bildirim izni istendi');
    }
    } else if (Platform.isIOS) {
      // iOS'ta Firebase Messaging ile kontrol
      final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
      if (fcmSettings.authorizationStatus != AuthorizationStatus.authorized) {
        await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
        print('🔔 [ŞOFÖR iOS] Bildirim izni istendi');
      }
    }
    
    // Pil optimizasyonu bypass (SADECE ANDROID!)
    if (Platform.isAndroid) {
    try {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (batteryStatus.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
          print('🔋 [ŞOFÖR Android] Pil optimizasyonu bypass istendi');
      }
    } catch (e) {
        print('⚠️ [ŞOFÖR Android] Pil izni hatası (normal): $e');
      }
    } else if (Platform.isIOS) {
      print('📱 [ŞOFÖR iOS] Arka planda yenileme Info.plist\'te var');
    }
    
    print('✅ [ŞOFÖR] Arka plan izin kontrolü tamamlandı');
  } catch (e) {
    print('❌ [ŞOFÖR] İzin kontrol hatası: $e');
  }
}

// MANUEL ATAMA - DİREKT YOLCULUK EKRANINA GİT (POPUP YOK)!
Future<void> _goDirectToActiveRideScreen(BuildContext context, String rideId) async {
  try {
    print('🚗 === MANUEL ATAMA DİREKT YOLCULUK FLOW ===');
    print('   🆔 Ride ID: $rideId');
    print('   ⚡ POPUP atlanıyor - direkt active ride screen!');
    
    // Ride detaylarını API'den çek
    final response = await http.post(
      Uri.parse('https://admin.funbreakvale.com/api/get_ride_details.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ride_id': rideId}),
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['success'] == true && data['ride'] != null) {
        final rideDetails = data['ride'];
        final correctRideId = rideDetails['id'] ?? rideId;
        
        print('✅ Ride detayları alındı - Yolculuk ekranı açılıyor...');
        print('   📊 Ride ID: $correctRideId');
        print('   👤 Müşteri: ${rideDetails['customer_name']}');
        print('   📍 Pickup: ${rideDetails['pickup_address']}');
        
        // PERSİSTENCE KAYDET
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_driver_ride_data', jsonEncode({
          'ride_id': correctRideId,
          'id': correctRideId,
          'customer_id': rideDetails['customer_id'] ?? '0',
          'customer_name': rideDetails['customer_name'] ?? 'Müşteri',
          'customer_phone': rideDetails['customer_phone'] ?? '',
          'pickup_address': rideDetails['pickup_address'] ?? '',
          'destination_address': rideDetails['destination_address'] ?? '',
          'estimated_price': rideDetails['estimated_price']?.toString() ?? '0',
          'status': 'accepted',
        }));
        await prefs.setString('driver_ride_state', 'active');
        
        print('💾 Persistence kaydedildi');
        
        // DİREKT YOLCULUK EKRANINA GİT!
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ModernDriverActiveRideScreen(
              rideDetails: {
                'ride_id': correctRideId,
                'id': correctRideId,
                'customer_id': rideDetails['customer_id'] ?? '0',
                'customer_name': rideDetails['customer_name'] ?? 'Müşteri',
                'customer_phone': rideDetails['customer_phone'] ?? '0543 123 45 67',
                'pickup_address': rideDetails['pickup_address'] ?? 'Alış konumu',
                'destination_address': rideDetails['destination_address'] ?? 'Varış konumu',
                'pickup_lat': rideDetails['pickup_lat'] ?? 0.0,
                'pickup_lng': rideDetails['pickup_lng'] ?? 0.0,
                'destination_lat': rideDetails['destination_lat'] ?? 0.0,
                'destination_lng': rideDetails['destination_lng'] ?? 0.0,
                'estimated_price': rideDetails['estimated_price']?.toString() ?? '0',
                'payment_method': rideDetails['payment_method'] ?? 'card',
                'status': 'accepted',
                'created_at': rideDetails['created_at'] ?? DateTime.now().toIso8601String(),
                'accepted_at': DateTime.now().toIso8601String(),
              },
              waitingMinutes: 0,
            ),
          ),
        );
        
        print('✅ MANUEL ATAMA - Yolculuk ekranı açıldı!');
      } else {
        print('❌ Ride detayları alınamadı');
      }
    } else {
      print('❌ API hatası: ${response.statusCode}');
    }
    
  } catch (e) {
    print('❌ Manuel atama yolculuk ekranı hatası: $e');
  }
}