package `in`.qoder.refresh_rate

import android.app.Activity
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.WindowManager
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import `in`.qoder.refresh_rate.generated.DisplayInfoMessage
import `in`.qoder.refresh_rate.generated.RefreshRateFlutterApi
import `in`.qoder.refresh_rate.generated.RefreshRateHostApi

class RefreshRatePlugin : FlutterPlugin, ActivityAware, RefreshRateHostApi {
    private var activity: Activity? = null
    private var messenger: BinaryMessenger? = null
    private var foreignFlutterView = false
    private var lastNativeRequest: Map<String, Any?>? = null
    private var context: Context? = null
    private var flutterApi: RefreshRateFlutterApi? = null
    private var control: MethodChannel? = null
    private var displayListener: DisplayManager.DisplayListener? = null
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var powerReceiver: BroadcastReceiver? = null
    private var surfaceView: FlutterSurfaceView? = null
    private var ownedSurface: Surface? = null
    private var categoryView: View? = null
    private var originalCategory: Float? = null
    private var submittedCategory: Float? = null
    private var pending: Map<String, Any?>? = null
    private var originalMode: Int? = null
    private var originalRate: Float? = null
    private var submittedMode: Int? = null
    private var submittedRate: Float? = null
    private val handler = Handler(Looper.getMainLooper())
    private var boostGeneration = 0
    private var pendingTouchBoost: Boolean? = null
    private var originalTouchBoost: Boolean? = null
    private var submittedTouchBoost: Boolean? = null
    private val sustainedOwners = mutableSetOf<String>()
    private var sustainedBaseline: Boolean? = null
    private var sustainedApplied = false
    private var lastHeadroomAt = -10000L
    private var lastHeadroomForecast = 0
    private var lastHeadroom: Map<String, Any?>? = null
    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) { handler.post { reapply() } }
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { reapply() }
        override fun surfaceDestroyed(holder: SurfaceHolder) { /* The destroyed target owns no live vote. */ }
    }
    private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener {
        val changed = bindSurface()
        if (changed) reapply()
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        messenger = binding.binaryMessenger
        RefreshRateHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = RefreshRateFlutterApi(binding.binaryMessenger)
        control = MethodChannel(binding.binaryMessenger, "refresh_rate/control").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "capabilities" -> result.success(mapOf("query" to true,
                            "surfaceVoting" to (Build.VERSION.SDK_INT >= 30),
                            "windowPreferences" to (Build.VERSION.SDK_INT >= 23),
                            "categoryHints" to (Build.VERSION.SDK_INT >= 35),
                            "atLeast" to (Build.VERSION.SDK_INT >= 36),
                            "contentMatching" to (Build.VERSION.SDK_INT >= 30),
                            "touchBoost" to (Build.VERSION.SDK_INT >= 35),
                            "thermalHeadroom" to (Build.VERSION.SDK_INT >= 30),
                            "sustainedPerformance" to (Build.VERSION.SDK_INT >= 24 &&
                                (context?.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isSustainedPerformanceModeSupported == true)))
                        "thermalHeadroom" -> result.success(readThermalHeadroom(
                            (call.argument<Number>("forecastSeconds"))?.toInt() ?: 10))
                        "acquireSustained" -> {
                            val id = call.argument<String>("id") ?: throw IllegalArgumentException("Missing lease id")
                            val baseline = call.argument<Boolean>("previousEnabled") ?: throw IllegalArgumentException("Known prior sustained state required")
                            val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            if (Build.VERSION.SDK_INT < 24 || pm?.isSustainedPerformanceModeSupported != true) {
                                result.success(response("unsupported", message = "Sustained performance mode is not supported"))
                            } else {
                                require(id.length <= 128 && sustainedOwners.size < 128) { "Sustained owner limit exceeded" }
                                require(sustainedBaseline == null || sustainedBaseline == baseline) { "Conflicting sustained baseline" }
                                sustainedBaseline = baseline; sustainedOwners.add(id)
                                result.success(applySustained())
                            }
                        }
                        "releaseSustained" -> {
                            val id = call.argument<String>("id")
                            if (sustainedOwners.remove(id)) {
                                if (sustainedOwners.isEmpty()) { restoreSustained(); sustainedBaseline = null }
                                result.success(response("submitted", "sustainedPerformance"))
                            } else result.success(response("superseded", message = "No sustained preference owned by this lease"))
                        }
                        "resetTouchBoost" -> {
                            restoreTouchBoost(); pendingTouchBoost = null
                            result.success(response(if (Build.VERSION.SDK_INT >= 35) "submitted" else "unsupported", "touchBoost"))
                        }
                        "request" -> {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                            boostGeneration++
                            pending = args
                            result.success(recordRequest(args))
                        }
                        "diagnostics" -> {
                            val d = getDisplay()
                            result.success(mapOf("displayId" to d?.displayId?.toString(),
                                "activityAttached" to (activity != null),
                                "lastNativeRequest" to lastNativeRequest,
                                "surfaceAvailable" to (surfaceView?.holder?.surface?.isValid == true),
                                "ownedSustainedRequests" to sustainedOwners.size,
                                "sustainedPreferenceApplied" to sustainedApplied,
                                "touchBoostEnabled" to if (Build.VERSION.SDK_INT >= 35) activity?.window?.getFrameRateBoostOnTouchEnabled() else null,
                                "source" to "androidDisplay", "currentHz" to d?.refreshRate?.toDouble(),
                                "suggestedNormalHz" to if (Build.VERSION.SDK_INT >= 36) d?.getSuggestedFrameRate(Display.FRAME_RATE_CATEGORY_NORMAL)?.toDouble() else null,
                                "suggestedHighHz" to if (Build.VERSION.SDK_INT >= 36) d?.getSuggestedFrameRate(Display.FRAME_RATE_CATEGORY_HIGH)?.toDouble() else null))
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.error("refresh_rate", error.message, null) }
            }
        }
        registerListeners()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity(); pending = null; pendingTouchBoost = null
        sustainedOwners.clear(); sustainedBaseline = null; boostGeneration++
        handler.removeCallbacksAndMessages(null)
        RefreshRateHostApi.setUp(binding.binaryMessenger, null)
        control?.setMethodCallHandler(null); control = null
        val dm = context?.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        displayListener?.let { dm?.unregisterDisplayListener(it) }; displayListener = null
        val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (Build.VERSION.SDK_INT >= 29) thermalListener?.let { pm?.removeThermalStatusListener(it) }
        powerReceiver?.let { context?.unregisterReceiver(it) }; powerReceiver = null
        flutterApi = null; context = null; messenger = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activity?.window?.decorView?.viewTreeObserver?.addOnGlobalLayoutListener(layoutListener)
        bindSurface(); reapply(); applyTouchBoost(); applySustained(); publish()
    }
    override fun onDetachedFromActivityForConfigChanges() { detachActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() { detachActivity(); pending = null }
    private fun detachActivity() {
        restoreTouchBoost(); restoreSustained()
        clearOwnedPreference()
        surfaceView?.holder?.removeCallback(surfaceCallback); surfaceView = null
        activity?.window?.decorView?.viewTreeObserver?.removeOnGlobalLayoutListener(layoutListener)
        activity = null
    }
    private fun bindSurface(): Boolean {
        val candidates = mutableListOf<FlutterSurfaceView>()
        foreignFlutterView = false
        fun visit(view: View, insideFlutter: Boolean) {
            if (view is FlutterView) {
                val executor = view.attachedFlutterEngine?.dartExecutor
                // Plugin bindings use the executor on some Flutter versions
                // and its BinaryMessenger facade on others.
                if (executor !== messenger && executor?.binaryMessenger !== messenger) {
                    foreignFlutterView = true
                    return
                }
            }
            val inside = insideFlutter || view is FlutterView
            if (inside && view is FlutterSurfaceView && view.isAttachedToWindow && view.visibility == View.VISIBLE) candidates.add(view)
            if (view is ViewGroup) for (i in 0 until view.childCount) visit(view.getChildAt(i), inside)
        }
        activity?.window?.decorView?.let { visit(it, false) }
        val found = candidates.singleOrNull()
        if (found === surfaceView) return false
        restoreCategory()
        if (Build.VERSION.SDK_INT >= 30) ownedSurface?.takeIf { it.isValid }?.setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        ownedSurface = null
        surfaceView?.holder?.removeCallback(surfaceCallback)
        surfaceView = found; found?.holder?.addCallback(surfaceCallback)
        return true
    }
    private fun response(status: String, backend: String = "unavailable", message: String? = null) =
        mapOf("status" to status, "backend" to backend, "scope" to when (backend) {
            "flutterSurface" -> "flutterSurface"
            "viewCategory" -> "flutterSurfaceView"
            else -> "activityWindow"
        }, "message" to message)
    private fun applyRequest(args: Map<String, Any?>): Map<String, Any?> {
        val kind = args["kind"] as? String ?: "system"
        if (kind !in listOf("system", "high", "category", "content", "atLeast")) throw IllegalArgumentException("Unknown preference")
        val fps = (args["fps"] as? Number)?.toFloat()
        if (kind in listOf("content", "atLeast") && (fps == null || !fps.isFinite() || fps <= 0f || fps > 1000f)) throw IllegalArgumentException("Invalid FPS")
        val category = (args["category"] as? Number)?.toInt() ?: 0
        if (category !in 0..3) throw IllegalArgumentException("Invalid category")
        if (activity == null) return response("unavailable", message = "No attached activity; request will be reconciled on attachment.")
        if (kind == "system") { clearOwnedPreference(); return response("submitted", "clearOwnedPreference") }
        val d = getDisplay() ?: return response("unavailable", message = "No display")
        bindSurface()
        if (kind == "category") {
            if (Build.VERSION.SDK_INT < 35) return response("unsupported", message = "Native view categories require API 35")
            val view = surfaceView ?: return response("unavailable", message = "No uniquely identified FlutterSurfaceView for category hint")
            clearOwnedPreference()
            val value = when (category) {
                1 -> View.REQUESTED_FRAME_RATE_CATEGORY_LOW
                2 -> View.REQUESTED_FRAME_RATE_CATEGORY_NORMAL
                3 -> View.REQUESTED_FRAME_RATE_CATEGORY_HIGH
                else -> View.REQUESTED_FRAME_RATE_CATEGORY_NO_PREFERENCE
            }
            categoryView = view; originalCategory = view.requestedFrameRate
            view.setRequestedFrameRate(value); submittedCategory = value
            return response("submitted", "viewCategory")
        }
        restoreCategory()
        if (kind == "atLeast" && Build.VERSION.SDK_INT < 36) return response("unsupported", message = "At-least compatibility requires API 36")
        val mode = if (Build.VERSION.SDK_INT >= 23) d.mode else null
        val rates = if (Build.VERSION.SDK_INT >= 23) d.supportedModes.filter { it.physicalWidth == mode?.physicalWidth && it.physicalHeight == mode.physicalHeight } else emptyList()
        val maxRate = rates.maxOfOrNull { it.refreshRate } ?: d.refreshRate
        val requested = when (kind) {
            "content", "atLeast" -> fps!!
            else -> if (Build.VERSION.SDK_INT >= 36) {
                d.getSuggestedFrameRate(Display.FRAME_RATE_CATEGORY_HIGH).takeIf { it.isFinite() && it > 0f } ?: maxRate
            } else maxRate
        }
        if (requested == 0f) { clearOwnedPreference(); return response("submitted", "clearOwnedPreference") }
        val surface = surfaceView?.holder?.surface?.takeIf { it.isValid }
        if (Build.VERSION.SDK_INT >= 30 && surface != null) {
            restoreWindow()
            val compatibility = when {
                kind == "content" -> Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE
                Build.VERSION.SDK_INT >= 36 -> Surface.FRAME_RATE_COMPATIBILITY_AT_LEAST
                else -> Surface.FRAME_RATE_COMPATIBILITY_DEFAULT
            }
            if (Build.VERSION.SDK_INT >= 31) surface.setFrameRate(requested, compatibility,
                if (args["strategy"] == "allowNonSeamless") Surface.CHANGE_FRAME_RATE_ALWAYS else Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS)
            else if (args["strategy"] == "allowNonSeamless") return response("unsupported", message = "Switch strategy requires API 31")
            else surface.setFrameRate(requested, compatibility)
            ownedSurface = surface
            return response("submitted", "flutterSurface")
        }
        if (kind == "content" || kind == "atLeast") return response("unavailable", message = "No uniquely identified live FlutterSurfaceView; content semantics cannot be preserved by window fallback")
        if (Build.VERSION.SDK_INT < 23) return response("unsupported")
        if (foreignFlutterView) return response("unavailable", message = "Window fallback would affect another Flutter engine")
        val window = activity!!.window
        val params = window.attributes
        if (originalMode == null) { originalMode = params.preferredDisplayModeId; originalRate = params.preferredRefreshRate }
        // Window refresh-rate hint preserves resolution; no implicit mode switch.
        params.preferredRefreshRate = requested
        submittedRate = requested; submittedMode = params.preferredDisplayModeId
        window.attributes = params
        return response("submitted", "windowPreference", "No qualified Flutter surface; using a window refresh-rate hint")
    }
    private fun restoreWindow() {
        val window = activity?.window ?: return
        val params = window.attributes
        if (originalMode != null && params.preferredDisplayModeId == submittedMode && params.preferredRefreshRate == submittedRate) {
            params.preferredDisplayModeId = originalMode!!; params.preferredRefreshRate = originalRate ?: 0f
            window.attributes = params
        }
        originalMode = null; originalRate = null; submittedMode = null; submittedRate = null
    }
    private fun clearOwnedPreference() {
        restoreCategory()
        if (Build.VERSION.SDK_INT >= 30) ownedSurface?.takeIf { it.isValid }?.setFrameRate(0f, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        ownedSurface = null
        restoreWindow()
    }
    private fun restoreCategory() {
        if (Build.VERSION.SDK_INT >= 35) {
            val view = categoryView
            if (view != null && view.requestedFrameRate == submittedCategory) {
                originalCategory?.let { view.setRequestedFrameRate(it) }
            }
        }
        categoryView = null; originalCategory = null; submittedCategory = null
    }
    private fun recordRequest(args: Map<String, Any?>): Map<String, Any?> {
        val outcome = try { applyRequest(args) } catch (error: Exception) {
            response("failed", message = error.message)
        }
        lastNativeRequest = outcome + mapOf("preference" to args, "observedAtMs" to System.currentTimeMillis())
        return outcome
    }
    private fun reapply() { pending?.let { recordRequest(it) } }
    override fun getDisplayInfo(): DisplayInfoMessage {
        val display = getDisplay()
        val modes = if (Build.VERSION.SDK_INT >= 23) display?.supportedModes ?: emptyArray() else emptyArray()
        val current = if (Build.VERSION.SDK_INT >= 23) display?.mode else null
        val rates = modes.filter { it.physicalWidth == current?.physicalWidth && it.physicalHeight == current.physicalHeight }.map { it.refreshRate.toDouble() }.distinct().sorted()
        val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val thermal: Long? = if (Build.VERSION.SDK_INT >= 29) when(pm?.currentThermalStatus) {
            0 -> 0L; 1, 2 -> 1L; 3 -> 2L; 4, 5, 6 -> 3L; else -> null
        } else null
        return DisplayInfoMessage(currentRate = display?.refreshRate?.toDouble(), maxRate = rates.maxOrNull(), minRate = rates.minOrNull(),
            supportedRates = rates, isVariableRefreshRate = null, engineTargetRate = null,
            androidApiLevel = Build.VERSION.SDK_INT.toLong(), isLowPowerMode = pm?.isPowerSaveMode,
            thermalStateIndex = thermal, hasAdaptiveRefreshRate = if (Build.VERSION.SDK_INT >= 36) display?.hasArrSupport() else null)
    }
    private fun legacy(kind: String, fps: Double? = null) { boostGeneration++; pending = mapOf("kind" to kind, "fps" to fps); applyRequest(pending!!) }
    override fun enable() = legacy("high")
    override fun disable() = legacy("system")
    override fun preferMax() = legacy("high")
    override fun preferDefault() = legacy("system")
    override fun matchContent(fps: Double) = legacy("content", fps)
    override fun boost(durationMs: Long) {
        require(durationMs > 0 && durationMs <= 86400000)
        val previous = pending; legacy("high"); val generation = boostGeneration
        handler.postDelayed({ if (generation == boostGeneration) { pending = previous ?: mapOf("kind" to "system"); reapply() } }, durationMs)
    }
    override fun setCategory(categoryIndex: Long) {
        require(categoryIndex in 0..3); boostGeneration++
        pending = mapOf("kind" to "category", "category" to categoryIndex); applyRequest(pending!!)
    }
    override fun setTouchBoost(enabled: Boolean) {
        check(Build.VERSION.SDK_INT >= 35) { "Touch boost requires Android API 35" }
        pendingTouchBoost = enabled
        applyTouchBoost()
    }
    private fun applyTouchBoost() {
        if (Build.VERSION.SDK_INT < 35) return
        val value = pendingTouchBoost ?: return
        val window = activity?.window ?: return
        if (originalTouchBoost == null) originalTouchBoost = window.getFrameRateBoostOnTouchEnabled()
        window.setFrameRateBoostOnTouchEnabled(value); submittedTouchBoost = value
    }
    private fun restoreTouchBoost() {
        if (Build.VERSION.SDK_INT >= 35) {
            val window = activity?.window
            if (window != null && originalTouchBoost != null && window.getFrameRateBoostOnTouchEnabled() == submittedTouchBoost) {
                window.setFrameRateBoostOnTouchEnabled(originalTouchBoost!!)
            }
        }
        originalTouchBoost = null; submittedTouchBoost = null
    }
    private fun applySustained(): Map<String, Any?> {
        if (sustainedOwners.isEmpty()) return response("superseded")
        if (Build.VERSION.SDK_INT < 24) return response("unsupported")
        val window = activity?.window ?: return response("unavailable", message = "Waiting for attached activity")
        window.setSustainedPerformanceMode(true); sustainedApplied = true
        return response("submitted", "sustainedPerformance", "Consistency preference; not a maximum-performance guarantee")
    }
    private fun restoreSustained() {
        if (Build.VERSION.SDK_INT >= 24 && sustainedApplied) {
            activity?.window?.setSustainedPerformanceMode(sustainedBaseline ?: false)
        }
        sustainedApplied = false
    }
    private fun readThermalHeadroom(forecast: Int): Map<String, Any?> {
        require(forecast in 0..60) { "Forecast must be 0..60 seconds" }
        if (Build.VERSION.SDK_INT < 30) return mapOf("forecastSeconds" to forecast, "unavailableReason" to "Thermal headroom requires API 30")
        val now = SystemClock.elapsedRealtime()
        if (now - lastHeadroomAt < 10000) {
            if (forecast == lastHeadroomForecast) return (lastHeadroom ?: emptyMap()) + ("cached" to true)
            return mapOf("forecastSeconds" to forecast, "unavailableReason" to "Another forecast was sampled less than ten seconds ago")
        }
        val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val value = pm?.getThermalHeadroom(forecast)?.takeIf { it.isFinite() && it >= 0f }
        lastHeadroomAt = now; lastHeadroomForecast = forecast
        val reading = mapOf<String, Any?>("value" to value?.toDouble(), "forecastSeconds" to forecast,
            "observedAtMs" to System.currentTimeMillis(), "cached" to false,
            "unavailableReason" to if (value == null) "Device did not provide thermal headroom" else null)
        lastHeadroom = reading
        return reading
    }
    override fun isSupported(): Boolean = Build.VERSION.SDK_INT >= 23
    private fun publish() { handler.post { flutterApi?.onDisplayInfoChanged(getDisplayInfo()) {} } }
    private fun registerListeners() {
        val dm = context?.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        displayListener = object : DisplayManager.DisplayListener {
            override fun onDisplayChanged(displayId: Int) { publish() }
            override fun onDisplayAdded(displayId: Int) { publish() }
            override fun onDisplayRemoved(displayId: Int) { publish() }
        }
        dm?.registerDisplayListener(displayListener, handler)
        val pm = context?.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (Build.VERSION.SDK_INT >= 29) {
            thermalListener = PowerManager.OnThermalStatusChangedListener { publish() }
            pm?.addThermalStatusListener(context!!.mainExecutor, thermalListener!!)
        }
        powerReceiver = object : BroadcastReceiver() { override fun onReceive(context: Context?, intent: Intent?) { publish() } }
        context?.registerReceiver(powerReceiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED))
    }
    @Suppress("DEPRECATION")
    private fun getDisplay(): Display? = if (Build.VERSION.SDK_INT >= 30) activity?.display else activity?.windowManager?.defaultDisplay
}
