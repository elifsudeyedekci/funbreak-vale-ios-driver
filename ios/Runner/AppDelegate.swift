import Flutter
import UIKit
import Firebase  // ⚠️ Firebase import!
import GoogleMaps  // ⚠️ Google Maps import!

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // ⚠️ Firebase initialization
    FirebaseApp.configure()
    print("✅ Firebase configured in iOS (ŞOFÖR)")
    
    // ⚠️ Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY")
    print("✅ Google Maps configured in iOS (ŞOFÖR)")
    
    // Flutter plugin registration
    GeneratedPluginRegistrant.register(with: self)
    
    // ⚠️ Push notification setup (iOS 10+)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
      print("✅ UNUserNotificationCenter delegate set (ŞOFÖR)")
    }
    
    // ⚠️ Background fetch için minimum interval ayarla (Sürücü her zaman aktif!)
    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // ⚠️ APNs Device Token Registration
  override func application(_ application: UIApplication, 
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    
    // APNs token'ı Firebase'e gönder
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("📱 ŞOFÖR APNs Device Token: \(token)")
    
    // Firebase Messaging'e token kaydet
    #if canImport(FirebaseMessaging)
    Messaging.messaging().apnsToken = deviceToken
    #endif
  }
  
  // ⚠️ APNs Registration Failure
  override func application(_ application: UIApplication, 
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ ŞOFÖR Failed to register for remote notifications: \(error)")
  }
  
  // ⚠️ Background Fetch (Sürücü için önemli - her zaman konum güncelleme)
  override func application(_ application: UIApplication, 
                            performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📦 ŞOFÖR Background fetch triggered - konum güncelleniyor...")
    completionHandler(.newData)
  }
}

