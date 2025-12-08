import Flutter
import UIKit
import Firebase  // ⚠️ Firebase import!
import FirebaseMessaging  // ⚠️ Firebase Messaging import!
import GoogleMaps  // ⚠️ Google Maps import!
import UserNotifications  // ⚠️ UserNotifications import!

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // ⚠️ Firebase initialization - FLUTTER PLUGIN KULLAN!
    // Native Firebase.configure() iOS'ta CRASH yapıyor (NSException → Swift catch yakalamıyor)
    // Flutter firebase_core plugin kendi initialize eder!
    print("📱 ŞOFÖR iOS: Firebase initialization Flutter plugin tarafından yapılacak")
    
    // ⚠️ Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY")
    print("✅ Google Maps configured in iOS")
    
    // Flutter plugin registration
    GeneratedPluginRegistrant.register(with: self)
    
    // ⚠️ Push notification setup (iOS 10+)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
      Messaging.messaging().delegate = self as MessagingDelegate
      print("✅ UNUserNotificationCenter delegate + Firebase Messaging delegate set (ŞOFÖR)")
    }
    
    // ⚠️ Push notification izni iste!
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      print("📱 ŞOFÖR Push izni: \(granted ? "✅ VERİLDİ" : "❌ REDDEDİLDİ")")
      if let error = error {
        print("❌ Push izin hatası: \(error)")
      }
    }
    
    // ⚠️ APNs registration
    application.registerForRemoteNotifications()
    
    // ⚠️ Background fetch için minimum interval ayarla
    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // ⚠️ APNs Device Token Registration - PRODUCTION TYPE!
  override func application(_ application: UIApplication, 
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    
    // 🔥 KRİTİK: APNs token'ı PRODUCTION type ile kaydet!
    // Bu embedded.mobileprovision dosyası olmadan da çalışmasını sağlar!
    // TestFlight/App Store build'lerinde mobileprovision kaldırılıyor
    #if DEBUG
    Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
    print("📱 ŞOFÖR APNs Token SANDBOX olarak kaydedildi (DEBUG)")
    #else
    Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
    print("📱 ŞOFÖR APNs Token PRODUCTION olarak kaydedildi (RELEASE)")
    #endif
    
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("📱 ŞOFÖR APNs Device Token registered: \(token.prefix(20))...")
    #if DEBUG
    print("✅ APNs token Firebase'e kaydedildi (ŞOFÖR) - Type: SANDBOX")
    #else
    print("✅ APNs token Firebase'e kaydedildi (ŞOFÖR) - Type: PRODUCTION")
    #endif
  }
  
  // ⚠️ APNs Registration Failure
  override func application(_ application: UIApplication, 
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error)")
  }
  
  // ⚠️ BACKGROUND REMOTE NOTIFICATION - UYGULAMA KAPALI/ARKA PLANDA!
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📱 === ŞOFÖR BACKGROUND REMOTE NOTIFICATION ALINDI ===")
    print("   📊 UserInfo: \(userInfo)")
    
    // Firebase Messaging'e bildir
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Flutter background handler çağrılacak
    completionHandler(.newData)
    print("✅ ŞOFÖR Background notification işlendi")
  }
  
  // ⚠️ Background Fetch
  override func application(_ application: UIApplication, 
                            performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📦 Background fetch triggered")
    completionHandler(.newData)
  }
  
  // ⚠️ MessagingDelegate - FCM Token Refresh
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("📱 ŞOFÖR FCM Token güncellendi: \(fcmToken?.prefix(20) ?? "nil")...")
    // Token'ı backend'e göndermek için kullanılabilir
  }
  
  // ⚠️ FOREGROUND BİLDİRİM HANDLER - iOS'ta bildirim göstermek için ZORUNLU!
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    
    print("🔔 iOS ŞOFÖR FOREGROUND Bildirim alındı:")
    print("   📋 Title: \(notification.request.content.title)")
    print("   💬 Body: \(notification.request.content.body)")
    print("   📊 UserInfo: \(userInfo)")
    
    // iOS 14+ için yeni presentation options
    if #available(iOS 14.0, *) {
      completionHandler([[.banner, .list, .badge, .sound]])
      print("✅ iOS 14+ ŞOFÖR Bildirim gösterilecek: banner + list + sound + badge")
    } else {
      // iOS 13 ve altı için eski options
      completionHandler([[.alert, .badge, .sound]])
      print("✅ iOS 13 ŞOFÖR Bildirim gösterilecek: alert + sound + badge")
    }
  }
  
  // ⚠️ BİLDİRİME TIKLANMA HANDLER
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    
    print("👆 iOS ŞOFÖR Bildirime tıklandı:")
    print("   📊 UserInfo: \(userInfo)")
    
    // Flutter tarafına ilet
    completionHandler()
  }
}
