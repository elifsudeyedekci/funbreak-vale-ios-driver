import 'package:shared_preferences/shared_preferences.dart';

/// Sürücü oturumundaki sayısal kullanıcı kimliği (API `user_id`).
///
/// Önce **string** kimlikler (`admin_user_id`, `driver_id`) — `login.php` her zaman
/// `admin_user_id` yazar; bazı cihazlarda eski/yanlış `driver_id` **int** değeri
/// string oturumun önüne geçmesin diye int okuma en sonda.
int readDriverNumericUserId(SharedPreferences prefs) {
  for (final raw in [prefs.getString('admin_user_id'), prefs.getString('driver_id')]) {
    if (raw != null && raw.trim().isNotEmpty) {
      final v = int.tryParse(raw.trim());
      if (v != null && v > 0) return v;
    }
  }
  final adminInt = prefs.getInt('admin_user_id');
  if (adminInt != null && adminInt > 0) return adminInt;
  final driverInt = prefs.getInt('driver_id');
  if (driverInt != null && driverInt > 0) return driverInt;
  return 0;
}
