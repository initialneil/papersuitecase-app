import Cocoa
import FlutterMacOS
import app_links

@main
class AppDelegate: FlutterAppDelegate {
  private var sparklePlugin: SparklePlugin?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.papersuitcase/sparkle",
      binaryMessenger: controller.engine.binaryMessenger
    )
    sparklePlugin = SparklePlugin(channel: channel)
    channel.setMethodCallHandler(sparklePlugin!.handle)
    sparklePlugin!.start()
  }

  // Handle URLs opened via custom URL scheme (OAuth callbacks)
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      NSLog("AppDelegate: open URL: \(url.absoluteString)")
      AppLinks.shared.handleLink(link: url.absoluteString)
    }
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(self)

    super.application(application, open: urls)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
