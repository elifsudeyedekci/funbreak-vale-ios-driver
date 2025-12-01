import 'dart:convert';
import 'package:http/http.dart' as http;

class DynamicContactService {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  static String getSupportPhone() {
    return '0533 448 82 53';
  }
  
  static String getSupportEmail() {
    return 'info@funbreakvale.com';
  }
  
  static String getWhatsAppNumber() {
    return '0533 448 82 53';
  }
  
  static Future<void> initialize() async {
    // Basit servis, initialize gerekmez
    print('✅ DynamicContactService hazır');
  }
  
  static Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_support_phone.php'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'support_phone': data['support_phone'] ?? getSupportPhone(),
            'support_email': getSupportEmail(),
            'whatsapp': getWhatsAppNumber(),
          };
        }
      }
    } catch (e) {
      print('❌ DynamicContactService hata: $e');
    }
    
    return {
      'support_phone': getSupportPhone(),
      'support_email': getSupportEmail(),
      'whatsapp': getWhatsAppNumber(),
    };
  }
}

