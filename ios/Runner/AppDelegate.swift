import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    self.launchOptions = launchOptions
    // Local notifications never finishes initialize unless this is set before
    // launch returns. Firebase then forwards through the app delegate instead
    // of replacing it.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The scene loads the Flutter engine after UIKit has already posted
    // didFinishLaunching. Firebase Messaging only finishes setup in that
    // notification, so without this it never applies the APNS token and
    // getInitialMessage never returns.
    let published = engineBridge.pluginRegistry.valuePublished(
      byPlugin: "FLTFirebaseMessagingPlugin")
    let selector = NSSelectorFromString("application_onDidFinishLaunchingNotification:")
    guard let messaging = published, !(messaging is NSNull),
          messaging.responds(to: selector) else {
      return
    }
    var userInfo: [AnyHashable: Any] = [:]
    launchOptions?.forEach { key, value in
      userInfo[key.rawValue] = value
    }
    let notification = NSNotification(
      name: UIApplication.didFinishLaunchingNotification,
      object: UIApplication.shared,
      userInfo: userInfo
    )
    messaging.perform(selector, with: notification)
  }
}
