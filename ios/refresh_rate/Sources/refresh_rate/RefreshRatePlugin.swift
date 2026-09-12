import Flutter
import UIKit
import QuartzCore

/// Query and opt-in callback observation. No process-wide display-link hooks.
public class RefreshRatePlugin: NSObject, FlutterPlugin, RefreshRateHostApi {
    private weak var viewController: UIViewController?
    private var flutterApi: RefreshRateFlutterApi?
    private var channel: FlutterMethodChannel?
    private var observers: [NSObjectProtocol] = []
    private var link: CADisplayLink?
    private var callbackHz: Double?
    private var expectedHz: Double?
    private var lastTimestamp: CFTimeInterval?
    private var sampleCount = 0
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RefreshRatePlugin()
        instance.viewController = registrar.viewController
        instance.flutterApi = RefreshRateFlutterApi(binaryMessenger: registrar.messenger())
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        let channel = FlutterMethodChannel(name: "refresh_rate/control", binaryMessenger: registrar.messenger())
        instance.channel = channel
        channel.setMethodCallHandler { [weak instance] call, result in
            guard let self = instance else { result(FlutterError(code: "detached", message: "Engine detached", details: nil)); return }
            switch call.method {
            case "capabilities": result(["query": true, "engineControl": false, "presentationObservation": false])
            case "request":
                let args = call.arguments as? [String: Any]
                let clear = args?["kind"] as? String == "system"
                result(["status": clear ? "submitted" : "unsupported", "backend": clear ? "clearOwnedPreference" : "unavailable",
                    "scope": "flutterEngine", "message": "No supported per-engine rate-control integration is installed. System scheduling remains in control."])
            case "startObservation":
                self.startObservation(); result(nil)
            case "stopObservation":
                self.stopObservation(); result(nil)
            case "diagnostics":
                result(["source": "appleDisplayLink", "callbackHz": self.callbackHz as Any,
                    "expectedCallbackHz": self.expectedHz as Any, "sampleCount": self.sampleCount,
                    "scope": "pluginObserver", "maximumHz": self.screen.map { Double($0.maximumFramesPerSecond) } as Any])
            default: result(FlutterMethodNotImplemented)
            }
        }
        registrar.publish(instance)
        instance.registerObservers()
    }
    private var screen: UIScreen? { viewController?.viewIfLoaded?.window?.screen }
    func getDisplayInfo() throws -> DisplayInfoMessage {
        DisplayInfoMessage(currentRate: nil,
            maxRate: screen.map { Double($0.maximumFramesPerSecond) }, minRate: nil,
            supportedRates: nil, isVariableRefreshRate: nil, engineTargetRate: nil,
            iosProMotionEnabled: Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone") as? Bool,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalStateIndex: thermalIndex(), hasAdaptiveRefreshRate: nil)
    }
    private func unsupported() throws { throw PigeonError(code: "unsupported", message: "Flutter engine rate control is unavailable without a qualified integration", details: nil) }
    func enable() throws { try unsupported() }
    func preferMax() throws { try unsupported() }
    func disable() throws { /* No owned engine preference to clear. */ }
    func preferDefault() throws { try disable() }
    func matchContent(fps: Double) throws { try unsupported() }
    func boost(durationMs: Int64) throws { try unsupported() }
    func setCategory(categoryIndex: Int64) throws { try unsupported() }
    func setTouchBoost(enabled: Bool) throws { try unsupported() }
    func isSupported() throws -> Bool { false }
    private func startObservation() {
        guard link == nil else { return }
        callbackHz = nil; expectedHz = nil; lastTimestamp = nil; sampleCount = 0
        let observer = CADisplayLink(target: self, selector: #selector(tick))
        observer.isPaused = UIApplication.shared.applicationState != .active
        observer.add(to: .main, forMode: .common); link = observer
    }
    private func stopObservation() { link?.invalidate(); link = nil; lastTimestamp = nil; callbackHz = nil; expectedHz = nil; sampleCount = 0 }
    @objc private func tick(_ sender: CADisplayLink) {
        let interval = sender.targetTimestamp - sender.timestamp
        expectedHz = interval > 0 ? 1 / interval : nil
        if let last = lastTimestamp, sender.timestamp > last { callbackHz = 1 / (sender.timestamp - last); sampleCount += 1 }
        lastTimestamp = sender.timestamp
    }
    private func registerObservers() {
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification,
            UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                if notification.name == UIApplication.willResignActiveNotification { self.link?.isPaused = true; self.lastTimestamp = nil; self.callbackHz = nil }
                if notification.name == UIApplication.didBecomeActiveNotification { self.link?.isPaused = false; self.lastTimestamp = nil }
                if let info = try? self.getDisplayInfo() { self.flutterApi?.onDisplayInfoChanged(info: info) { _ in } }
            })
        }
    }
    private func thermalIndex() -> Int64? {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return nil
        }
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        stopObservation(); channel?.setMethodCallHandler(nil); channel = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
