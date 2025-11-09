import 'dart:convert';
import 'package:http/http.dart' as http;

// SÜRÜCÜ İÇİN DİNAMİK İLETİŞİM BİLGİLERİ SERVİSİ - PANEL ENTEGRE!
class DynamicContactService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  static Map<String, dynamic>? _cachedSettings;
  static DateTime? _lastFetchTime;
  static const Duration cacheDuration = Duration(seconds: 30); // 30 saniye cache - anlık çekme

  // SİSTEM AYARLARINI ÇEK (CACHE İLE)
  static Future<Map<String, dynamic>> getSystemSettings() async {
    // Cache kontrol
    if (_cachedSettings != null && 
        _lastFetchTime != null && 
        DateTime.now().difference(_lastFetchTime!) < cacheDuration) {
      print('🚛 SÜRÜCÜ: Cached sistem ayarları kullanılıyor');
      return _cachedSettings!;
    }

    try {
      print('🔄 SÜRÜCÜ: Panel sistem ayarları çekiliyor...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/get_system_settings.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['settings'] != null) {
          _cachedSettings = data['settings'];
          _lastFetchTime = DateTime.now();
          
          print('✅ SÜRÜCÜ sistem ayarları başarıyla çekildi:');
          print('   📞 Telefon: ${getSupportPhone()}');
          print('   📧 Email: ${getSupportEmail()}');
          print('   💬 WhatsApp: ${getWhatsAppNumber()}');
          
          return _cachedSettings!;
        }
      }
      
      print('⚠️ SÜRÜCÜ: Panel ayarları çekilemedi - varsayılan değerler kullanılıyor');
      return _getDefaultSettings();
      
    } catch (e) {
      print('❌ SÜRÜCÜ: Panel ayarları çekme hatası: $e');
      return _getDefaultSettings();
    }
  }

  // SÜRÜCÜ DESTEK TELEFON NUMARASI
  static String getSupportPhone() {
    if (_cachedSettings != null && 
        _cachedSettings!['support_phone'] != null) {
      final phone = _cachedSettings!['support_phone'].toString();
      print('✅ SÜRÜCÜ Destek telefonu panelden alındı: $phone');
      return phone;
    }
    print('⚠️ SÜRÜCÜ Destek telefonu panelden alınamadı, varsayılan kullanılıyor');
    return '05555555555'; // Müşteri app ile aynı varsayılan
  }

  // SÜRÜCÜ DESTEK EMAIL - API FORMAT FIX!
  static String getSupportEmail() {
    if (_cachedSettings != null && 
        _cachedSettings!['support_email'] != null) {
      // API direkt string döndürüyor, ['value'] yok!
      return _cachedSettings!['support_email'].toString();
    }
    return 'destek@funbreakvale.com'; // Varsayılan
  }

  // SÜRÜCÜ WHATSAPP NUMARASI - DESTEK TELEFONU İLE AYNI
  static String getWhatsAppNumber() {
    if (_cachedSettings != null) {
      // Önce destek telefonunu kullan (aynı numara olsun)
      final supportPhone = _cachedSettings!['support_phone']?.toString();
      final whatsappNum = _cachedSettings!['whatsapp_number']?.toString();
      final supportWhatsapp = _cachedSettings!['support_whatsapp']?.toString();
      
      if (supportPhone != null && supportPhone.isNotEmpty) {
        print('✅ SÜRÜCÜ WhatsApp destek telefonu ile aynı: $supportPhone');
        return supportPhone;
      } else if (whatsappNum != null && whatsappNum.isNotEmpty) {
        print('✅ SÜRÜCÜ WhatsApp panelden alındı: $whatsappNum');
        return whatsappNum;
      } else if (supportWhatsapp != null && supportWhatsapp.isNotEmpty) {
        print('✅ DRIVER WhatsApp from support_whatsapp: $supportWhatsapp');
        return supportWhatsapp;
      }
    }
    print('⚠️ SÜRÜCÜ WhatsApp panelden alınamadı, varsayılan kullanılıyor');
    return '05555555555'; // Müşteri app ile aynı varsayılan
  }

  // ŞİRKET ADI - API FORMAT FIX!
  static String getCompanyName() {
    if (_cachedSettings != null && 
        _cachedSettings!['company_name'] != null) {
      // API direkt string döndürüyor, ['value'] yok!
      return _cachedSettings!['company_name'].toString();
    }
    return 'FunBreak Vale Teknoloji'; // Varsayılan
  }

  // VARSAYILAN AYARLAR - MÜŞTERİ APP İLE TUTARLI!
  static Map<String, dynamic> _getDefaultSettings() {
    return {
      'support_phone': '05555555555',
      'support_email': 'destek@funbreakvale.com',
      'whatsapp_number': '05555555555',
      'support_whatsapp': '05555555555',
      'company_name': 'FunBreak Vale',
      'app_name': 'FunBreak Vale Driver',
    };
  }

  // TELEFON ARAMA URL
  static String getPhoneUrl() {
    return 'tel:${getSupportPhone()}';
  }

  // EMAIL URL
  static String getEmailUrl({String? subject, String? body}) {
    String url = 'mailto:${getSupportEmail()}';
    
    List<String> params = [];
    if (subject != null) params.add('subject=${Uri.encodeComponent(subject)}');
    if (body != null) params.add('body=${Uri.encodeComponent(body)}');
    
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    
    return url;
  }

  // WHATSAPP URL
  static String getWhatsAppUrl({String? message}) {
    String phone = getWhatsAppNumber().replaceAll(RegExp(r'[^\d]'), '');
    if (phone.startsWith('0')) {
      phone = '90${phone.substring(1)}'; // Türkiye kodu ekle
    }
    
    String url = 'https://wa.me/$phone';
    if (message != null) {
      url += '?text=${Uri.encodeComponent(message)}';
    }
    
    return url;
  }

  // CACHE TEMİZLE
  static void clearCache() {
    _cachedSettings = null;
    _lastFetchTime = null;
    print('🗑️ SÜRÜCÜ: İletişim cache temizlendi');
  }

  // INIT
  static Future<void> initialize() async {
    print('🚀 SÜRÜCÜ: Dinamik iletişim servisi başlatılıyor...');
    await getSystemSettings();
    print('✅ SÜRÜCÜ: Dinamik iletişim servisi hazır!');
  }
}
