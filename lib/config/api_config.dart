// 🔥 MERKEZİ API KONFİGÜRASYONU - SÜRÜCÜ UYGULAMASI
// Tüm API URL'leri buradan yönetilir
class ApiConfig {
  // ⚠️ SERVER URL DEĞİŞTİRMEK İÇİN SADECE BU SABİTİ GÜNCELLE!
  static const String baseUrl = 'https://admin.funbreakvale.com';
  
  // API endpoint'leri
  static const String apiPath = '/api';
  static String get apiUrl => '$baseUrl$apiPath';
  
  // Yaygın API endpoint'leri
  static String get getRideMessages => '$apiUrl/get_ride_messages.php';
  static String get sendRideMessage => '$apiUrl/send_ride_message.php';
  static String get getDriverEarningsReport => '$apiUrl/get_driver_earnings_report.php';
  static String get getPushNotifications => '$apiUrl/get_push_notifications.php';
  static String get getDriverRatings => '$apiUrl/get_driver_ratings.php';
  static String get getDriverDetails => '$apiUrl/get_driver_details.php';
  static String get getDriverAnnouncements => '$apiUrl/get_driver_announcements.php';
  static String get getDriverPhoto => '$apiUrl/get_driver_photo.php';
  static String get uploadDriverPhoto => '$apiUrl/upload_driver_photo.php';
  static String get getPricingSettings => '$apiUrl/get_pricing_settings.php';
  static String get getHourlyPackages => '$apiUrl/get_hourly_packages.php';
  static String get getPricingInfo => '$apiUrl/get_pricing_info.php';
  static String get getCustomerDetails => '$apiUrl/get_customer_details.php';
  static String get checkDriverActiveRide => '$apiUrl/check_driver_active_ride.php';
  static String get updateRideRealtimeData => '$apiUrl/update_ride_realtime_data.php';
  static String get updateFcmToken => '$apiUrl/update_fcm_token.php';
  static String get sendAdvancedNotification => '$apiUrl/send_advanced_notification.php';
  static String get getNotificationHistory => '$apiUrl/get_notification_history.php';
  
  // Panel base URL
  static String get panelUrl => baseUrl;
  
  // Debug/logging
  static void printConfig() {
    print('🌐 === API KONFİGÜRASYONU (SÜRÜCÜ) ===');
    print('   Base URL: $baseUrl');
    print('   API URL: $apiUrl');
    print('   Panel URL: $panelUrl');
  }
}
