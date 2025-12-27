import 'dart:io';  // ⚠️ PLATFORM CHECK!
import 'dart:convert';
import 'dart:typed_data'; // 🔥 Int64List için!
import 'package:flutter/material.dart'; // COLOR İÇİN GEREKLİ!
import 'package:flutter/services.dart'; // 🔥 MethodChannel için!
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ride_persistence_service.dart';

// GELİŞMİŞ BİLDİRİM SERVİSİ - SÜRÜCÜ UYGULAMASI!
// 🔥 V2.0 - RATE LIMIT SORUNU ÇÖZÜLDÜ!
class AdvancedNotificationService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static FirebaseMessaging? _messaging;
  static bool _initialized = false;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static final Set<String> _processedMessageIds = {};
  static String? _cachedFcmToken;
  
  // 🔥 GPT FIX: Hard Guard + Cooldown!
  static bool _inProgress = false;
  static DateTime? _lastAttemptAt;
  static bool _fcmTokenSentToServer = false;
  
  // 🔄 OTOMATİK RETRY: Başarısız olunca 2dk sonra tekrar dene
  static Timer? _retryTimer;
  static int? _pendingDriverId;
  static String? _pendingUserType;
  
  // SÜRÜCÜ BİLDİRİM TÜRLERİ
  static const Map<String, NotificationConfig> _driverNotifications = {
    'new_ride_request': NotificationConfig(
      title: '🚗 Yeni Yolculuk Talebi!',
      channelId: 'rides',
      priority: 'high',
      sound: 'notification.wav',
    ),
    'ride_cancelled': NotificationConfig(
      title: '❌ Talep İptal Edildi',
      channelId: 'ride_updates',
      priority: 'normal',
      sound: 'default',
    ),
    'payment_completed': NotificationConfig(
      title: '💰 Ödeme Tamamlandı',
      channelId: 'payments',
      priority: 'normal',
      sound: 'notification.wav',
    ),
    'rating_received': NotificationConfig(
      title: '⭐ Yeni Puanlama!',
      channelId: 'ratings',
      priority: 'normal',
      sound: 'default',
    ),
    'system_announcement': NotificationConfig(
      title: '📢 Sistem Duyurusu',
      channelId: 'announcements',
      priority: 'normal',
      sound: 'default',
    ),
    'new_message': NotificationConfig(
      title: '💬 Yeni Mesaj',
      channelId: 'messages',
      priority: 'high',
      sound: 'notification.wav',
    ),
  };
  
  // 🔥 SERVİS BAŞLATMA - FCM TOKEN ALMADAN!
  static Future<void> initialize() async {
    if (_initialized) {
      print('⏭️ [VALE] Bildirim servisi zaten başlatıldı');
      return;
    }
    
    try {
      print('🔔 [VALE] Bildirim servisi başlatılıyor (V2.0 - Rate Limit Fix)...');
      
      if (Platform.isIOS) {
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: false, // 🔥 İZİN İSTEME - Login sonrası yapılacak!
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        
        await _localNotifications.initialize(
          const InitializationSettings(iOS: iosSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        print('✅ [VALE] iOS bildirim sistemi başlatıldı');
        
      } else {
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _localNotifications.initialize(
          const InitializationSettings(android: androidSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        await _createNotificationChannels();
        print('✅ [VALE] Android bildirim sistemi başlatıldı');
      }
      
      _messaging = FirebaseMessaging.instance;
      
      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      print('✅ [VALE] Foreground listener kayıtlı');
      
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      
      _initialized = true;
      print('✅ [VALE] Bildirim servisi hazır! (FCM token login sonrası alınacak)');

    } catch (e) {
      print('❌ [VALE] Bildirim servisi başlatma hatası: $e');
    }
  }
  
  // 🔥 FCM TOKEN KAYDETME - SADECE LOGIN SONRASI ÇAĞRILMALI!
  static Future<bool> registerFcmToken(int driverId, {String userType = 'driver'}) async {
    final now = DateTime.now();
    
    // 🔥 HARD GUARD: Aynı anda 2. çağrıyı engelle
    if (_inProgress) {
      print('⛔️ [VALE FCM] Guard: inProgress, SKIP - Driver: $driverId');
      return false;
    }
    
    // 🔥 COOLDOWN: 2 dakika içinde tekrar deneme engelle
    if (_lastAttemptAt != null && now.difference(_lastAttemptAt!).inSeconds < 120) {
      final remaining = 120 - now.difference(_lastAttemptAt!).inSeconds;
      print('⛔️ [VALE FCM] Guard: cooldown (${remaining}s kaldı), SKIP');
      return false;
    }
    
    // 🔒 KİLİTLE!
    _inProgress = true;
    _lastAttemptAt = now;
    
    print('🔔 [VALE FCM] registerFcmToken BAŞLADI - Driver: $driverId');
    
    // Zaten başarıyla gönderilmişse tekrar gönderme
    if (_fcmTokenSentToServer && _cachedFcmToken != null) {
      print('✅ [VALE FCM] Token zaten backend\'e gönderildi - atlanıyor');
      _inProgress = false;
      return true;
    }
    
    try {
      print('📱 [VALE FCM] Bildirim izni isteniyor...');
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      
      print('📱 [VALE FCM] İzin durumu: ${settings.authorizationStatus}');
      
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        print('❌ [VALE FCM] Bildirim izni reddedildi');
        return false;
      }
      
      if (Platform.isIOS) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        
        print('📱 [VALE FCM] iOS - APNs token bekleniyor...');
        String? apnsToken;
        for (int i = 0; i < 5; i++) {
          apnsToken = await _messaging!.getAPNSToken();
          if (apnsToken != null) {
            print('✅ [VALE FCM] APNs token alındı (${i+1}. deneme)');
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        
        if (apnsToken == null) {
          print('⚠️ [VALE FCM] APNs token alınamadı');
        }
      }
      
      // APNs → Firebase senkronizasyonu için 2sn bekle
      print('⏳ [VALE FCM] APNs → Firebase senkronizasyonu için 2sn bekleniyor...');
      await Future.delayed(const Duration(seconds: 2));
      
      // 🔥 TEK DENEME - Rate limit'i önle!
      print('🔑 [VALE FCM] Token alınıyor (TEK DENEME)...');
      String? token;
      
      try {
        token = await _messaging!.getToken().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ [VALE FCM] Token timeout');
            return null;
          },
        );
        
        if (token != null && token.isNotEmpty) {
          print('✅ [VALE FCM] Token alındı!');
        }
      } catch (tokenError) {
        print('⚠️ [VALE FCM] Token alma başarısız: $tokenError');
        
        // 🔍 NATIVE HATASI: Gerçek iOS hatasını al
        if (Platform.isIOS) {
          try {
            const channel = MethodChannel('debug_fcm');
            final nativeResult = await channel.invokeMethod('getNativeFcmToken');
            print('🔍 [VALE NATIVE] Token: $nativeResult');
          } catch (nativeError) {
            print('🔍 [VALE NATIVE HATA] $nativeError');
          }
        }
      }
      
      // Token alınamadıysa - 2 DAKİKA SONRA OTOMATİK TEKRAR DENE!
      if (token == null || token.isEmpty) {
        print('❌ [VALE FCM] Token alınamadı - 2 dakika sonra OTOMATİK tekrar denenecek');
        _scheduleRetry(driverId, userType);
        return false;
      }
      
      print('✅ [VALE FCM] Token alındı: ${token.substring(0, 30)}...');
      _cachedFcmToken = token;
      
      print('📡 [VALE FCM] Token backend\'e gönderiliyor...');
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': driverId,
          'user_type': userType,
          'fcm_token': token,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ [VALE FCM] Token backend\'e kaydedildi!');
          _fcmTokenSentToServer = true;
          _retryTimer?.cancel(); // Retry iptal
          await _subscribeToTopics();
          return true;
        } else {
          print('❌ [VALE FCM] Backend hatası: ${data['message']}');
        }
      } else {
        print('❌ [VALE FCM] HTTP hatası: ${response.statusCode}');
      }
      
      return false;
      
    } catch (e) {
      print('❌ [VALE FCM] registerFcmToken hatası: $e');
      
      if (e.toString().contains('Too many') || e.toString().contains('server requests')) {
        print('🛑 [VALE FCM] RATE LIMIT! 2 dakika sonra tekrar denenecek.');
        _scheduleRetry(driverId, userType);
      }
      
      return false;
    } finally {
      // 🔓 KİLİDİ AÇ!
      _inProgress = false;
    }
  }
  
  static String? getCachedToken() => _cachedFcmToken;
  
  static void resetTokenState() {
    _cachedFcmToken = null;
    _inProgress = false;
    _lastAttemptAt = null;
    _fcmTokenSentToServer = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingDriverId = null;
    _pendingUserType = null;
    print('🔄 [VALE FCM] Token durumu sıfırlandı');
  }
  
  // 🔄 OTOMATİK RETRY: 2 dakika sonra tekrar dene
  static void _scheduleRetry(int driverId, String userType) {
    // Önceki timer'ı iptal et
    _retryTimer?.cancel();
    
    // Bilgileri sakla
    _pendingDriverId = driverId;
    _pendingUserType = userType;
    
    // 2 dakika sonra tekrar dene
    print('⏰ [VALE FCM] 2 dakika sonra otomatik retry planlandı...');
    _retryTimer = Timer(const Duration(minutes: 2), () async {
      print('🔄 [VALE FCM] OTOMATİK RETRY başlıyor...');
      
      // Cooldown'ı sıfırla (retry için)
      _lastAttemptAt = null;
      
      // Tekrar dene
      if (_pendingDriverId != null && _pendingUserType != null) {
        final success = await registerFcmToken(_pendingDriverId!, userType: _pendingUserType!);
        if (success) {
          print('✅ [VALE FCM] OTOMATİK RETRY başarılı!');
          _pendingDriverId = null;
          _pendingUserType = null;
        } else {
          print('❌ [VALE FCM] OTOMATİK RETRY başarısız - tekrar planlanıyor...');
        }
      }
    });
  }
  
  // ANDROID BİLDİRİM KANALLARI
  static Future<void> _createNotificationChannels() async {
    if (Platform.isIOS) return;
    
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'rides_v2',
        'Yolculuk Talepleri',
        description: 'Yeni yolculuk talepleri',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'ride_updates_v2',
        'Yolculuk Güncellemeleri',
        description: 'Yolculuk durumu güncellemeleri',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'payments_v2',
        'Ödeme Bildirimleri',
        description: 'Ödeme bilgileri',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'messages_v2',
        'Mesajlar',
        description: 'Müşteri mesajları',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
    ];
    
    for (final channel in channels) {
      await androidPlugin.createNotificationChannel(channel);
    }
    
    print('✅ [VALE] ${channels.length} bildirim kanalı oluşturuldu');
  }
  
  static void _onTokenRefresh(String token) async {
    print('🔄 [VALE FCM] Token yenilendi');
    _cachedFcmToken = token;
    
    if (_fcmTokenSentToServer) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final driverIdStr = prefs.getString('admin_user_id') ?? 
                            prefs.getString('driver_id');
        
        if (driverIdStr != null) {
          final driverId = int.tryParse(driverIdStr);
          if (driverId != null && driverId > 0) {
            await _updateTokenOnServerDirect(token, driverId, 'driver');
          }
        }
      } catch (e) {
        print('❌ [VALE FCM] Token refresh sunucu hatası: $e');
      }
    }
  }
  
  static Future<void> _updateTokenOnServerDirect(String token, int userId, String userType) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': userType,
          'fcm_token': token,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        print('✅ [VALE FCM] Token refresh - sunucu güncellendi');
      }
    } catch (e) {
      print('❌ [VALE FCM] Token refresh sunucu hatası: $e');
    }
  }
  
  static Future<void> _subscribeToTopics() async {
    try {
      await _messaging!.subscribeToTopic('drivers');
      await _messaging!.subscribeToTopic('all_users');
      print('✅ [VALE FCM] Topic\'lere abone olundu: drivers, all_users');
    } catch (e) {
      print('❌ [VALE FCM] Topic abonelik hatası: $e');
    }
  }
  
  // FOREGROUND MESSAGE HANDLER
  static void _onForegroundMessage(RemoteMessage message) async {
    final messageId = message.messageId ?? '${message.sentTime?.millisecondsSinceEpoch}';
    
    if (_processedMessageIds.contains(messageId)) {
      print('⏭️ [VALE] Duplicate mesaj atlandı: $messageId');
      return;
    }
    
    _processedMessageIds.add(messageId);
    if (_processedMessageIds.length > 100) {
      _processedMessageIds.clear();
    }
    
    print('📱 === VALE FOREGROUND BİLDİRİM ===');
    print('   📋 Title: ${message.notification?.title}');
    print('   💬 Body: ${message.notification?.body}');
    print('   📊 Data: ${message.data}');
    print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
    
    // Yeni yolculuk talebi - RidePersistenceService'e kaydet
    if (message.data['type'] == 'new_ride_request') {
      await RidePersistenceService.saveFromNotification(message.data);
    }
    
    if (Platform.isAndroid) {
      await _showNotification(message);
    }
  }
  
  static void _onMessageOpenedApp(RemoteMessage message) {
    print('📱 [VALE] Notification tap: ${message.data}');
  }
  
  static void _onNotificationTapped(NotificationResponse response) {
    print('🔔 [VALE] Local notification tapped: ${response.payload}');
  }
  
  static Future<void> _showNotification(RemoteMessage message) async {
    if (Platform.isIOS) return;
    
    final notification = message.notification;
    if (notification == null) return;
    
    final type = message.data['type'] ?? 'default';
    final config = _driverNotifications[type] ?? _driverNotifications['new_ride_request']!;
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title ?? config.title,
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          '${config.channelId}_v2',
          config.title,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification'),
          enableVibration: true,
          fullScreenIntent: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    
    print('✅ [VALE] Local notification gösterildi: ${notification.title}');
  }
  
  // BACKGROUND NOTIFICATION
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    if (Platform.isIOS) return;
    
    final title = message.notification?.title ?? message.data['title'] ?? 'FunBreak Vale';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    
    final type = message.data['type'] ?? 'default';
    final config = _driverNotifications[type] ?? _driverNotifications['new_ride_request']!;
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          '${config.channelId}_v2',
          config.title,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('notification'),
          fullScreenIntent: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    
    print('✅ [VALE] Background notification gösterildi: $title');
  }
}

// NOTIFICATION CONFIG CLASS
class NotificationConfig {
  final String title;
  final String channelId;
  final String priority;
  final String sound;

  const NotificationConfig({
    required this.title,
    required this.channelId,
    required this.priority,
    required this.sound,
  });
}
