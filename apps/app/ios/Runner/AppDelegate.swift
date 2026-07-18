import Flutter
import FirebaseMessaging
import StoreKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushRegistrationChannel: FlutterMethodChannel?
  private var reviewEnvironmentChannel: FlutterMethodChannel?
  private var deferredInviteChannel: FlutterMethodChannel?
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

    let reviewChannel = FlutterMethodChannel(
      name: "today.readtheworld.app/review_environment",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    reviewEnvironmentChannel = reviewChannel
    reviewChannel.setMethodCallHandler { call, flutterResult in
      guard call.method == "isTestFlight" else {
        flutterResult(FlutterMethodNotImplemented)
        return
      }
      self.resolveTestFlightEnvironment(flutterResult)
    }

    let inviteChannel = FlutterMethodChannel(
      name: "today.readtheworld.app/deferred_invite",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    deferredInviteChannel = inviteChannel
    inviteChannel.setMethodCallHandler { call, flutterResult in
      switch call.method {
      case "hasInvite":
        self.hasProbableInvite(flutterResult)
      case "readClipboardInvite":
        let pasteboard = UIPasteboard.general
        flutterResult(pasteboard.url?.absoluteString ?? pasteboard.string)
      case "markConsumed":
        let arguments = call.arguments as? [String: Any]
        let code = (arguments?["code"] as? String)?.uppercased() ?? ""
        let pasteboard = UIPasteboard.general
        let value = (pasteboard.url?.absoluteString ?? pasteboard.string ?? "").uppercased()
        if !code.isEmpty && value.contains(code) {
          pasteboard.items = []
        }
        flutterResult(nil)
      default:
        flutterResult(FlutterMethodNotImplemented)
      }
    }
  }

  private func hasProbableInvite(_ flutterResult: @escaping FlutterResult) {
    if #available(iOS 15.0, *) {
      UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
        DispatchQueue.main.async {
          switch result {
          case .success(let patterns):
            flutterResult(patterns.contains(.probableWebURL))
          case .failure:
            flutterResult(false)
          }
        }
      }
      return
    }
    flutterResult(UIPasteboard.general.hasURLs)
  }

  private func resolveTestFlightEnvironment(_ flutterResult: @escaping FlutterResult) {
    if #available(iOS 16.0, *) {
      Task {
        do {
          let verification = try await AppTransaction.shared
          let transaction: AppTransaction
          switch verification {
          case .verified(let value):
            transaction = value
          case .unverified(let value, _):
            transaction = value
          }
          await MainActor.run {
            flutterResult(transaction.environment == .sandbox)
          }
        } catch {
          await MainActor.run {
            flutterResult(self.hasSandboxReceipt)
          }
        }
      }
      return
    }
    flutterResult(hasSandboxReceipt)
  }

  private var hasSandboxReceipt: Bool {
    Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
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
