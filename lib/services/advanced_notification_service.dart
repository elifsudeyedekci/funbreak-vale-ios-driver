import 'dart:io';  // ⚠️ PLATFORM CHECK!
import 'dart:convert';
import 'dart:typed_data'; // 🔥 Int64List için!
import 'package:flutter/material.dart'; // COLOR İÇİN GEREKLİ!
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'ride_persistence_service.dart';

// GELİŞMİŞ BİLDİRİM SERVİSİ - SÜRÜCÜ UYGULAMASI!
class AdvancedNotificationService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static FirebaseMessaging? _messaging;
  static bool _initialized = false; // 🔥 Sadece 1 kez initialize
  static StreamSubscription<RemoteMessage>? _foregroundSubscription; // 🔥 Listener kontrolü
  static final Set<String> _processedMessageIds = {}; // 🔥 DUPLICATE MESSAGE ENGELLEME!
  
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
    'earnings_update': NotificationConfig(
      title: '💵 Kazanç Güncellendi',
      channelId: 'payments',
      priority: 'normal',
      sound: 'default',
    ),
  };
  
  // SERVİS BAŞLATMA - PLATFORM-SPECIFIC!
  static Future<void> initialize() async {
    // 🔥 ZATEN BAŞLATILDIYSA ATLA!
    if (_initialized) {
      print('⏭️ Sürücü bildirim servisi zaten başlatıldı - atlanıyor');
      return;
    }
    
    try {
      print('🔔 Sürücü bildirim servisi başlatılıyor... (${Platform.operatingSystem})');
      
      // ⚠️ PLATFORM-SPECIFIC INITIALIZATION
      if (Platform.isIOS) {
        // iOS initialization
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          onDidReceiveLocalNotification: _onIOSLocalNotification,
        );
        
        await _localNotifications.initialize(
          const InitializationSettings(iOS: iosSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        print('✅ iOS bildirim sistemi başlatıldı');
        
      } else {
        // Android initialization
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _localNotifications.initialize(
          const InitializationSettings(android: androidSettings),
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        
        // Android notification channels oluştur
        await _createNotificationChannels();
        print('✅ Android bildirim sistemi başlatıldı');
      }
      
      // Firebase Messaging setup (HER İKİ PLATFORM)
      _messaging = FirebaseMessaging.instance;
      
      // Permission iste
      await _requestPermissions();
      
      // Background handler main.dart'ta kayıtlı
      
      // 🔥 ESKİ LISTENER'I İPTAL ET!
      await _foregroundSubscription?.cancel();
      
      // Foreground message handler - SADECE BİR KERE!
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      print('✅ ŞOFÖR Foreground listener kayıtlı - ID: ${_foregroundSubscription.hashCode}');
      
      // App açılışında notification handler
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      
      // Token güncelleme
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);
      
      // SÜRÜCÜ topic'ine subscribe
      await _subscribeToTopics();
      
      _initialized = true; // 🔥 BAŞARILDI OLARAK İŞARETLE!
      print('✅ Sürücü bildirim servisi hazır!');
      
    } catch (e) {
      print('❌ Sürücü bildirim servisi hatası: $e');
    }
  }
  
  // ⚠️ iOS LOCAL NOTIFICATION CALLBACK
  static void _onIOSLocalNotification(int id, String? title, String? body, String? payload) async {
    // iOS 9 ve altı için (eski cihazlar)
    print('📱 iOS Local Notification alındı: $title - $body');
  }
  
  // ANDROID BİLDİRİM KANALLARI - SÜRÜCÜ KANALLARI!
  static Future<void> _createNotificationChannels() async {
    // ⚠️ iOS'te channel sistemi yok, sadece Android!
    if (Platform.isIOS) {
      print('⏭️ iOS - Channel sistemi yok, atlanıyor');
      return;
    }
    
    print('🔔 [ŞOFÖR] ANDROID CHANNEL OLUŞTURMA BAŞLADI!');
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin == null) {
      print('❌ [ŞOFÖR] AndroidFlutterLocalNotificationsPlugin NULL!');
      return;
    }
    
    print('🗑️ [ŞOFÖR] Eski channellar siliniyor...');
    // Önce eski kanalları sil
    await androidPlugin.deleteNotificationChannel('rides');
    await androidPlugin.deleteNotificationChannel('ride_updates');
    await androidPlugin.deleteNotificationChannel('payments');
    await androidPlugin.deleteNotificationChannel('ratings');
    await androidPlugin.deleteNotificationChannel('announcements');
    
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'rides',
        'Yolculuk Talepleri',
        description: 'Yeni vale talepleri ve acil bildirimler',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'ride_updates', 
        'Yolculuk Güncellemeleri',
        description: 'Yolculuk durumu değişiklikleri',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'payments',
        'Ödeme Bildirimleri', 
        description: 'Kazanç ve ödeme güncellemeleri',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'ratings',
        'Puanlama Bildirimleri',
        description: 'Müşteri puanlamaları',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
      AndroidNotificationChannel(
        'announcements',
        'Sistem Duyuruları',
        description: 'Önemli sistem bilgilendirmeleri',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFFD700),
        showBadge: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      ),
    ];
    
    print('🔨 [ŞOFÖR] ${channels.length} channel oluşturuluyor...');
    for (final channel in channels) {
      await androidPlugin.createNotificationChannel(channel);
      print('  ✅ Channel: ${channel.id} (Importance: ${channel.importance})');
    }
    
    print('✅ [ŞOFÖR] ${channels.length} sürücü bildirim kanalı OLUŞTURULDU (IMPORTANCE MAX!)');
  }
  
  // İZİN İSTEME
  static Future<void> _requestPermissions() async {
    final settings = await _messaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    
    print('🔔 Sürücü bildirim izni durumu: ${settings.authorizationStatus}');
  }
  
  // SÜRÜCÜ TOPIC SUBSCRIBE
  static Future<void> _subscribeToTopics() async {
    try {
      await _messaging!.subscribeToTopic('funbreak_drivers');
      print('✅ Sürücü topic\'ine subscribe oldu');
    } catch (e) {
      print('❌ Topic subscribe hatası: $e');
    }
  }
  
  // BACKGROUND MESSAGE HANDLER
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print('🔔 Sürücü background mesaj: ${message.messageId}');
    await _persistPendingRideRequest(message);
    await _showLocalNotification(message);
  }
  
  // PUBLIC BACKGROUND NOTIFICATION - main.dart'tan çağrılabilir!
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    print('🔔 [ŞOFÖR BACKGROUND] showBackgroundNotification çağrıldı');
    await _persistPendingRideRequest(message);
    await _showLocalNotification(message);
  }
  
  // FOREGROUND MESSAGE HANDLER
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    // 🔥 DUPLICATE MESSAGE ENGELLE!
    if (_processedMessageIds.contains(message.messageId)) {
      print('⚠️ [ŞOFÖR FOREGROUND] DUPLICATE MESAJ - ATLANIYOR: ${message.messageId}');
      return; // ❌ Aynı mesaj daha önce işlendi!
    }
    _processedMessageIds.add(message.messageId!);
    
    print('🔔 [ŞOFÖR FOREGROUND] Mesaj alındı: ${message.messageId}');
    print('   📊 Data: ${message.data}');
    print('   📋 Notification: ${message.notification?.title ?? "YOK"}');
    
    // 🔥 DATA-ONLY mesajlar için notification oluştur!
    RemoteMessage finalMessage = message;
    if (message.notification == null && message.data.isNotEmpty) {
      print('   🔥 DATA-ONLY mesaj - notification oluşturuluyor...');
      final title = message.data['title'] ?? 'FunBreak Vale Şoför';
      final body = message.data['body'] ?? 'Yeni bildirim';
      
      // Fake notification ekle
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
    
    await _persistPendingRideRequest(finalMessage);

    final notificationType = finalMessage.data['notification_type']?.toString() ?? '';
    final type = finalMessage.data['type']?.toString() ?? '';
    
    if (notificationType == 'requests_expired') {
      await RidePersistenceService.clearPendingRideRequest();
      return;
    }

    // CROSS-CANCEL KONTROL - MÜŞTERİ İPTAL ETTİ Mİ?
    if (notificationType == 'ride_cancelled_by_customer') {
      print('🚫 Müşteri talep iptal etti - popup kapatılıyor...');
      await _handleCrossCancel(finalMessage.data);
      return; // Local notification gösterme
    }
    
    // 🔥 RIDE_COMPLETED - BİLDİRİM GÖSTER VE İŞLE!
    if (type == 'ride_completed') {
      print('✅ [ŞOFÖR FOREGROUND] YOLCULUK TAMAMLANDI - Bildirim gösteriliyor!');
      
      // Persistence temizle
      await RidePersistenceService.clearPendingRideRequest();
      
      print('✅ [FOREGROUND] Tüm sürücü persistence temizlendi!');
      
      // ✅ LOCAL BİLDİRİM GÖSTER!
      await _showLocalNotification(finalMessage);
      return;
    }
    
    await _showLocalNotification(finalMessage);
  }
  
  // NOTIFICATION TAP HANDLER
  static Future<void> _onNotificationTapped(NotificationResponse response) async {
    print('🔔 Sürücü bildirime tıklandı: ${response.payload}');
    
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      await _handleDriverNotificationAction(data);
    }
  }
  
  // MESSAGE OPENED APP HANDLER
  static Future<void> _onMessageOpenedApp(RemoteMessage message) async {
    print('🔔 Mesajdan sürücü uygulaması açıldı: ${message.messageId}');
    await _persistPendingRideRequest(message, overwrite: true);
    await _handleDriverNotificationAction(message.data);
  }
  
  // TOKEN REFRESH HANDLER
  static Future<void> _onTokenRefresh(String token) async {
    print('🔔 Sürücü FCM Token yenilendi: ${token.substring(0, 20)}...');
    await _updateDriverTokenOnServer(token);
  }
  
  // LOCAL BİLDİRİM GÖSTER - SÜRÜCÜ STILI!
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    
    // 🔥 HER ZAMAN BİZİM LOCAL'İ GÖSTER - HEADS-UP GARANTİLİ!
    if (notification != null) {
      print('✅ [ŞOFÖR] Local notification gösteriliyor (heads-up garantisi için)');
      // FCM de gösterebilir ama bizimki daha agresif - heads-up olur!
      
      // 🔥 UNIQUE ID - Hash ile garanti unique
      final timestamp = DateTime.now();
      final uniqueId = (timestamp.millisecondsSinceEpoch + timestamp.microsecond).hashCode.abs() % 2147483647;
      
      // 🔥 HER BİLDİRİM İÇİN FARKLI TİTREŞİM!
      final vibrationPattern = Int64List.fromList([0, 250 + (uniqueId % 200), 250, 250]);
      
      // 🔥 HER BİLDİRİM TİPİ İÇİN AYRI CHANNEL - ANDROID RATE-LIMIT BYPASS!
      final notificationType = message.data['type'] ?? message.data['notification_type'] ?? '';
      String channelId;
      String channelName;
      String channelDesc;
      String sound = 'notification';
      
      if (notificationType == 'new_ride_request') {
        channelId = 'rides'; // ✅ Yeni talep
        channelName = 'Yolculuk Talepleri';
        channelDesc = 'Yeni yolculuk bildirimleri';
      } else if (notificationType == 'ride_completed') {
        channelId = 'payments'; // ✅ FARKLI CHANNEL!
        channelName = 'Ödeme Bildirimleri';
        channelDesc = 'Yolculuk tamamlanma bildirimleri';
      } else if (notificationType == 'ride_cancelled') {
        channelId = 'ride_updates'; // ✅ FARKLI CHANNEL!
        channelName = 'Yolculuk Güncellemeleri';
        channelDesc = 'İptal bildirimleri';
      } else {
        channelId = 'announcements'; // ✅ FARKLI CHANNEL (duyurular)!
        channelName = 'Duyurular';
        channelDesc = 'Panel duyuruları';
      }
      
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      
      // ⚠️ PLATFORM-SPECIFIC NOTIFICATION DETAILS
      NotificationDetails details;
      
      if (Platform.isIOS) {
        // iOS için DarwinNotificationDetails
        details = NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'notification.caf',  // ⚠️ iOS .caf formatı!
            badgeNumber: 1,
            threadIdentifier: 'funbreak_vale_driver',
            subtitle: 'FunBreak Vale Şoför',
            interruptionLevel: InterruptionLevel.timeSensitive, // iOS 15+ öncelikli bildirim
          ),
        );
        
      } else {
        // Android için AndroidNotificationDetails (MEVCUT SISTEM)
        final BigTextStyleInformation bigTextStyle = BigTextStyleInformation(
          notification.body ?? '',
          contentTitle: notification.title,
          htmlFormatContentTitle: true,
          htmlFormatBigText: true,
        );
        
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.max,
            priority: Priority.max,
            sound: RawResourceAndroidNotificationSound(sound),
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFFFFD700),
            enableVibration: true,
            playSound: true,
            visibility: NotificationVisibility.public,
            showWhen: true,
            when: currentTime,
            ticker: '${notification.title} - $uniqueId', // 🔥 Her bildirim FARKLI ticker
            autoCancel: true,
            onlyAlertOnce: false,
            enableLights: true,
            ledColor: const Color(0xFFFFD700),
            ledOnMs: 1000,
            ledOffMs: 500,
            category: AndroidNotificationCategory.call,
            groupKey: 'funbreak_driver_$uniqueId', // 🔥 Her bildirim KENDİ GRUBU!
            setAsGroupSummary: false,
            styleInformation: bigTextStyle,
            tag: 'notification_$uniqueId', // 🔥 Her bildirim unique tag!
            channelShowBadge: true,
            timeoutAfter: null,
            vibrationPattern: vibrationPattern, // 🔥 HER BİLDİRİM FARKLI TİTREŞİR!
          ),
        );
      }
      
      // 🔥 UNIQUE ID İLE HER BİLDİRİM AYRI!
      await _localNotifications.show(
        uniqueId,
        notification.title,
        notification.body,
        details,
        payload: jsonEncode(message.data),
      );
      
      print('🔔 ŞOFÖR BİLDİRİMİ GÖSTERİLDİ:');
      print('   ID: $uniqueId (UNIQUE - timestamp)');
      print('   Kanal: $channelId');
      print('   Başlık: ${notification.title}');
      print('   Type: $notificationType');
      print('   Ses: ✅ Titreşim: ✅ LED: ✅ Importance: MAX');
    }
  }
  
  // SÜRÜCÜ AKSİYON HANDLER
  static Future<void> _handleDriverNotificationAction(Map<String, dynamic> data) async {
    final type = data['notification_type'] ?? '';
    
    print('🔔 Sürücü bildirim aksiyonu: $type');
    
    // Sürücü bildirim türlerine göre sayfa yönlendirme
    switch (type) {
      case 'new_ride_request':
        // Ana sayfaya git (talep listesi göster)
        break;
      case 'payment_completed':
        // Kazanç sayfasına git
        break;
      case 'rating_received':
        // Profil sayfasına git
        break;
      case 'system_announcement':
        // Duyurular sayfasına git
        break;
    }
  }

  static Future<void> _persistPendingRideRequest(RemoteMessage message, {bool overwrite = false}) async {
    try {
      final type = message.data['type'] ?? message.data['notification_type'] ?? '';
      if (type != 'new_ride_request' && type != 'manual_assignment') {
        if (overwrite) {
          await RidePersistenceService.clearPendingRideRequest();
        }
        return;
      }

      final extracted = _extractRideData(message);
      if (extracted == null) {
        if (overwrite) {
          await RidePersistenceService.clearPendingRideRequest();
        }
        return;
      }

      if (overwrite) {
        await RidePersistenceService.clearPendingRideRequest();
      }

      await RidePersistenceService.savePendingRideRequest(extracted);
    } catch (e) {
      print('❌ Pending talep persistence hatası: $e');
    }
  }

  static Map<String, dynamic>? _extractRideData(RemoteMessage message) {
    try {
      Map<String, dynamic> base = {};
      message.data.forEach((key, value) {
        if (value == null) return;
        base[key] = value;
      });

      if (message.notification != null) {
        base['notification_title'] = message.notification!.title;
        base['notification_body'] = message.notification!.body;
      }

      if (!base.containsKey('ride_id')) {
        final possible = base['request_id'] ?? base['id'] ?? base['rideId'];
        if (possible != null) {
          base['ride_id'] = possible;
        }
      }

      final rideId = base['ride_id']?.toString();
      if (rideId == null || rideId.isEmpty) {
        return null;
      }

      return base;
    } catch (e) {
      print('❌ Pending talep veri çıkarma hatası: $e');
      return null;
    }
  }
  
  // SÜRÜCÜ TOKEN GÜNCELLE
  static Future<void> _updateDriverTokenOnServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '0';
      
      final response = await http.post(
        Uri.parse('$baseUrl/update_fcm_token.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': 'driver',
          'fcm_token': token,
        }),
      );
      
      if (response.statusCode == 200) {
        print('✅ Sürücü FCM Token güncellendi');
      }
    } catch (e) {
      print('❌ Sürücü token güncelleme hatası: $e');
    }
  }
  
  // CROSS-CANCEL HANDLER - MÜŞTERİ İPTAL ETTİ!
  static Future<void> _handleCrossCancel(Map<String, dynamic> data) async {
    try {
      final rideId = data['ride_id']?.toString() ?? '';
      final customerId = data['customer_id']?.toString() ?? '';
      final reason = data['cancellation_reason'] ?? 'customer_cancelled';
      
      print('🚫 Cross-cancel işleniyor - Ride: $rideId, Müşteri: $customerId, Sebep: $reason');
      
      // POPUP KAPAT - Customer request cancelled
      print('📱 Driver popup should close - customer: $customerId cancelled');
      
      // HEM PENDING HEM AKTİF YOLCULUĞU TEMİZLE!
      print('🗑️ Bekleyen talep temizleniyor...');
      await RidePersistenceService.clearPendingRideRequest();
      
      print('🗑️ Aktif yolculuk temizleniyor (ride: $rideId)...');
      final prefs = await SharedPreferences.getInstance();
      
      // 1. active_driver_ride_data (modern_driver_active_ride_screen için)
      final activeRideJson = prefs.getString('active_driver_ride_data');
      if (activeRideJson != null) {
        final activeRide = jsonDecode(activeRideJson);
        final activeRideId = activeRide['ride_id']?.toString() ?? '';
        
        // İptal edilen ride ile aktif ride aynı mı?
        if (activeRideId == rideId || rideId.isEmpty) {
          await prefs.remove('active_driver_ride_data');
          await prefs.remove('driver_ride_state');
          print('✅ active_driver_ride_data temizlendi - Ride: $activeRideId');
        } else {
          print('ℹ️ Farklı ride aktif (active_driver_ride_data: $activeRideId), iptal edilen: $rideId');
        }
      }
      
      // 2. current_ride (DriverRideProvider için) - KRİTİK!
      final currentRideJson = prefs.getString('current_ride');
      if (currentRideJson != null) {
        final currentRide = jsonDecode(currentRideJson);
        final currentRideId = currentRide['id']?.toString() ?? '';
        
        // İptal edilen ride ile current ride aynı mı?
        if (currentRideId == rideId || rideId.isEmpty) {
          await prefs.remove('current_ride');
          print('✅ current_ride temizlendi - Ride: $currentRideId');
          print('🔄 DriverRideProvider restore ederken _currentRide=null olacak!');
          
          // FLAG YAZ - Polling'de _currentRide temizlenecek!
          await prefs.setString('ride_cancelled_flag', DateTime.now().toIso8601String());
          print('FLAG YAZILDI: ride_cancelled_flag - Polling bu flag kontrol edecek ve _currentRide temizleyecek!');
        } else {
          print('ℹ️ Farklı ride aktif (current_ride: $currentRideId), iptal edilen: $rideId');
        }
      }
      
      print('✅ Tüm persistence temizlendi - uygulama yeni talepleri görebilir!');
      
    } catch (e) {
      print('❌ Cross-cancel handle hatası: $e');
    }
  }
  
  // SÜRÜCÜ MANUEl BİLDİRİM GÖNDER
  static Future<bool> sendDriverNotification({
    required String notificationType,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '0';
      
      final config = _driverNotifications[notificationType];
      if (config == null) {
        print('❌ Bilinmeyen sürücü bildirim türü: $notificationType');
        return false;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/send_advanced_notification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'user_type': 'driver',
          'notification_type': notificationType,
          'title': config.title,
          'message': _formatMessage(config.title, data),
          'data': data,
        }),
      );
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      
      return false;
    } catch (e) {
      print('❌ Sürücü manuel bildirim hatası: $e');
      return false;
    }
  }
  
  // MESAJ FORMATLAMA
  static String _formatMessage(String template, Map<String, dynamic> data) {
    String message = template;
    
    data.forEach((key, value) {
      message = message.replaceAll('{$key}', value.toString());
    });
    
    return message;
  }
}

// BİLDİRİM KONFİGÜRASYON SINIFI
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
