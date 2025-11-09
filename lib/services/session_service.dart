import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _sessionKey = 'driver_session';
  static const String _lastActivityKey = 'last_activity';
  static const String _autoLoginKey = 'auto_login_enabled';
  static const String _driverIdKey = 'driver_id';
  static const String _driverNameKey = 'driver_name';
  static const String _driverPhoneKey = 'driver_phone';
  static const String _driverEmailKey = 'driver_email'; // YENİ EKLENEN!
  
  static Timer? _sessionTimer;
  static bool _isSessionActive = false;
  
  // Session süresi (45 gün - optimum süre!)
  static const Duration sessionDuration = Duration(days: 45);
  
  // Otomatik çıkışı engelle - session'ı sürekli aktif tut
  static Future<void> initializeSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Otomatik giriş her zaman aktif - kullanıcı manuel kapatana kadar
      await prefs.setBool(_autoLoginKey, true);
      
      // Session'ı aktif olarak işaretle
      await _updateLastActivity();
      _isSessionActive = true;
      
      // Periyodik activity güncelleme (her 2 dakikada bir)
      _sessionTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
        await _updateLastActivity();
        print('Session activity güncellendi - Otomatik çıkış engellendi');
      });
      
      print('Session başlatıldı - Otomatik çıkış tamamen devre dışı');
    } catch (e) {
      print('Session başlatma hatası: $e');
    }
  }
  
  // Son aktiviteyi güncelle
  static Future<void> _updateLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Last activity güncelleme hatası: $e');
    }
  }
  
  // Şoför girişi kaydet - EMAIL EKLENDİ!
  static Future<bool> saveDriverLogin({
    required String driverId,
    required String driverName,
    required String driverPhone,
    String? driverEmail, // YENİ EKLENEN PARAMETRE!
    bool enableAutoLogin = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Şoför bilgilerini kaydet
      await prefs.setString(_driverIdKey, driverId);
      await prefs.setString(_driverNameKey, driverName);
      await prefs.setString(_driverPhoneKey, driverPhone);
      if (driverEmail != null) {
        await prefs.setString(_driverEmailKey, driverEmail); // EMAIL KAYDET!
      }
      await prefs.setBool(_autoLoginKey, enableAutoLogin);
      await prefs.setBool(_sessionKey, true);
      
      // Son aktiviteyi güncelle
      await _updateLastActivity();
      
      // Session'ı başlat
      if (enableAutoLogin) {
        await initializeSession();
      }
      
      print('Şoför girişi kaydedildi: $driverName (Auto-login: $enableAutoLogin)');
      return true;
    } catch (e) {
      print('Şoför giriş kaydetme hatası: $e');
      return false;
    }
  }
  
  // Şoför bilgilerini al - EMAIL EKLENDİ!
  static Future<Map<String, String>?> getDriverInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      String? driverId = prefs.getString(_driverIdKey);
      String? driverName = prefs.getString(_driverNameKey);
      String? driverPhone = prefs.getString(_driverPhoneKey);
      String? driverEmail = prefs.getString(_driverEmailKey); // YENİ EKLENENEMAİL!
      
      if (driverId != null && driverName != null) {
        return {
          'driver_id': driverId,
          'driver_name': driverName,
          'driver_phone': driverPhone ?? '',
          'driver_email': driverEmail ?? 'driver$driverId@funbreakvale.com', // EMAIL EKLENDİ!
        };
      }
      
      return null;
    } catch (e) {
      print('Şoför bilgisi alma hatası: $e');
      return null;
    }
  }
  
  // Session geçerli mi kontrol et
  static Future<bool> isSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      bool sessionExists = prefs.getBool(_sessionKey) ?? false;
      bool autoLoginEnabled = prefs.getBool(_autoLoginKey) ?? false;
      
      if (!sessionExists) {
        print('Session bulunamadı');
        return false;
      }
      
      // Otomatik giriş aktifse session her zaman geçerli
      if (autoLoginEnabled) {
        await _updateLastActivity(); // Activity'yi güncelle
        print('Session geçerli (auto-login aktif)');
        return true;
      }
      
      // Otomatik giriş kapalıysa son aktiviteyi kontrol et
      int? lastActivity = prefs.getInt(_lastActivityKey);
      if (lastActivity == null) {
        print('Son aktivite bulunamadı');
        return false;
      }
      
      DateTime lastActivityTime = DateTime.fromMillisecondsSinceEpoch(lastActivity);
      DateTime now = DateTime.now();
      
      if (now.difference(lastActivityTime) > sessionDuration) {
        print('Session süresi dolmuş');
        await clearSession();
        return false;
      }
      
      print('Session geçerli');
      return true;
    } catch (e) {
      print('Session kontrol hatası: $e');
      return false;
    }
  }
  
  // Otomatik giriş durumunu değiştir
  static Future<bool> setAutoLogin(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoLoginKey, enabled);
      
      if (enabled) {
        // Otomatik giriş aktifleştirildi, session'ı başlat
        await initializeSession();
      } else {
        // Otomatik giriş kapatıldı, timer'ı durdur
        _sessionTimer?.cancel();
        _sessionTimer = null;
        _isSessionActive = false;
      }
      
      print('Otomatik giriş durumu değiştirildi: $enabled');
      return true;
    } catch (e) {
      print('Otomatik giriş ayarlama hatası: $e');
      return false;
    }
  }
  
  // Otomatik giriş durumunu al
  static Future<bool> isAutoLoginEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_autoLoginKey) ?? true; // Varsayılan: aktif
    } catch (e) {
      print('Otomatik giriş durumu alma hatası: $e');
      return true;
    }
  }
  
  // Session'ı temizle (çıkış)
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Session bilgilerini temizle
      await prefs.remove(_sessionKey);
      await prefs.remove(_lastActivityKey);
      await prefs.remove(_driverIdKey);
      await prefs.remove(_driverNameKey);
      await prefs.remove(_driverPhoneKey);
      await prefs.remove(_autoLoginKey);
      
      // Timer'ı durdur
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _isSessionActive = false;
      
      print('Session temizlendi');
    } catch (e) {
      print('Session temizleme hatası: $e');
    }
  }
  
  // Manuel çıkış (otomatik girişi de kapat)
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Sadece session bilgilerini temizle, driver bilgilerini koru
      await prefs.remove(_sessionKey);
      await prefs.remove(_lastActivityKey);
      await prefs.remove(_autoLoginKey);
      
      // Timer'ı durdur
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _isSessionActive = false;
      
      print('Şoför çıkış yaptı - Session temizlendi');
    } catch (e) {
      print('Logout hatası: $e');
    }
  }
  
  // Uygulama kapatılırken/arka plana alınırken
  static Future<void> onAppPaused() async {
    // Her zaman session'ı koru
    await _updateLastActivity();
    print('Uygulama arka plana alındı - Session korunuyor');
  }
  
  // Uygulama açılırken
  static Future<void> onAppResumed() async {
    // Session geçerliliğini kontrol et
    bool isValid = await isSessionValid();
    
    if (isValid) {
      await _updateLastActivity();
      print('Uygulama açıldı - Session geçerli');
    } else {
      print('Uygulama açıldı - Session geçersiz');
    }
  }
  
  // Session durumu
  static bool get isActive => _isSessionActive;
  
  // Servisi temizle
  static void dispose() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _isSessionActive = false;
    print('Session service temizlendi');
  }
}
