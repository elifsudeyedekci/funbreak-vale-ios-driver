import 'package:shared_preferences/shared_preferences.dart';

/// Sürücü oturumundaki sayısal kullanıcı kimliği (API `user_id`).
///
/// Uygulama genelinde `driver_id` ve `admin_user_id` farklı anahtarlarda tutulabiliyor;
/// sözleşme logu ve backend çağrıları için ikisini de dene.
int readDriverNumericUserId(SharedPreferences prefs) {
  int id = prefs.getInt('driver_id') ?? 0;
  if (id == 0) {
    final s = prefs.getString('driver_id');
    if (s != null && s.trim().isNotEmpty) {
      id = int.tryParse(s.trim()) ?? 0;
    }
  }
  if (id == 0) {
    final admin = prefs.getString('admin_user_id');
    if (admin != null && admin.trim().isNotEmpty) {
      id = int.tryParse(admin.trim()) ?? 0;
    }
  }
  if (id == 0) {
    id = prefs.getInt('admin_user_id') ?? 0;
  }
  return id;
}
