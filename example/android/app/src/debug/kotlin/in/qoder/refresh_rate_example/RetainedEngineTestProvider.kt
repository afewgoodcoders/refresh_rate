package `in`.qoder.refresh_rate_example

import android.app.Activity
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import `in`.qoder.refresh_rate.RefreshRatePlugin

/** Debug-only fixture: replace an Activity without replacing its Flutter engine. */
class RetainedEngineTestProvider : ContentProvider(), Application.ActivityLifecycleCallbacks {
    private var replacing: Activity? = null
    private var retained: FlutterEngine? = null
    private var destroyed = 0
    private var ordinaryDetach = false
    private var detachedWithoutTarget = false
    private val cacheKey = "refresh-rate-integration-engine"

    override fun onCreate(): Boolean {
        (context!!.applicationContext as Application).registerActivityLifecycleCallbacks(this)
        return true
    }

    private fun findEngine(view: View): FlutterEngine? {
        if (view is FlutterView) return view.attachedFlutterEngine
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            findEngine(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    override fun onActivityResumed(activity: Activity) {
        if (activity !is FlutterActivity) return
        activity.window.decorView.post {
            val engine = findEngine(activity.window.decorView) ?: return@post
            MethodChannel(engine.dartExecutor.binaryMessenger, "refresh_rate_example/retained_engine")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "snapshot" -> result.success(mapOf(
                            "activity" to System.identityHashCode(activity),
                            "engine" to System.identityHashCode(engine),
                            "destroyed" to destroyed,
                            "ordinaryDetach" to ordinaryDetach,
                            "detachedWithoutTarget" to detachedWithoutTarget))
                        "replaceActivity" -> {
                            if (replacing != null) {
                                result.error("busy", "Activity replacement already in progress", null)
                            } else {
                                retained = engine
                                replacing = activity
                                FlutterEngineCache.getInstance().put(cacheKey, engine)
                                // FlutterActivity honors this extra for an internally created engine too.
                                activity.intent.putExtra("destroy_engine_with_activity", false)
                                result.success(null)
                                activity.window.decorView.post { activity.finish() }
                            }
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    override fun onActivityDestroyed(activity: Activity) {
        if (activity !== replacing) return
        val engine = retained!!
        destroyed++
        ordinaryDetach = !activity.isChangingConfigurations
        replacing = null
        retained = null
        // Application callbacks may run from super.onDestroy(), before the
        // Flutter delegate detaches. Wait until the entire callback unwinds.
        Handler(Looper.getMainLooper()).post {
            val plugin = engine.plugins.get(RefreshRatePlugin::class.java) as RefreshRatePlugin
            val snapshot = plugin.getDiagnostics()
            detachedWithoutTarget = snapshot.activityAttached == false && snapshot.surfaceAvailable == false
            context!!.startActivity(FlutterActivity.withCachedEngine(cacheKey)
                .destroyEngineWithActivity(false).build(context!!)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?): Int = 0
}
