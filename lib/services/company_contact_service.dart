import 'package:http/http.dart' as http;
import 'dart:convert';

class CompanyContactService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static Map<String, dynamic>? _cachedContacts;
  static DateTime? _lastFetch;
  static const Duration cacheTimeout = Duration(minutes: 5);
  
  // Panel'den şirket iletişim bilgilerini çek (sürücü versiyonu)
  static Future<Map<String, dynamic>?> getCompanyContacts() async {
    try {
      // Cache kontrol
      if (_cachedContacts != null && _lastFetch != null) {
        if (DateTime.now().difference(_lastFetch!) < cacheTimeout) {
          print('📞 [ŞOFÖR] Company contacts cache\'den alındı');
          return _cachedContacts;
        }
      }
      
      print('📞 [ŞOFÖR] Company contacts API\'den çekiliyor...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_system_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _cachedContacts = {
            'support_phone': data['settings']['support_phone'] ?? '+90 555 123 45 67',
            'contact_phone': data['settings']['contact_phone'] ?? '+90 555 123 45 67',
            'emergency_phone': data['settings']['emergency_phone'] ?? '+90 555 123 45 67',
            'company_name': data['settings']['app_name'] ?? 'FunBreak Vale',
            'driver_support_phone': data['settings']['driver_support_phone'] ?? data['settings']['support_phone'],
          };
          _lastFetch = DateTime.now();
          
          print('✅ [ŞOFÖR] Company contacts başarıyla alındı');
          return _cachedContacts;
        }
      }
      
      print('❌ [ŞOFÖR] Company contacts alınamadı: ${response.statusCode}');
      return null;
      
    } catch (e) {
      print('❌ [ŞOFÖR] Company contacts hatası: $e');
      return null;
    }
  }
  
  // Şoför için şirket arama seçenekleri
  static Future<List<Map<String, String>>> getDriverCallOptions() async {
    final contacts = await getCompanyContacts();
    
    if (contacts == null) {
      // Fallback değerler
      return [
        {
          'title': '🏢 Şirket Merkezi',
          'subtitle': 'Şoför destek hattı',
          'phone': '+90 555 123 45 67',
          'type': 'driver_support',
          'icon': 'business',
        },
        {
          'title': '🚨 Acil Durum',
          'subtitle': '7/24 acil destek',
          'phone': '+90 555 123 45 67',
          'type': 'emergency',
          'icon': 'emergency',
        },
      ];
    }
    
    return [
      {
        'title': '🏢 ${contacts['company_name']} Merkezi',
        'subtitle': 'Şoför operasyon hattı',
        'phone': contacts['driver_support_phone'] ?? contacts['support_phone'],
        'type': 'driver_support',
        'icon': 'business',
      },
      {
        'title': '📞 Destek Hattı',
        'subtitle': 'Teknik destek',
        'phone': contacts['support_phone'],
        'type': 'technical_support',
        'icon': 'support',
      },
      {
        'title': '🚨 Acil Durum Hattı',
        'subtitle': '7/24 acil yardım',
        'phone': contacts['emergency_phone'] ?? contacts['support_phone'],
        'type': 'emergency',
        'icon': 'emergency',
      },
    ];
  }
  
  // Cache temizle
  static void clearCache() {
    _cachedContacts = null;
    _lastFetch = null;
    print('📞 [ŞOFÖR] Company contacts cache temizlendi');
  }
}
