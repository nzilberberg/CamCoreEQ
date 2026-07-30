package io.github.nzilberberg.camcoreeq;

import android.content.Context;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Over-the-air update of the web app.
 *
 * WHY THIS IS NATIVE AND NOT AN IN-PAGE fetch() -- GitHub Pages sends no
 * Access-Control-Allow-Origin header, so a fetch() issued by the page (whose origin is
 * the loopback server) would be refused by CORS. Native HTTP is not subject to CORS at
 * all. This is the reason the updater lives in Java rather than in index.html.
 *
 * Ordering matters and is deliberate:
 *   1. fetch the manifest, no-store
 *   2. compare its build to what is being served; stop if equal
 *   3. refuse if the build requires a newer shell than this one (minNativeVersion)
 *   4. only then fetch the document, and commit both atomically
 *
 * Failure is always silent-and-safe: on any error the stored copy keeps serving. A LAN
 * with no internet is the normal case for this app, not an exception.
 */
final class WebUpdater {

    /** Published by GitHub Pages from the repository root. */
    private static final String BASE = "https://nzilberberg.github.io/CamCoreEQ/";
    private static final int TIMEOUT_MS = 8000;

    /** The shell's own version. Raise it, versionCode and build.json's nativeVersion together. */
    static final int NATIVE_VERSION = 6;

    interface Listener {
        /** Called on a worker thread. newBuild is null when nothing changed. */
        void onResult(String newBuild, String message);
    }

    private WebUpdater() {}

    static void checkAsync(final Context ctx, final Listener l) {
        // Route native updates like the sibling TomeRoam project, where this flow is
        // device-proven: a HARD prompt when the published web build needs a newer shell
        // (the web build is then NOT applied -- the app keeps working on its current
        // one), a SOFT dismissible prompt when a newer shell merely exists, and in the
        // ordinary case the web build updates silently with no dialog at all.
        final android.app.Activity act =
                (ctx instanceof android.app.Activity) ? (android.app.Activity) ctx : null;
        new Thread(() -> {
            try {
                String manJson = new String(get(BASE + "build.json"), "UTF-8");
                String remote = WebStore.buildOf(manJson);
                String local = WebStore.currentBuild(ctx);

                if (remote.isEmpty()) { l.onResult(null, "no build id in the published manifest"); return; }

                int remoteNative = WebStore.intField(manJson, "nativeVersion", NATIVE_VERSION);
                int floor = WebStore.intField(manJson, "minNativeVersion", 1);

                if (floor > NATIVE_VERSION) {
                    // The new web build cannot run on this shell: route straight to the
                    // APK downloader and leave the current web build in place.
                    if (act != null) act.runOnUiThread(() -> ApkUpdater.promptRequired(act));
                    l.onResult(null, "build " + remote + " needs app version " + floor
                            + "; this app is " + NATIVE_VERSION);
                    return;
                }
                if (remoteNative > NATIVE_VERSION && act != null) {
                    // A newer shell exists but is not required: offer it once, and still
                    // take the web update below.
                    act.runOnUiThread(() -> ApkUpdater.prompt(act));
                }

                if (remote.equals(local)) { l.onResult(null, "up to date (" + local + ")"); return; }

                byte[] doc = get(BASE + "index.html");
                // A document that does not identify itself is not installed. Cheap, but it
                // catches a Pages 404 page or a captive-portal interception, either of
                // which would otherwise be committed as "the app".
                String head = new String(doc, 0, Math.min(doc.length, 4096), "UTF-8");
                if (!head.contains("<title>CamCoreEQ</title>")) {
                    l.onResult(null, "downloaded document is not CamCoreEQ; ignored");
                    return;
                }
                WebStore.commit(ctx, doc, manJson.getBytes("UTF-8"));
                l.onResult(remote, "updated to " + remote);
            } catch (Exception e) {
                l.onResult(null, "update check failed: " + e.getClass().getSimpleName());
            }
        }, "camcoreeq-ota").start();
    }

    private static byte[] get(String url) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try {
            c.setConnectTimeout(TIMEOUT_MS);
            c.setReadTimeout(TIMEOUT_MS);
            c.setRequestProperty("Cache-Control", "no-store");
            c.setInstanceFollowRedirects(true);
            int code = c.getResponseCode();
            if (code != 200) throw new IOException("HTTP " + code + " for " + url);
            try (InputStream in = c.getInputStream()) { return LoopbackServer.readAll(in); }
        } finally {
            c.disconnect();
        }
    }
}
