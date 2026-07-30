package io.github.nzilberberg.camcoreeq;

import android.app.Activity;
import android.os.Bundle;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

/**
 * The shell: a loopback-served WebView, plus an OTA check on launch.
 *
 * Deliberate choices, each with a reason that is easy to lose:
 *
 *  - The document is served over http://127.0.0.1 by LoopbackServer, NOT from an
 *    https asset origin. An insecure WebSocket from a secure page is hard-blocked, and
 *    CamillaDSP offers no TLS -- an https origin would break every connection to the
 *    player. See LoopbackServer's header.
 *
 *  - Mixed content is irrelevant here precisely BECAUSE the origin is insecure, so
 *    setMixedContentMode is not needed. Do not "improve" this by moving to
 *    WebViewAssetLoader; that reintroduces the exact failure it avoids.
 *
 *  - The WebView is hosted in a FrameLayout and the CONTAINER is padded by the system
 *    bar insets. Padding the WebView itself does not work: it anchors position:fixed
 *    elements to its full view box and ignores its own padding, so a fixed bottom bar
 *    still lands under the navigation bar.
 *
 *  - The WebView's own scrollbars are disabled. A WebView is an Android View and draws
 *    its own scrollbars, which CSS cannot reach.
 */
public class MainActivity extends Activity {

    private LoopbackServer server;
    private WebView web;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        server = new LoopbackServer(this);
        try {
            server.start();
        } catch (Exception e) {
            // Fail loudly. A silent failure here looks like "the app is broken" with no
            // cause, and the fixed port is intentional (localStorage is per-origin).
            Toast.makeText(this,
                    "CamCoreEQ could not start its local server on port "
                            + LoopbackServer.PORT + ". Another app may be using it.",
                    Toast.LENGTH_LONG).show();
            return;
        }

        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);          // the app stores its UI prefs and the player address
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);  // the OTA swap replaces bytes behind the same URL

        // ---- viewport parity with a browser -------------------------------------
        // WebView defaults setUseWideViewPort to FALSE, and with it false the engine
        // IGNORES the page's <meta name="viewport"> entirely -- including this app's
        // "width=device-width, initial-scale=1". The page is then laid out and scaled
        // by WebView's own rules instead of its own declaration, which is why the UI
        // scaled and laid out differently here than in a browser. Turning it on is what
        // makes the WebView honour the document, not an enhancement.
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);   // fit the declared viewport to the view on load
        // A browser lets you pinch-zoom a dense control surface; WebView does not unless
        // asked. Enable the gesture but not the deprecated on-screen +/- buttons.
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        // Pin text scaling. WebView applies its own font boosting/system text scaling,
        // which is a second, independent source of "text is a different size than the
        // browser" once the viewport itself is correct.
        s.setTextZoom(100);
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        // Publish the SHELL version into the page so the UI can show it. Without this
        // there is no way to tell from the app which native version is installed, only
        // which web build is being served -- and with two independent update tracks that
        // is the first question when someone reports "installing the update changed
        // nothing". Injected rather than exposed via addJavascriptInterface: this is a
        // one-way constant, and an interface would add a callable surface for no reason.
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String url) {
                // Kept for compatibility: shells v3/v4 published EQ_NATIVE this way and
                // the diagnostics code reads it. New code should prefer the bridge
                // below, which is available from document start rather than after load.
                v.evaluateJavascript(
                    "window.EQ_NATIVE=" + WebUpdater.NATIVE_VERSION + ";", null);
            }
        });

        // Bridge exposed as window.CamCoreEQNative -- the same pattern the sibling
        // TomeRoam project device-proved (its AppBridge). Deliberately tiny: only
        // @JavascriptInterface methods are reachable from the page, and the page
        // FEATURE-DETECTS it (window.CamCoreEQNative && CamCoreEQNative.updateApp), so
        // an older shell simply shows no button -- no version arithmetic in the page,
        // and no URL-scheme navigation for an old shell to trip over. Installed before
        // loadUrl, so unlike the onPageFinished injection it exists at document start.
        web.addJavascriptInterface(new AppBridge(), "CamCoreEQNative");

        FrameLayout root = new FrameLayout(this);
        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        // targetSdk 35 forces edge-to-edge, so the WebView would otherwise draw behind
        // the system bars. Pad the CONTAINER, and hand the child zeroed insets.
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets.inset(bars);
        });

        setContentView(root);
        web.loadUrl(server.origin() + "/");

        // Web OTA, the TomeRoam way. At LAUNCH a found update applies IN PLACE -- the
        // loopback server already serves the committed copy, so one reload lands it;
        // seconds after open the user has nothing in progress to lose, and telling
        // them to restart the app they just started was strictly worse UX.
        WebUpdater.checkAsync(this, (newBuild, message) -> runOnUiThread(() -> {
            if (newBuild != null) web.loadUrl(server.origin() + "/");
        }));
    }

    // A build published WHILE the app is open is found on the next return to the app.
    // It is NOT auto-applied -- the user may be mid-edit -- it lights the Settings
    // "Apply update" button instead (stagedWebBuild/applyWebUpdate on the bridge),
    // which is exactly how TomeRoam's Options button behaves.
    private String stagedWeb = null;
    private boolean firstResume = true;

    @Override
    protected void onResume() {
        super.onResume();
        if (firstResume) { firstResume = false; return; }   // onCreate's check covers launch
        if (web == null) return;
        WebUpdater.checkAsync(this, (newBuild, message) -> runOnUiThread(() -> {
            if (newBuild != null) {
                stagedWeb = newBuild;
                Toast.makeText(this, "CamCoreEQ " + newBuild
                        + " ready - apply it in Settings", Toast.LENGTH_LONG).show();
            }
        }));
    }

    // Only @JavascriptInterface methods are reachable from JS. Kept intentionally tiny.
    private final class AppBridge {
        @android.webkit.JavascriptInterface
        public int nativeVersion() { return WebUpdater.NATIVE_VERSION; }

        // The Settings "Update app" button: download the latest signed APK and hand it
        // to the system installer. The user's tap is the consent.
        @android.webkit.JavascriptInterface
        public void updateApp() {
            runOnUiThread(() -> ApkUpdater.startUpdate(MainActivity.this));
        }

        // A web build committed while this session was already running (found by the
        // onResume re-check), or "" when the running page is current.
        @android.webkit.JavascriptInterface
        public String stagedWebBuild() { return stagedWeb == null ? "" : stagedWeb; }

        // Apply it in place: the loopback server already serves the committed copy,
        // so a reload is the whole operation. Tap = consent, same as TomeRoam.
        @android.webkit.JavascriptInterface
        public void applyWebUpdate() {
            runOnUiThread(() -> {
                stagedWeb = null;
                web.loadUrl(server.origin() + "/");
            });
        }
    }

    @Override
    public void onBackPressed() {
        // The app is a single page with its own internal navigation; a back gesture
        // should not walk the WebView history out from under it.
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (server != null) server.stop();
        super.onDestroy();
    }
}
