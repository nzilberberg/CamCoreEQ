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
                v.evaluateJavascript(
                    "window.EQ_NATIVE=" + WebUpdater.NATIVE_VERSION + ";", null);
            }
        });

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

        // Silent OTA: if a newer build is published, store it and use it on next launch.
        // Never swaps under the user mid-session -- an EQ editor reloading itself while
        // someone is dragging a band would lose their edit.
        WebUpdater.checkAsync(this, (newBuild, message) -> runOnUiThread(() -> {
            if (newBuild != null) {
                Toast.makeText(this, "CamCoreEQ " + newBuild
                        + " downloaded - restart the app to use it", Toast.LENGTH_LONG).show();
            }
        }));
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
