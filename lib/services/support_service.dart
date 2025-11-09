import 'dart:convert';
import 'package:http/http.dart' as http;

class SupportService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static Map<String, String>? _cachedSupport;
  static DateTime? _lastFetch;
  
  // Cache süresi (10 dakika)
  static const Duration cacheTimeout = Duration(minutes: 10);
  
  static Future<Map<String, String>> getSupportInfo() async {
    try {
      // Cache kontrolü
      if (_cachedSupport != null && _lastFetch != null) {
        if (DateTime.now().difference(_lastFetch!) < cacheTimeout) {
          print('Şoför - Support info cache\'den alındı');
          return _cachedSupport!;
        }
      }
      
      print('Şoför - Support info API\'den çekiliyor...');
      final response = await http.get(
        Uri.parse('$baseUrl/get_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final settings = data['data'] as Map<String, dynamic>;
          
          // Destek bilgilerini çıkar
          String phone = _getSupportPhone(settings);
          String email = _getSupportEmail(settings);
          String appName = settings['app_name'] ?? 'FunBreak Vale Driver';
          
          _cachedSupport = {
            'phone': phone,
            'email': email,
            'app_name': appName,
          };
          
          _lastFetch = DateTime.now();
          print('Şoför - Support info güncellendi: $phone, $email');
          return _cachedSupport!;
        }
      }
      
      print('Şoför - Support info alınamadı, varsayılan değerler kullanılıyor');
      return _getDefaultSupportInfo();
      
    } catch (e) {
      print('Şoför - Support info hatası: $e');
      return _getDefaultSupportInfo();
    }
  }
  
  // Destek telefonu al (alternatif field'ları kontrol et)
  static String _getSupportPhone(Map<String, dynamic> settings) {
    List<String> phoneFields = [
      'support_phone',
      'contact_phone', 
      'phone'
    ];
    
    for (String field in phoneFields) {
      String? phone = settings[field]?.toString();
      if (phone != null && phone.isNotEmpty && phone != 'null') {
        return phone;
      }
    }
    
    return '+90 555 123 4567'; // Varsayılan
  }
  
  // Destek e-postası al (alternatif field'ları kontrol et)
  static String _getSupportEmail(Map<String, dynamic> settings) {
    List<String> emailFields = [
      'support_email',
      'contact_email',
      'email'
    ];
    
    for (String field in emailFields) {
      String? email = settings[field]?.toString();
      if (email != null && email.isNotEmpty && email != 'null') {
        return email;
      }
    }
    
    return 'destek@funbreakvale.com'; // Varsayılan
  }
  
  // Varsayılan destek bilgileri
  static Map<String, String> _getDefaultSupportInfo() {
    return {
      'phone': '+90 555 123 4567',
      'email': 'destek@funbreakvale.com',
      'app_name': 'FunBreak Vale Driver',
    };
  }
  
  // Telefon numarasını al
  static Future<String> getSupportPhone() async {
    final info = await getSupportInfo();
    return info['phone'] ?? '+90 555 123 4567';
  }
  
  // E-posta adresini al
  static Future<String> getSupportEmail() async {
    final info = await getSupportInfo();
    return info['email'] ?? 'destek@funbreakvale.com';
  }
  
  // Uygulama adını al
  static Future<String> getAppName() async {
    final info = await getSupportInfo();
    return info['app_name'] ?? 'FunBreak Vale Driver';
  }
  
  // Cache'i temizle (ayarlar değiştiğinde)
  static void clearCache() {
    _cachedSupport = null;
    _lastFetch = null;
    print('Şoför - Support info cache temizlendi');
  }
  
  // Cache'i zorla yenile
  static Future<Map<String, String>> refreshSupportInfo() async {
    clearCache();
    return await getSupportInfo();
  }
}
