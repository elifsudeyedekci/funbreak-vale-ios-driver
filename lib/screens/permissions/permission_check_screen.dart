import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io'; // Platform kontrolü için

class PermissionCheckScreen extends StatefulWidget {
  final VoidCallback? onPermissionsGranted;
  
  const PermissionCheckScreen({Key? key, this.onPermissionsGranted}) : super(key: key);

  @override
  State<PermissionCheckScreen> createState() => _PermissionCheckScreenState();
}

class _PermissionCheckScreenState extends State<PermissionCheckScreen> {
  bool _locationAlwaysGranted = false;
  bool _backgroundAppGranted = false;
  bool _notificationGranted = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkAllPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD700),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Header
              Text(
                'İzin Kontrolleri',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'FunBreak Vale\'nin düzgün çalışması için gerekli izinler',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 40),
              
              Expanded(
                child: Column(
                  children: [
                    // 1. Konum İzni "Her Zaman"
                    _buildPermissionCard(
                      icon: Icons.location_on,
                      title: 'Konum İzni "Her Zaman"',
                      description: 'Vale takibi için konum izninizin "Her zaman izin ver" olarak ayarlanması gerekiyor.',
                      isGranted: _locationAlwaysGranted,
                      onTap: _requestLocationAlwaysPermission,
                      criticalText: 'ZORUNLU: Uygulama çalışmaz!',
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 2. Arka Plan İzni  
                    _buildPermissionCard(
                      icon: Icons.apps,
                      title: 'Arka Plan Uygulaması İzni',
                      description: 'Arka planda talep alabilmek için "Kısıtlanmamış" arka plan izni gerekiyor.',
                      isGranted: _backgroundAppGranted,
                      onTap: _requestBackgroundPermission,
                      criticalText: 'ZORUNLU: Arka plan çalışmaz!',
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 3. Bildirim İzni
                    _buildPermissionCard(
                      icon: Icons.notifications,
                      title: 'Bildirim İzni',
                      description: 'Yeni talepleri bildirim olarak alabilmek için gerekli.',
                      isGranted: _notificationGranted,
                      onTap: _requestNotificationPermission,
                      criticalText: 'ÖNEMLİ: Talep bildirimleri',
                    ),
                  ],
                ),
              ),
              
              // Continue Button
              if (_allPermissionsGranted()) ...[
                Container(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      if (widget.onPermissionsGranted != null) {
                        widget.onPermissionsGranted!();
                      }
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFFFD700),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Devam Et ✅',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      'Tüm izinler gerekli!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Refresh Button
              TextButton(
                onPressed: _isChecking ? null : _checkAllPermissions,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isChecking) ...[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(Icons.refresh, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'İzinleri Yeniden Kontrol Et',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onTap,
    required String criticalText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isGranted ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isGranted ? Colors.green : Colors.red,
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    
                    Text(
                      criticalText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isGranted ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isGranted ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isGranted ? Icons.check : Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          
          if (!isGranted) ...[
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'İzin Ver',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _isChecking = true);
    
    try {
      // 1. Konum İzni "Her Zaman" Kontrol
      LocationPermission locationPermission = await Geolocator.checkPermission();
      _locationAlwaysGranted = (locationPermission == LocationPermission.always);
      
      print('📍 Konum İzni Durumu: $locationPermission');
      print('   Her Zaman İzin: ${_locationAlwaysGranted ? "VAR" : "YOK"}');
      
      // 2. Arka Plan İzni Kontrol (Platform-Specific!)
      if (Platform.isAndroid) {
        var backgroundStatus = await Permission.ignoreBatteryOptimizations.status;
        _backgroundAppGranted = backgroundStatus.isGranted;
        print('📱 Android Arka Plan İzni: $backgroundStatus');
        print('   Pil Optimizasyonu İgnore: ${_backgroundAppGranted ? "VAR" : "YOK"}');
      } else if (Platform.isIOS) {
        // iOS'te arka planda yenileme Info.plist'te zaten var (UIBackgroundModes)
        // Kullanıcı Settings'te aktif etmesi gerekiyor
        _backgroundAppGranted = true; // iOS için varsayılan true, Settings'te kontrol et deriz
        print('📱 iOS Arka Planda Yenileme: Settings → Genel → Arka Planda Yenileme → FunBreak Vale → Aç');
      
      // 3. Bildirim İzni Kontrol
      var notificationStatus = await Permission.notification.status;
      _notificationGranted = notificationStatus.isGranted;
      
      print('🔔 Bildirim İzni Durumu: $notificationStatus');
      print('   Bildirim İzni: ${_notificationGranted ? "VAR" : "YOK"}');
      
    } catch (e) {
      print('❌ İzin kontrol hatası: $e');
    }
    
    setState(() => _isChecking = false);
  }

  bool _allPermissionsGranted() {
    return _locationAlwaysGranted && _backgroundAppGranted && _notificationGranted;
  }

  Future<void> _requestLocationAlwaysPermission() async {
    try {
      print('📍 KONUM İZNİ "HER ZAMAN" İSTENİYOR...');
      
      // Önce normal konum izni iste
      LocationPermission permission = await Geolocator.requestPermission();
      
      if (permission == LocationPermission.denied) {
        _showLocationPermissionDialog();
        return;
      }
      
      // "Her zaman" izni için ayarlara yönlendir
      if (permission != LocationPermission.always) {
        _showLocationAlwaysDialog();
      }
      
      // İzni tekrar kontrol et
      await _checkAllPermissions();
    } catch (e) {
      print('❌ Konum izni hatası: $e');
    }
  }

  Future<void> _requestBackgroundPermission() async {
    try {
      print('📱 ARKA PLAN İZNİ İSTENİYOR...');
      
      if (Platform.isAndroid) {
        var status = await Permission.ignoreBatteryOptimizations.request();
        
        if (status.isDenied || status.isPermanentlyDenied) {
          _showBackgroundPermissionDialog();
        }
      } else if (Platform.isIOS) {
        // iOS'te Settings'e yönlendir
        _showBackgroundPermissionDialog();
      }
      
      // İzni tekrar kontrol et
      await _checkAllPermissions();
    } catch (e) {
      print('❌ Arka plan izni hatası: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      print('🔔 BİLDİRİM İZNİ İSTENİYOR...');
      
      var status = await Permission.notification.request();
      
      if (status.isDenied || status.isPermanentlyDenied) {
        _showNotificationPermissionDialog();
      }
      
      // İzni tekrar kontrol et
      await _checkAllPermissions();
    } catch (e) {
      print('❌ Bildirim izni hatası: $e');
    }
  }

  void _showLocationAlwaysDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_on, color: Color(0xFFFFD700), size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('Konum İzni "Her Zaman" Gerekli')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vale takibi için konum izninizin "HER ZAMAN İZİN VER" olarak ayarlanması zorunludur.',
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📱 Ayarlar Yolu:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Ayarlar → Uygulamalar → FunBreak Vale → İzinler → Konum → "Her zaman izin ver"'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFFD700)),
            child: Text('Ayarlara Git', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showBackgroundPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.apps, color: Color(0xFFFFD700), size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('Arka Plan İzni Gerekli')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Platform.isAndroid 
                ? 'Arka planda talep alabilmek için "Pil optimizasyonu" izninin açık olması gerekiyor.'
                : 'Arka planda talep alabilmek için "Arka Planda Yenileme" izninin açık olması gerekiyor.',
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📱 Ayarlar Yolu:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(Platform.isAndroid 
                    ? 'Ayarlar → Pil → Pil optimizasyonu → FunBreak Vale → "Kısıtlama"'
                    : 'Ayarlar → Genel → Arka Planda Yenileme → FunBreak Vale → Aç'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFFD700)),
            child: Text('Ayarlara Git', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNotificationPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications, color: Color(0xFFFFD700), size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('Bildirim İzni')),
          ],
        ),
        content: Text(
          'Yeni talep bildirimlerini alabilmek için bildirim izni gerekli.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFFD700)),
            child: Text('Ayarlara Git', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(child: Text('Konum İzni Reddedildi')),
          ],
        ),
        content: Text(
          'FunBreak Vale konum izni olmadan çalışamaz. Lütfen ayarlardan konum iznini verin.',
          style: TextStyle(fontSize: 16, height: 1.4),
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
}
