import Flutter
import UIKit
import QuartzCore

/// Query and opt-in callback observation. No process-wide display-link hooks.
public class RefreshRatePlugin: NSObject, FlutterPlugin, RefreshRateHostApi {
    private var registrar: FlutterPluginRegistrar?
    private var flutterApi: RefreshRateFlutterApi?
    private var observers: [NSObjectProtocol] = []
    private var link: CADisplayLink?
    private var callbackHz: Double?
    private var expectedHz: Double?
    private var lastTimestamp: CFTimeInterval?
    private var sampleCount = 0
    private var firstTimestamp: CFTimeInterval?
    private var observationWindowUs: Int64?
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RefreshRatePlugin()
        instance.registrar = registrar
        instance.flutterApi = RefreshRateFlutterApi(binaryMessenger: registrar.messenger())
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        registrar.publish(instance)
        instance.registerObservers()
    }
    // Implicit engines may register plugins before attaching their view.
    // Resolve the engine's current view rather than caching a nil controller.
    private var screen: UIScreen? { registrar?.viewController?.viewIfLoaded?.window?.screen }
    func getDisplayInfo() throws -> DisplayInfoMessage {
        DisplayInfoMessage(currentRate: nil,
            maxRate: screen.map { Double($0.maximumFramesPerSecond) }, minRate: nil,
            supportedRates: nil, isVariableRefreshRate: nil, engineTargetRate: nil,
            iosProMotionEnabled: Bundle.main.object(forInfoDictionaryKey: "CADisableMinimumFrameDurationOnPhone") as? Bool,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalStateIndex: thermalIndex(), hasAdaptiveRefreshRate: nil)
    }
    func getCapabilities() -> CapabilitiesMessage {
        CapabilitiesMessage(query: true, engineControl: false, presentationObservation: false,
            callbackObservation: true)
    }
    func getDiagnostics() -> DiagnosticsMessage {
        DiagnosticsMessage(source: "appleDisplayLink", scope: "pluginObserver", maximumHz: screen.map { Double($0.maximumFramesPerSecond) },
            callbackHz: callbackHz, expectedCallbackHz: expectedHz,
            sampleCount: Int64(sampleCount), windowUs: observationWindowUs)
    }
    func submitPreference(preference: PreferenceMessage) -> RequestResultMessage {
        let clear = preference.kind == .system
        return RequestResultMessage(status: clear ? .submitted : .unsupported,
            backend: clear ? "clearOwnedPreference" : "unavailable", scope: "flutterEngine",
            message: "No qualified per-engine control integration; system scheduling remains in control.",
            preference: preference)
    }
    func resetTouchBoost() -> RequestResultMessage {
        RequestResultMessage(status: .unsupported, backend: "unavailable", scope: "flutterEngine")
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
    func startObservation() -> Bool {
        guard link == nil else { return true }
        callbackHz = nil; expectedHz = nil; lastTimestamp = nil; sampleCount = 0; firstTimestamp = nil; observationWindowUs = nil
        let observer = CADisplayLink(target: self, selector: #selector(tick))
        observer.isPaused = UIApplication.shared.applicationState != .active
        observer.add(to: .main, forMode: .common); link = observer
        return true
    }
    func stopObservation() { link?.invalidate(); link = nil; lastTimestamp = nil; callbackHz = nil; expectedHz = nil; sampleCount = 0 }
    @objc private func tick(_ sender: CADisplayLink) {
        let interval = sender.targetTimestamp - sender.timestamp
        expectedHz = interval > 0 ? 1 / interval : nil
        if let first = firstTimestamp, let last = lastTimestamp, sender.timestamp > last {
            sampleCount += 1
            let elapsed = sender.timestamp - first
            callbackHz = elapsed > 0 ? Double(sampleCount) / elapsed : nil
            observationWindowUs = Int64(elapsed * 1_000_000)
        } else { firstTimestamp = sender.timestamp }
        lastTimestamp = sender.timestamp
    }
    private func registerObservers() {
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification,
            UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                if notification.name == UIApplication.willResignActiveNotification { self.link?.isPaused = true; self.lastTimestamp = nil; self.firstTimestamp = nil; self.sampleCount = 0; self.observationWindowUs = nil; self.callbackHz = nil }
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
        self.registrar = nil
        stopObservation()
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        RefreshRateHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
