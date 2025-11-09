import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAAeSrC4jKD8NfwpVziSyuE4zJnaq4Ok5A',
    appId: '1:123456789012:web:abcdef1234567891',
    messagingSenderId: '123456789012',
    projectId: 'funbreak-vale',
    authDomain: 'funbreak-vale.firebaseapp.com',
    storageBucket: 'funbreak-vale.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD_N1xsLJ5E4G8t1BP3wjKEdm4tjgxIM_c',
    appId: '1:398609081798:android:4b4fd79c2e44d869e8bec7',
    messagingSenderId: '398609081798',
    projectId: 'funbreak-vale',
    storageBucket: 'funbreak-vale.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC9EwNmEe-8uN3BZCJQcrFpfxC3Rda6KLM',
    appId: '1:398609081798:ios:4b4fd79c2e44d869e8bec7',
    messagingSenderId: '398609081798',
    projectId: 'funbreak-vale',
    storageBucket: 'funbreak-vale.firebasestorage.app',
    iosBundleId: 'com.funbreak.vale.iosdriver',
    iosClientId: '842813355945-vavtjf1200g6cbbgssaar0i6dum5j883.apps.googleusercontent.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAAeSrC4jKD8NfwpVziSyuE4zJnaq4Ok5A',
    appId: '1:123456789012:ios:abcdef1234567891',
    messagingSenderId: '123456789012',
    projectId: 'funbreak-vale',
    storageBucket: 'funbreak-vale.firebasestorage.app',
    iosBundleId: 'com.funbreak.vale.iosdriver',
  );
} 