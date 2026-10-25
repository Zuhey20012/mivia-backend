import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// GoogleService-Info.plist is added on the Mac and never committed (docs/ios/MAC-SETUP.md).
  /// Without it Firebase is not configured and the app runs without push, phone and Apple sign-in.
  private static let firebaseConfigured =
    Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil

  private static let remoteNotificationSelector =
    NSSelectorFromString("application:didReceiveRemoteNotification:fetchCompletionHandler:")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Without Firebase, the firebase_auth plugin would stop the app when iOS hands it a push
  /// (FirebaseAuth needs a configured app), for example a test push dropped on the simulator.
  /// iOS then simply does not deliver pushes to the app delegate; nothing else needs them.
  override func responds(to aSelector: Selector!) -> Bool {
    if !AppDelegate.firebaseConfigured && aSelector == AppDelegate.remoteNotificationSelector {
      return false
    }
    return super.responds(to: aSelector)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Tells the Dart side (malvoya_core SignInSetup) what this build was set up with, so it can
    // hide sign-in options whose SDKs would otherwise stop the app.
    let setup = FlutterMethodChannel(
      name: "malvoya/ios_setup", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    setup.setMethodCallHandler { call, result in
      if call.method == "read" {
        result(AppDelegate.setupInfo())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func setupInfo() -> [String: Any] {
    let info = Bundle.main.infoDictionary ?? [:]
    var schemes: [String] = []
    for urlType in info["CFBundleURLTypes"] as? [[String: Any]] ?? [] {
      schemes.append(contentsOf: urlType["CFBundleURLSchemes"] as? [String] ?? [])
    }
    return [
      "firebasePlist": firebaseConfigured,
      "urlSchemes": schemes,
      "googleClientId": info["GIDClientID"] as? String ?? "",
      "googleServerClientId": info["GIDServerClientID"] as? String ?? "",
    ]
  }
}
