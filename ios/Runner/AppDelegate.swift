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
    print("✅ Firebase configured in iOS")
    
    // ⚠️ Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY")
    print("✅ Google Maps configured in iOS")
    
    // Flutter plugin registration
    GeneratedPluginRegistrant.register(with: self)
    
    // ⚠️ Push notification setup (iOS 10+)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
      print("✅ UNUserNotificationCenter delegate set")
    }
    
    // ⚠️ Background fetch için minimum interval ayarla
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
    print("📱 APNs Device Token: \(token)")
    
    // Firebase Messaging'e token kaydet
    #if canImport(FirebaseMessaging)
    Messaging.messaging().apnsToken = deviceToken
    #endif
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
}
