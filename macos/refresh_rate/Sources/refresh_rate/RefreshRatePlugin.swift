import Cocoa
import FlutterMacOS
import CoreVideo

/// Window-scoped native display queries, independent of Flutter engine control.
public class RefreshRatePlugin: NSObject, FlutterPlugin, RefreshRateHostApi {
    private weak var view: NSView?
    private var flutterApi: RefreshRateFlutterApi?
    private var observers: [NSObjectProtocol] = []
    private var control: FlutterMethodChannel?
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RefreshRatePlugin()
        instance.view = registrar.view
        instance.flutterApi = RefreshRateFlutterApi(binaryMessenger: registrar.messenger)
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger, api: instance)
        let control = FlutterMethodChannel(name: "refresh_rate/control", binaryMessenger: registrar.messenger)
        instance.control = control
        control.setMethodCallHandler { [weak instance] call, result in
            guard let self = instance else { result(FlutterError(code: "detached", message: "Engine detached", details: nil)); return }
            switch call.method {
            case "capabilities": result(["query": true, "engineControl": false])
            case "request":
                let clear = (call.arguments as? [String: Any])?["kind"] as? String == "system"
                result(["status": clear ? "submitted" : "unsupported", "backend": clear ? "clearOwnedPreference" : "unavailable",
                    "scope": "flutterEngine", "message": "A helper display link does not control the Flutter engine."])
            case "diagnostics": result(["source": "coreGraphicsDisplayMode", "displayId": self.displayId.map { String($0) } as Any])
            default: result(FlutterMethodNotImplemented)
            }
        }
        var notifications = [NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification,
            ProcessInfo.thermalStateDidChangeNotification]
        if #available(macOS 12.0, *) { notifications.append(Notification.Name.NSProcessInfoPowerStateDidChange) }
        for name in notifications {
            instance.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak instance] _ in
                guard let self = instance, let info = try? self.getDisplayInfo() else { return }
                self.flutterApi?.onDisplayInfoChanged(info: info) { _ in }
            })
        }
    }
    private var screen: NSScreen? { view?.window?.screen }
    private var displayId: CGDirectDisplayID? { screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
    func getDisplayInfo() throws -> DisplayInfoMessage {
        let current = displayId.flatMap { CGDisplayCopyDisplayMode($0) }
        let rates: [Double] = displayId.flatMap { CGDisplayCopyAllDisplayModes($0, nil) as? [CGDisplayMode] }?.filter {
            $0.width == current?.width && $0.height == current?.height && $0.refreshRate > 0
        }.map { $0.refreshRate } ?? []
        let unique = Array(Set(rates)).sorted()
        var maxRate = unique.max()
        var vrr: Bool? = nil
        if #available(macOS 12.0, *), let screen = screen {
            maxRate = Double(screen.maximumFramesPerSecond)
            vrr = screen.minimumRefreshInterval != screen.maximumRefreshInterval
        }
        var lowPower: Bool? = nil
        if #available(macOS 12.0, *) { lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        let thermal: Int64?
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = 0
        case .fair: thermal = 1
        case .serious: thermal = 2
        case .critical: thermal = 3
        @unknown default: thermal = nil
        }
        return DisplayInfoMessage(currentRate: (current?.refreshRate ?? 0) > 0 ? current?.refreshRate : nil,
            maxRate: maxRate, minRate: unique.min(), supportedRates: unique,
            isVariableRefreshRate: vrr, engineTargetRate: nil, isLowPowerMode: lowPower,
            thermalStateIndex: thermal, hasAdaptiveRefreshRate: vrr,
            monitorCount: Int64(NSScreen.screens.count))
    }
    private func unsupported() throws { throw PigeonError(code: "unsupported", message: "No qualified Flutter engine rate-control backend", details: nil) }
    func enable() throws { try unsupported() }
    func preferMax() throws { try unsupported() }
    func disable() throws {}
    func preferDefault() throws {}
    func matchContent(fps: Double) throws { try unsupported() }
    func boost(durationMs: Int64) throws { try unsupported() }
    func setCategory(categoryIndex: Int64) throws { try unsupported() }
    func setTouchBoost(enabled: Bool) throws { try unsupported() }
    func isSupported() throws -> Bool { false }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        control?.setMethodCallHandler(nil); control = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger, api: nil)
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
