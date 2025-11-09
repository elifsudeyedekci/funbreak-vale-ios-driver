class AppConstants {
  // Colors
  static const int primaryColor = 0xFFFFD700; // Golden yellow
  static const int secondaryColor = 0xFF000000; // Black
  
  // Firebase Collections
  static const String customersCollection = 'customers';
  static const String driversCollection = 'drivers';
  static const String ridesCollection = 'rides';
  static const String pricingPackagesCollection = 'pricing_packages';
  static const String settingsCollection = 'settings';
  
  // Ride Status
  static const String rideStatusPending = 'pending';
  static const String rideStatusAccepted = 'accepted';
  static const String rideStatusArrived = 'arrived';
  static const String rideStatusStarted = 'started';
  static const String rideStatusWaiting = 'waiting';
  static const String rideStatusCompleted = 'completed';
  static const String rideStatusCancelled = 'cancelled';
  
  // Pricing
  static const double defaultBaseFare = 15.0;
  static const double defaultPerKmRate = 2.5;
  static const double defaultPerHourRate = 30.0;
  static const double defaultCommissionRate = 0.15; // 15%
  
  // Waiting Fees
  static const double defaultFreeMinutes = 15.0;
  static const double defaultFeePer15Minutes = 100.0;
  
  // Night Package
  static const int defaultMinHoursForNightPackage = 2;
  static const double defaultNightPackageMultiplier = 1.5;
  
  // UI
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 8.0;
  static const double defaultIconSize = 24.0;
  
  // Validation
  static const int minPasswordLength = 6;
  static const int maxPhoneLength = 15;
  static const int maxNameLength = 50;
  
  // Error Messages
  static const String errorInvalidEmail = 'Geçerli bir e-posta girin';
  static const String errorInvalidPassword = 'Şifre en az 6 karakter olmalı';
  static const String errorInvalidPhone = 'Geçerli bir telefon numarası girin';
  static const String errorInvalidName = 'Geçerli bir ad soyad girin';
  static const String errorInvalidLicensePlate = 'Geçerli bir plaka girin';
  static const String errorNetworkConnection = 'İnternet bağlantısı hatası';
  static const String errorUnknown = 'Bilinmeyen bir hata oluştu';
  
  // Success Messages
  static const String successLogin = 'Giriş başarılı';
  static const String successRegister = 'Kayıt başarılı';
  static const String successRideAccepted = 'Yolculuk kabul edildi';
  static const String successRideStarted = 'Yolculuk başlatıldı';
  static const String successRideCompleted = 'Yolculuk tamamlandı';
  static const String successWaitingStarted = 'Bekleme başlatıldı';
  static const String successWaitingStopped = 'Bekleme durduruldu';
  
  // Loading Messages
  static const String loadingLogin = 'Giriş yapılıyor...';
  static const String loadingRegister = 'Kayıt yapılıyor...';
  static const String loadingRideAcceptance = 'Yolculuk kabul ediliyor...';
  static const String loadingRideStart = 'Yolculuk başlatılıyor...';
  static const String loadingRideCompletion = 'Yolculuk tamamlanıyor...';
  static const String loadingWaitingStart = 'Bekleme başlatılıyor...';
  static const String loadingWaitingStop = 'Bekleme durduruluyor...';
} 