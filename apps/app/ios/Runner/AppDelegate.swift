import Flutter
import FirebaseMessaging
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushRegistrationChannel: FlutterMethodChannel?
  private var lastPushRegistrationError: String?
  private var lastPushRegistrationSucceededAt: TimeInterval?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "today.readtheworld.app/push_registration",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pushRegistrationChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "register" || call.method == "status" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        if call.method == "register" {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(self?.pushRegistrationStatus() ?? [:])
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    lastPushRegistrationError = nil
    lastPushRegistrationSucceededAt = Date().timeIntervalSince1970
    NSLog("Read the World APNs registration succeeded: \(deviceToken.count) bytes")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    lastPushRegistrationError = error.localizedDescription
    NSLog("Read the World APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  private func pushRegistrationStatus() -> [String: Any] {
    var status: [String: Any] = [
      "isRegisteredForRemoteNotifications": UIApplication.shared.isRegisteredForRemoteNotifications,
      "firebaseApnsTokenSet": Messaging.messaging().apnsToken != nil,
    ]
    status["lastError"] = lastPushRegistrationError ?? NSNull()
    status["lastSuccessAt"] = lastPushRegistrationSucceededAt ?? NSNull()
    return status
  }
}
