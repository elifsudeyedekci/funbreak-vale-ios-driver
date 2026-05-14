import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io'; // ✅ Platform.isIOS için gerekli!
import 'dart:math'; // ✅ Random için!
import 'package:http/http.dart' as http;
import '../services/location_service.dart';
import '../services/session_service.dart';
import '../services/advanced_notification_service.dart'; // ✅ FCM TOKEN İÇİN!

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocationService _locationService = LocationService();
  
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _error;
  String? _userEmail;
  String? _driverId;
  String? _driverName;
  String? _driverPhone;
  String? _driverPhotoUrl;
  String? _deviceId;
  
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await prefs.setString('device_id', deviceId);
    }
    _deviceId = deviceId;
    return deviceId;
  }
  
  // ✅ iOS DEBUG LOG - BACKEND'E GÖNDER!
  Future<void> _logToBackend(String message, {String level = 'INFO'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('admin_user_id') ?? prefs.getString('driver_id') ?? 'UNKNOWN';
      
      await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/log_ios_debug.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'app_name': 'VALE',
          'log_level': level,
          'message': message,
          'driver_id': driverId,
          'customer_id': '',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 2));
    } catch (e) {
      // Sessiz başarısız - log gönderme hatası ana işlemi durdurmasın!
    }
  }
  
  // ÇEVRİMİÇİ DURUM YÖNETİMİ - EKSİK FONKSİYON!
  bool _isOnline = false;
  bool _isAvailable = true;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isAuthenticated; // Eksik getter
  String? get error => _error;
  String? get userEmail => _userEmail;
  String? get driverId => _driverId;
  String? get customerId => _driverId; // Driver için customerId = driverId
  String? get driverName => _driverName;
  String? get driverPhone => _driverPhone;
  
  // ÇEVRİMİÇİ DURUM GETTER'LARI - EKSİK FONKSİYONLAR!
  bool get isOnline => _isOnline;
  bool get isAvailable => _isAvailable;
  
  // KULLANICI BİLGİLERİ GETTER - EMAIL SORUNNU ÇÖZÜLDİ!
  Map<String, dynamic>? get currentUser {
    if (_driverId == null) return null;
    
    return {
      'id': _driverId,
      'name': _driverName ?? 'Şoför',
      'surname': '', // Surname ayrı tutulmuyor, name'de birlikte
      'email': _userEmail ?? 'driver$_driverId@funbreakvale.com', // FALLBACK SABİT EMAIL
      'phone': _driverPhone ?? '',
      'photo_url': _driverPhotoUrl ?? '', // Profil foto URL'si
    };
  }
  
  // USER GETTER ALIAS - DRİVER_HOME_SCREEN İLE UYUMLU!
  Map<String, dynamic>? get user => currentUser;

  Future<bool> login({required String email, required String password}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();
      
      final deviceId = await _getOrCreateDeviceId();

      // Test kullanıcıları ve panelden eklenen şoförler için API kontrolü
      try {
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/login.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'email': email,
            'password': password,
            'type': 'driver',
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            final user = data['user'];
            
            // Session kaydet
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('admin_user_id', user['id'].toString());
            await prefs.setString('driver_id', user['id'].toString()); // FCM için eklendi!
            await prefs.setString('user_email', user['email']);
            await prefs.setString('user_name', user['name']);
            await prefs.setString('user_phone', user['phone'] ?? '05555555555');
            await prefs.setBool('is_logged_in', true);

            final panelStatus = (user['status'] ?? 'active').toString().toLowerCase().trim();
            await prefs.setString('driver_membership_status', panelStatus);
            final accountActive = panelStatus == 'active';

            _isAuthenticated = true;
            _userEmail = user['email'];
            _driverId = user['id'].toString();
            _driverName = user['name'];
            _driverPhone = user['phone'] ?? '05555555555';
            
            // SessionService ile oturum kaydet (otomatik çıkışı engelle)
            await SessionService.saveDriverLogin(
              driverId: _driverId!,
              driverName: _driverName!,
              driverPhone: _driverPhone!,
              driverEmail: _userEmail!, // EMAIL PARAMETRES İ EKLENDİ!
              enableAutoLogin: true,
            );
            
            if (accountActive) {
              // Şoförü online yap
              print('📍 LOGİN: update_driver_status çağrılıyor...');
              await _updateDriverStatus(true);
              print('✅ LOGİN: update_driver_status tamamlandı');
              
              // Konum takibini başlat
              print('📍 LOGİN: Location tracking başlatılıyor...');
              _locationService.startLocationTracking();
              print('✅ LOGİN: Location tracking başladı');
            } else {
              await prefs.setBool('is_online', false);
              await prefs.setBool('is_available', false);
              await prefs.setBool('driver_is_online', false);
              _isOnline = false;
              _isAvailable = false;
              await _updateDriverStatus(false);
              print('⛔ LOGİN: Hesap pasif — çevrimiçi / konum takibi başlatılmadı');
            }
            
            // ✅ ÇOKLU OTURUM: Eski cihazları logout yap
            try {
              await http.post(
                Uri.parse('https://admin.funbreakvale.com/api/logout_other_devices.php'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({'user_id': _driverId, 'device_id': deviceId, 'user_type': 'driver'}),
              ).timeout(const Duration(seconds: 5));
              print('✅ ÇOKLU OTURUM: Eski cihazlar logout yapıldı');
            } catch (e) {
              print('⚠️ ÇOKLU OTURUM hatası (devam ediliyor): $e');
            }
            
            // ✅ LOGİN BAŞARILI - FCM TOKEN KAYDET (ARKA PLANDA - BEKLEMEDEN!)
            print('🔔🔔🔔 LOGİN: _updateFCMToken() ARKA PLANDA ÇAĞRILACAK! 🔔🔔🔔');
            _updateFCMToken().then((_) {
              print('✅ LOGİN: _updateFCMToken() TAMAMLANDI!');
            }).catchError((fcmError) {
              print('❌❌❌ LOGİN: _updateFCMToken() EXCEPTION: $fcmError ❌❌❌');
            });
            
            _isLoading = false;
            notifyListeners();
            return true;
          }
        }
      } catch (e) {
        print('API giriş hatası: $e');
      }

      // Fallback test hesabı
      if (email == 'test@driver.com' && password == '123456') {
        // Session kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        await prefs.setString('driver_id', 'test_driver_001');
        await prefs.setString('driver_name', 'Test Şoför');
        await prefs.setString('driver_phone', '05555555555');
        await prefs.setBool('is_authenticated', true);
        
        _isAuthenticated = true;
        _userEmail = email;
        _driverId = 'test_driver_001';
        _driverName = 'Test Şoför';
        _driverPhone = '05555555555';
        
        // SessionService ile oturum kaydet (otomatik çıkışı engelle)
        await SessionService.saveDriverLogin(
          driverId: _driverId!,
          driverName: _driverName!,
          driverPhone: _driverPhone!,
          enableAutoLogin: true,
        );
        
        // Şoförü online yap
        print('📍 TEST LOGİN: update_driver_status çağrılıyor...');
        await _updateDriverStatus(true);
        print('✅ TEST LOGİN: update_driver_status tamamlandı');
        
        // ✅ TEST HESABI LOGİN - FCM TOKEN KAYDET (ARKA PLANDA - BEKLEMEDEN!)
        print('🔔🔔🔔 TEST LOGİN: _updateFCMToken() ARKA PLANDA ÇAĞRILACAK! 🔔🔔🔔');
        _updateFCMToken().then((_) {
          print('✅ TEST LOGİN: _updateFCMToken() TAMAMLANDI!');
        }).catchError((fcmError) {
          print('❌❌❌ TEST LOGİN: _updateFCMToken() EXCEPTION: $fcmError ❌❌❌');
        });
        
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Firebase ile giriş yapmayı dene
      try {
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (userCredential.user != null) {
          // Admin panel API'si ile de doğrula
          try {
            final response = await http.post(
              Uri.parse('https://admin.funbreakvale.com/api/login.php'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'email': email,
                'password': password,
                'type': 'driver',
              }),
            ).timeout(const Duration(seconds: 10));

            if (response.statusCode == 200) {
              final data = json.decode(response.body);
              if (data['success'] == true) {
                _isAuthenticated = true;
                _userEmail = email;
                _driverId = data['driver_id'];
                _driverName = data['driver_name'];
                
                // Konum takibini başlat
                _locationService.startLocationTracking();
                
                _isLoading = false;
                notifyListeners();
                return true;
              }
            }
          } catch (apiError) {
            print('API hatası: $apiError');
          }

          // API çalışmıyorsa Firebase ile devam et
          _isAuthenticated = true;
          _userEmail = email;
          _driverId = userCredential.user!.uid;
          _driverName = userCredential.user!.displayName ?? 'Şoför';
          _isLoading = false;
          notifyListeners();
          return true;
        }
      } catch (firebaseError) {
        print('Firebase hatası: $firebaseError');
      }

      _error = 'Geçersiz e-posta veya şifre';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Giriş yapılırken hata oluştu: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String licensePlate,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Firebase ile kayıt ol
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Kullanıcı profilini güncelle
        await userCredential.user!.updateDisplayName(fullName);

        // Firestore'a şoför bilgilerini kaydet
        await _firestore.collection('drivers').doc(userCredential.user!.uid).set({
          'name': fullName,
          'email': email,
          'phone': phone,
          'license_plate': licensePlate,
          'rating': 5.0,
          'status': 'active',
          'total_rides': 0,
          'total_earnings': 0.0,
          'created_at': FieldValue.serverTimestamp(),
        });

        // Admin panel API'si ile de kaydet
        try {
          final response = await http.post(
            Uri.parse('https://admin.funbreakvale.com/api/driver_register.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': password,
              'full_name': fullName,
              'phone': phone,
              'license_plate': licensePlate,
            }),
          );
        } catch (e) {
          print('Admin panel API error: $e');
        }

        _isAuthenticated = true;
        _userEmail = email;
        _driverId = userCredential.user!.uid;
        _driverName = fullName;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Kayıt başarısız';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Kayıt olurken hata oluştu: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Session yükleme - FCM YOK (main.dart halleder!)
  Future<void> loadSavedSession() async {
    try {
      // SessionService ile session kontrolü yap
      final isSessionValid = await SessionService.isSessionValid();
      
      if (isSessionValid) {
        // Session geçerli ise SessionService'ten driver bilgilerini yükle
        final driverInfo = await SessionService.getDriverInfo();
        
        if (driverInfo != null) {
          _isAuthenticated = true;
          _driverId = driverInfo['driver_id'];
          _driverName = driverInfo['driver_name'];
          _driverPhone = driverInfo['driver_phone'];
          _userEmail = driverInfo['driver_email'];
          
          print('✅ Session geçerli - Otomatik giriş yapıldı: ${_driverName}');
          
          // 🔥 AUTO-LOGIN DURUMUNDA DA FCM TOKEN KAYDET!
          print('🔔 AUTO-LOGIN: FCM Token kaydediliyor...');
          _updateFCMToken().then((_) {
            print('✅ AUTO-LOGIN: FCM Token kaydedildi!');
          }).catchError((e) {
            print('⚠️ AUTO-LOGIN: FCM Token hatası: $e');
          });
          
          notifyListeners();
        } else {
          print('❌ Driver bilgileri bulunamadı');
          _isAuthenticated = false;
          notifyListeners();
        }
      } else {
        print('❌ Session geçersiz - Giriş yapılması gerekiyor');
        _isAuthenticated = false;
        notifyListeners();
      }
    } catch (e) {
      print('Session yükleme hatası: $e');
      _isAuthenticated = false;
      notifyListeners();
    }
  }

  // Auth durumunu kontrol et
  Future<void> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();
    
    await loadSavedSession();
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _auth.signOut();
      
      // Şoförü offline yap
      await _updateDriverStatus(false);
      
      // Konum takibini durdur
      _locationService.stopLocationTracking();
      
      // SessionService ile oturumu temizle
      await SessionService.logout();
      
      // Sadece auth bilgilerini temizle, session bilgilerini koru
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('driver_membership_status');
      await prefs.remove('is_authenticated');
      await prefs.remove('user_email');
      await prefs.remove('driver_id');
      await prefs.remove('driver_name');
      await prefs.remove('driver_phone');
    } catch (e) {
      print('Logout error: $e');
    }
    
    _isAuthenticated = false;
    _userEmail = null;
    _driverId = null;
    _driverName = null;
    _driverPhone = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
  
  // Şoför durumunu güncelle (online/offline)
  Future<void> _updateDriverStatus(bool isOnline) async {
    if (_driverId == null) return;
    
    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_driver_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': int.tryParse(_driverId!) ?? _driverId,
          'is_online': isOnline,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('Şoför durumu güncellendi: ${isOnline ? "Online" : "Offline"}');
        } else {
          print('Şoför durumu güncelleme hatası: ${data['message']}');
        }
      } else {
        print('Şoför durumu API hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('Şoför durumu güncelleme hatası: $e');
    }
  }

  // ÇEVRİMİÇİ DURUM TOGGLE - EKSİK FONKSİYON EKLENDİ!
  Future<void> toggleOnlineStatus() async {
    try {
      print('🔄 Çevrimiçi durum değiştiriliyor: $_isOnline → ${!_isOnline}');
      
      _isOnline = !_isOnline;
      notifyListeners();
      
      // SharedPreferences'a kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_online', _isOnline);
      await prefs.setBool('is_available', _isOnline ? _isAvailable : false); // Çevrimdışıysa müsait de değil
      
      // Location service'e bildir
      await _locationService.setOnlineStatus(_isOnline);
      
      print('✅ Çevrimiçi durum başarıyla değiştirildi: ${_isOnline ? "ÇEVRİMİÇİ" : "ÇEVRİMDIŞI"}');
      
      // Panel'e anında bildir
      await _sendStatusUpdateToPanel();
      
    } catch (e) {
      print('❌ Çevrimiçi durum değiştirme hatası: $e');
      // Hata durumunda geri al
      _isOnline = !_isOnline;
      notifyListeners();
    }
  }
  
  // MÜSAİTLİK DURUM TOGGLE
  Future<void> toggleAvailabilityStatus() async {
    try {
      if (!_isOnline) {
        print('⚠️ Çevrimdışıyken müsaitlik değiştirilemez');
        return;
      }
      
      print('🔄 Müsaitlik durumu değiştiriliyor: $_isAvailable → ${!_isAvailable}');
      
      _isAvailable = !_isAvailable;
      notifyListeners();
      
      // SharedPreferences'a kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_available', _isAvailable);
      
      // Location service'e bildir
      await _locationService.setAvailabilityStatus(_isAvailable);
      
      print('✅ Müsaitlik durumu başarıyla değiştirildi: ${_isAvailable ? "MÜSAİT" : "MEŞGUL"}');
      
      // Panel'e anında bildir
      await _sendStatusUpdateToPanel();
      
    } catch (e) {
      print('❌ Müsaitlik durum değiştirme hatası: $e');
      // Hata durumunda geri al
      _isAvailable = !_isAvailable;
      notifyListeners();
    }
  }
  
  // PANEL'E DURUM GÜNCELLEMESİ GÖNDER - KRİTİK!
  Future<void> _sendStatusUpdateToPanel() async {
    try {
      if (_driverId == null) return;
      
      print('📡 Panel durum güncellemesi gönderiliyor...');
      print('   Sürücü ID: $_driverId');
      print('   Çevrimiçi: $_isOnline');
      print('   Müsait: $_isAvailable');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_driver_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'driver_id': int.parse(_driverId!),
          'is_online': _isOnline,
          'is_available': _isAvailable,
          'last_active': DateTime.now().toIso8601String(),
          'status_update_source': 'mobile_app',
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Panel durum güncellemesi BAŞARILI!');
          print('   Panel yanıtı: ${data['message']}');
        } else {
          print('❌ Panel durum güncellemesi BAŞARISIZ: ${data['message']}');
        }
      } else {
        print('❌ Panel durum API HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Panel durum güncelleme hatası: $e');
    }
  }
  
  // UYGULAMA BAŞLARKEN DURUM YÜKLE
  Future<void> loadSavedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isOnline = prefs.getBool('is_online') ?? false;
      _isAvailable = prefs.getBool('is_available') ?? true;
      
      // Kayıtlı profil fotoğrafını da yükle
      _driverPhotoUrl = prefs.getString('driver_photo_url');
      
      print('📱 Kayıtlı durum yüklendi: Çevrimiçi=$_isOnline, Müsait=$_isAvailable');
      if (_driverPhotoUrl != null) {
        print('📸 Kayıtlı profil fotoğrafı: $_driverPhotoUrl');
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ Kayıtlı durum yükleme hatası: $e');
    }
  }
  
  // SÜRÜCÜ FOTOĞRAF GÜNCELLEME - KALICI KAYIT!
  Future<void> updateDriverPhoto(String photoUrl) async {
    try {
      _driverPhotoUrl = photoUrl;
      
      // SharedPreferences'a kaydet - kalıcı olsun
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_photo_url', photoUrl);
      
      print('📸 Sürücü profil fotoğrafı güncellendi: $photoUrl');
      notifyListeners();
      
    } catch (e) {
      print('❌ Profil fotoğrafı güncelleme hatası: $e');
    }
  }
  
  // ✅ FCM TOKEN GÜNCELLEME - LOGIN SONRASI OTOMATIK ÇAĞRILIR!
  // 🔥 V2.0 - RATE LIMIT SORUNU ÇÖZÜLDÜ!
  Future<void> _updateFCMToken() async {
    print('🔔 iOS VALE: _updateFCMToken() - V2.0 (Rate Limit Fix)');
    
    try {
      // Driver ID'yi al
      final prefs = await SharedPreferences.getInstance();
      final driverIdStr = prefs.getString('admin_user_id') ?? 
                          prefs.getString('driver_id');
      
      if (driverIdStr == null || driverIdStr.isEmpty) {
        print('❌ FCM: Driver ID bulunamadı - token kaydedilemedi');
        return;
      }
      
      final driverId = int.tryParse(driverIdStr);
      if (driverId == null || driverId <= 0) {
        print('❌ FCM: Geçersiz Driver ID: $driverIdStr');
        return;
      }
      
      print('🔔 FCM: Token kaydediliyor - Driver ID: $driverId');
      
      // 🔥 YENİ: registerFcmToken() kullan - TEK DENEME, RATE LIMIT YOK!
      final success = await AdvancedNotificationService.registerFcmToken(
        driverId, 
        userType: 'driver',
      );
      
      if (success) {
        print('✅ FCM Token başarıyla kaydedildi!');
      } else {
        print('⚠️ FCM Token kaydedilemedi (ama uygulama çalışmaya devam edecek)');
      }
    } catch (e) {
      print('⚠️ FCM Token güncelleme hatası: $e');
    }
  }
} 