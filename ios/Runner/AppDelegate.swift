import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceChannel: HumanTwinDeviceChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HumanTwinDevice") {
      deviceChannel = HumanTwinDeviceChannel(messenger: registrar.messenger())
    }
  }
}

/// Device services for the local v1: app storage paths, the share sheet and "save to Files".
/// Gallery saves are not offered on iOS (they would need a photo-library permission).
final class HumanTwinDeviceChannel: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private let channel: FlutterMethodChannel
  private var pendingSave: FlutterResult?
  private var pendingShare: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "humantwin/device", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "paths":
      do {
        result([
          "documents": try privateDocuments().path,
          "cache": FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.path,
          // image_picker writes its copies to the temporary directory on iOS.
          "pickerCache": NSTemporaryDirectory(),
          "sdkInt": 0,
        ])
      } catch {
        result(FlutterError(code: "paths", message: error.localizedDescription, details: nil))
      }
    case "shareFile":
      guard let path = args["path"] as? String else { return result(["status": "failed"]) }
      share(URL(fileURLWithPath: path), result: result)
    case "saveDocument":
      guard let path = args["path"] as? String else { return result(["status": "failed"]) }
      saveDocument(URL(fileURLWithPath: path), result: result)
    case "saveImageToGallery":
      result(["status": "unsupported"])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Application Support (hidden from the Files app); the app's data folder is excluded from
  /// iCloud/iTunes backup so photos and models stay on this phone.
  private func privateDocuments() throws -> URL {
    let manager = FileManager.default
    let support = try manager.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var data = support.appendingPathComponent("humantwin", isDirectory: true)
    try manager.createDirectory(at: data, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try data.setResourceValues(values)
    return support
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var top = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private func share(_ url: URL, result: @escaping FlutterResult) {
    guard pendingShare == nil, pendingSave == nil else {
      return result(FlutterError(code: "busy", message: "Another share or save is in progress", details: nil))
    }
    guard let presenter = topViewController() else { return result(["status": "failed"]) }
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    // The app declares no photo-library permission on iOS; "Save Image" would need one.
    controller.excludedActivityTypes = [.saveToCameraRoll]
    pendingShare = result
    controller.completionWithItemsHandler = { [weak self] _, completed, _, error in
      // iOS reports an activity type, not an app name, so no label is passed back.
      let status = error != nil ? "failed" : (completed ? "handedOff" : "closed")
      self?.finishShare(["status": status])
    }
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 80, width: 1, height: 1)
    }
    presenter.present(controller, animated: true)
  }

  private func finishShare(_ payload: [String: Any]) {
    guard let result = pendingShare else { return }
    pendingShare = nil
    result(payload)
  }

  private func saveDocument(_ url: URL, result: @escaping FlutterResult) {
    guard pendingShare == nil, pendingSave == nil else {
      return result(FlutterError(code: "busy", message: "Another share or save is in progress", details: nil))
    }
    guard let presenter = topViewController() else { return result(["status": "failed"]) }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: url, in: .exportToService)
    }
    picker.delegate = self
    pendingSave = result
    presenter.present(picker, animated: true)
    picker.presentationController?.delegate = self
  }

  private func finishSave(_ status: String) {
    guard let result = pendingSave else { return }
    pendingSave = nil
    result(["status": status])
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishSave("saved")
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishSave("cancelled")
  }

  // Swiping the picker away does not always call documentPickerWasCancelled.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finishSave("cancelled")
  }
}
