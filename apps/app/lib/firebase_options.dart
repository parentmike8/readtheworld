import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const configured = bool.fromEnvironment('RTW_FIREBASE_CONFIGURED');

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('RTW_FIREBASE_API_KEY'),
    appId: String.fromEnvironment('RTW_FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('RTW_FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('RTW_FIREBASE_PROJECT_ID'),
    authDomain: String.fromEnvironment('RTW_FIREBASE_AUTH_DOMAIN'),
    storageBucket: String.fromEnvironment('RTW_FIREBASE_STORAGE_BUCKET'),
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: String.fromEnvironment('RTW_FIREBASE_ANDROID_API_KEY'),
    appId: String.fromEnvironment('RTW_FIREBASE_ANDROID_APP_ID'),
    messagingSenderId: String.fromEnvironment('RTW_FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('RTW_FIREBASE_PROJECT_ID'),
    storageBucket: String.fromEnvironment('RTW_FIREBASE_STORAGE_BUCKET'),
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: String.fromEnvironment('RTW_FIREBASE_IOS_API_KEY'),
    appId: String.fromEnvironment('RTW_FIREBASE_IOS_APP_ID'),
    messagingSenderId: String.fromEnvironment('RTW_FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('RTW_FIREBASE_PROJECT_ID'),
    storageBucket: String.fromEnvironment('RTW_FIREBASE_STORAGE_BUCKET'),
    iosBundleId: 'today.readtheworld.app',
  );
}
