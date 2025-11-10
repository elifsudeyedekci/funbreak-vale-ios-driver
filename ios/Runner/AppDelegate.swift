import Flutter
import UIKit
import Firebase  // ⚠️ Firebase import!
import FirebaseMessaging  // ⚠️ Firebase Messaging import!
import GoogleMaps  // ⚠️ Google Maps import!

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // ⚠️ Firebase initialization - NATIVE iOS tarafında configure ediyoruz!
    FirebaseApp.configure()
    print("✅ Firebase configured in iOS (native - ŞOFÖR)")
    
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
  
  // ⚠️ APNs Device Token Registration
  override func application(_ application: UIApplication, 
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    
    // APNs token'ı Firebase Messaging'e kaydet
    Messaging.messaging().apnsToken = deviceToken
    
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("📱 ŞOFÖR APNs Device Token registered: \(token.prefix(20))...")
    print("✅ APNs token Firebase'e kaydedildi (ŞOFÖR)")
  }
  
  // ⚠️ APNs Registration Failure
  override func application(_ application: UIApplication, 
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error)")
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
}
