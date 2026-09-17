package com.tarkilhk.wing

import android.app.Activity
import android.app.Dialog
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** App-owned browser session, matching Desktop's Portal cookie boundary.
 * No JavaScript bridge, certificate bypass, file access, or cookie forwarding to
 * an arbitrary caller-supplied host. Instance grants are exchanged in Dart via PKCE.
 */
class HermesCloudChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.tarkilhk.wing/hermes_cloud")
    private val main = Handler(Looper.getMainLooper())
    private val cookies get() = CookieManager.getInstance()
    private var dialog: Dialog? = null
    private val views = mutableListOf<WebView>()
    private var pending: MethodChannel.Result? = null
    private val portal = "https://portal.nousresearch.com"

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> { finish(null); result.success(null) }
                "portal" -> {
                    if (pending != null) { result.error("busy", "A sign-in is already open.", null) }
                    else if (call.argument<Boolean>("switchAccount") == true ||
                        (call.argument<Boolean>("signIn") == true && portalCookie() != null)) {
                        // Clear Portal browser identity, including Privy local storage.
                        // Per-instance bearer grants are separate secure-storage records.
                        pending = result
                        cookies.removeAllCookies {
                            if (pending !== result) return@removeAllCookies
                            android.webkit.WebStorage.getInstance().deleteAllData()
                            open(portal, null, result)
                        }
                    } else if (call.argument<Boolean>("signIn") != true) {
                        result.success(portalCookie())
                    } else { open(portal, null, result) }
                }
                "authorize" -> {
                    val url = call.argument<String>("url") ?: ""
                    val callback = call.argument<String>("callback") ?: ""
                    val target = Uri.parse(url)
                    val redirect = Uri.parse(callback)
                    if (pending != null) result.error("busy", "A sign-in is already open.", null)
                    else if (target.scheme != "https" || target.host.isNullOrEmpty() ||
                        target.userInfo != null || redirect.scheme != "http" ||
                        redirect.host != "127.0.0.1" || redirect.port != 49152 ||
                        redirect.query != null || redirect.fragment != null ||
                        redirect.path?.startsWith("/wing/") != true) {
                        result.error("invalid_url", "Invalid Cloud sign-in address.", null)
                    } else open(url, callback, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun portalCookie(): String? {
        val value = cookies.getCookie("$portal/api/agents") ?: return null
        val token = value.split(';').map { it.trim() }
            .firstOrNull { it.startsWith("privy-token=") }?.substringAfter('=') ?: return null
        // A fresh access token only signals browser completion. /api/agents
        // remains authoritative for authentication and membership.
        return try {
            val parts = Uri.decode(token).split('.')
            val payload = JSONObject(String(Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_WRAP)))
            if (payload.optLong("exp") > System.currentTimeMillis() / 1000 + 30) value else null
        } catch (_: Exception) { null }
    }

    private fun open(url: String, callback: String?, result: MethodChannel.Result) {
        pending = result
        val sheet = Dialog(activity, android.R.style.Theme_DeviceDefault_NoActionBar)
        dialog = sheet
        sheet.requestWindowFeature(Window.FEATURE_NO_TITLE)
        val column = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
        val bar = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
        val origin = TextView(activity).apply {
            text = Uri.parse(url).host
            textSize = 14f
            setPadding(16, 12, 8, 12)
        }
        bar.addView(origin, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        bar.addView(Button(activity).apply {
            text = "Close"
            setOnClickListener { finish(null) }
        })
        column.addView(bar)
        fun createBrowser(): WebView {
            return WebView(activity).apply {
                views.add(this)
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.allowFileAccess = false
                settings.allowContentAccess = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                settings.setSupportMultipleWindows(true)
                cookies.setAcceptCookie(true)
                cookies.setAcceptThirdPartyCookies(this, false)
                webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                        if (!request.isForMainFrame) return false
                        val destination = request.url
                        if (callback != null && destination.buildUpon().clearQuery().fragment(null).build().toString() == callback) {
                            finish(destination.toString())
                            return true
                        }
                        // Cookies stay origin-bound in WebView. Do not dispatch
                        // arbitrary intent:, file:, or cleartext navigations.
                        return destination.scheme != "https"
                    }
                    override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                        origin.text = url?.let { Uri.parse(it).host } ?: "Nous sign-in"
                    }
                }
                webChromeClient = object : WebChromeClient() {
                    override fun onCreateWindow(view: WebView, isDialog: Boolean, userGesture: Boolean,
                        resultMsg: android.os.Message): Boolean {
                        if (!userGesture) return false
                        val popup = createBrowser()
                        column.addView(popup, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
                        view.visibility = WebView.GONE
                        (resultMsg.obj as WebView.WebViewTransport).webView = popup
                        resultMsg.sendToTarget()
                        return true
                    }
                    override fun onCloseWindow(window: WebView) {
                        column.removeView(window)
                        views.remove(window)
                        window.destroy()
                        views.lastOrNull()?.visibility = WebView.VISIBLE
                    }
                }
            }
        }
        val browser = createBrowser()
        column.addView(browser, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        sheet.setContentView(column)
        sheet.setOnCancelListener { finish(null) }
        sheet.show()
        sheet.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
            decorView.setOnApplyWindowInsetsListener { v, insets ->
                v.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                insets
            }
        }
        browser.loadUrl(url)
        if (callback == null) {
            val poll = object : Runnable {
                override fun run() {
                    if (pending !== result) return
                    val value = portalCookie()
                    if (value != null) { cookies.flush(); finish(value) }
                    else main.postDelayed(this, 500)
                }
            }
            main.postDelayed(poll, 750)
        }
        main.postDelayed({ if (pending === result) finish(null) }, 5 * 60 * 1000L)
    }

    private fun finish(value: String?) {
        val result = pending
        pending = null
        main.removeCallbacksAndMessages(null)
        dialog?.setOnCancelListener(null)
        dialog?.dismiss()
        dialog = null
        views.forEach { it.stopLoading(); it.destroy() }
        views.clear()
        result?.success(value)
    }

    fun close() { finish(null); channel.setMethodCallHandler(null) }
}
