package today.readtheworld.app

import android.net.Uri
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val deferredInviteChannel = "today.readtheworld.app/deferred_invite"
    private val preferencesName = "deferred_invite"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deferredInviteChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstallReferrer" -> readInstallReferrer(result)
                "markConsumed" -> markConsumed(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun readInstallReferrer(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(this).build()
        var completed = false
        fun finish(value: String?) {
            if (completed) return
            completed = true
            try {
                client.endConnection()
            } catch (_: Exception) {
                // The service may have disconnected before setup completed.
            }
            result.success(value)
        }
        client.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                    finish(null)
                    return
                }
                val raw = try {
                    client.installReferrer.installReferrer
                } catch (_: Exception) {
                    ""
                }
                val code = Uri.parse("https://rtw.codes/?$raw")
                    .getQueryParameter("invite")
                    ?.trim()
                    ?.uppercase()
                    ?.takeIf { it.matches(Regex("^[A-Z0-9-]{4,32}$")) }
                val consumed = getSharedPreferences(preferencesName, MODE_PRIVATE)
                    .getString("consumedCode", null)
                finish(if (code == consumed) null else code)
            }

            override fun onInstallReferrerServiceDisconnected() {
                // A future app launch retries. Do not hang startup for a
                // best-effort deferred invite if setup never completed.
                finish(null)
            }
        })
    }

    private fun markConsumed(call: MethodCall, result: MethodChannel.Result) {
        val code = call.argument<String>("code")?.trim()?.uppercase()
        if (!code.isNullOrEmpty()) {
            getSharedPreferences(preferencesName, MODE_PRIVATE)
                .edit()
                .putString("consumedCode", code)
                .apply()
        }
        result.success(null)
    }
}
