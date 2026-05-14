import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Yasal onay kaydı — müşteri uygulaması [contract_update_screen] ile **aynı** HTTP sözleşmesi:
/// - `POST` + yalnızca `Content-Type: application/json`
/// - [register_screen] / güncelleme ekranındaki ile aynı JSON anahtarları (ekstra `driver_id` / model yok)
/// - Timeout: müşteri ekranı 10 sn; sürücü tam metinleri çok daha büyük → **45 sn**.
class LegalConsentLogService {
  LegalConsentLogService._();

  /// Müşteri `contract_update_screen.dart` satır 458–479 ile aynı (sadece süre uzun).
  static const Duration requestTimeout = Duration(seconds: 45);

  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
  };

  /// Müşteri `contract_update_screen._collectDeviceInfo` ile aynı yapı (6 alan).
  static Map<String, dynamic> buildDeviceInfo({
    required int userId,
    required bool isDriver,
    String appVersion = '4.0.0',
  }) {
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
    final tag = isDriver ? 'driver' : 'customer';
    final fingerprint =
        DateTime.now().millisecondsSinceEpoch.toString() + '_' + tag + '_' + userId.toString();

    return {
      'platform': platform,
      'os_version': Platform.operatingSystemVersion,
      'app_version': appVersion,
      'device_fingerprint': fingerprint,
      'user_agent': isDriver
          ? 'FunBreak Vale Driver/$platform ${Platform.operatingSystemVersion}'
          : 'FunBreak Vale Customer/$platform ${Platform.operatingSystemVersion}',
      'ip_address': 'auto',
    };
  }

  /// Sunucuya tek bir onay kaydı gönderir; yanıt map’i döner (`success`, `message`, `log_id` …).
  static Future<Map<String, dynamic>> postLegalConsent({
    required int userId,
    required String userType,
    required String consentType,
    required String consentText,
    required String consentSummary,
    required String consentVersion,
    required Map<String, dynamic> deviceInfo,
    Position? position,
  }) async {
    final uri = Uri.parse(ApiConfig.logLegalConsent);
    final body = jsonEncode({
      'user_id': userId,
      'user_type': userType,
      'consent_type': consentType,
      'consent_text': consentText,
      'consent_summary': consentSummary,
      'consent_version': consentVersion,
      'ip_address': deviceInfo['ip_address'],
      'user_agent': deviceInfo['user_agent'],
      'device_fingerprint': deviceInfo['device_fingerprint'],
      'platform': deviceInfo['platform'],
      'os_version': deviceInfo['os_version'],
      'app_version': deviceInfo['app_version'],
      'latitude': position?.latitude,
      'longitude': position?.longitude,
      'location_accuracy': position?.accuracy,
      'language': 'tr',
    });

    print(
      '📝 SÖZLEŞME LOG (müşteri ile aynı istek gövdesi): $consentType user=$userId type=$userType textLen=${consentText.length}',
    );

    final response =
        await http.post(uri, headers: jsonHeaders, body: body).timeout(requestTimeout);

    final preview = response.body.length > 400 ? '${response.body.substring(0, 400)}…' : response.body;
    print('📡 SÖZLEŞME LOG yanıt: HTTP ${response.statusCode} $preview');

    if (response.statusCode != 200) {
      return {'success': false, 'message': 'HTTP ${response.statusCode}'};
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return {'success': false, 'message': 'Geçersiz JSON yanıtı'};
      }
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      return {'success': false, 'message': 'JSON ayrıştırma: $e'};
    }
  }
}
