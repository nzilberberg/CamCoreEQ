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
        web.setVerticalScrollBarEnabled(false);
        web.setHorizontalScrollBarEnabled(false);
        web.setWebViewClient(new WebViewClient());

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
