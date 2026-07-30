package io.github.nzilberberg.camcoreeq;

import android.content.Context;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;

/**
 * A minimal loopback HTTP server that serves the single-page app to the WebView.
 *
 * WHY THIS EXISTS AT ALL -- this is the load-bearing design decision of the whole
 * shell, so it is written down here rather than discovered later:
 *
 *   The app talks to CamillaDSP over `ws://<player>:1234` and to the player's CGI
 *   scripts over `http://<player>:8080`. An insecure WebSocket from a SECURE page is
 *   active mixed content: hard-blocked by the engine, never upgraded. CamillaDSP has
 *   no TLS listener, so there is nothing to upgrade to. Therefore the document must
 *   NOT be served from an https:// origin -- which rules out WebViewAssetLoader
 *   (https://appassets.androidplatform.net) and rules out pointing the WebView at the
 *   GitHub Pages copy. Either would produce an app that launches and then cannot
 *   reach the player at all.
 *
 *   file:// would be insecure enough, but its origin is opaque, WebView blocks fetch
 *   from it without the broad deprecated setAllowUniversalAccessFromFileURLs, and
 *   localStorage keyed to an opaque origin is fragile.
 *
 *   A loopback http:// origin avoids all of that: insecure (so ws:// is allowed),
 *   a real origin (so localStorage and fetch behave normally), and no deprecated
 *   switches.
 *
 * The port is FIXED, deliberately. The document origin includes the port, and
 * localStorage is per-origin -- a port that varied between launches would silently
 * discard the user's settings every time the app started. If the port is unavailable
 * we fail loudly rather than drift to another one.
 */
final class LoopbackServer {

    /** Fixed on purpose: the origin (and therefore localStorage) depends on it. */
    static final int PORT = 8731;

    private final Context ctx;
    private ServerSocket socket;
    private Thread thread;
    private volatile boolean running;

    LoopbackServer(Context ctx) { this.ctx = ctx; }

    String origin() { return "http://127.0.0.1:" + PORT; }

    /** @throws IOException if the fixed port is unavailable -- caller must surface this. */
    void start() throws IOException {
        socket = new ServerSocket(PORT, 8, InetAddress.getByName("127.0.0.1"));
        running = true;
        thread = new Thread(this::loop, "camcoreeq-loopback");
        thread.setDaemon(true);
        thread.start();
    }

    void stop() {
        running = false;
        try { if (socket != null) socket.close(); } catch (IOException ignored) {}
    }

    private void loop() {
        while (running) {
            try (Socket c = socket.accept()) {
                serve(c);
            } catch (IOException e) {
                if (running) { /* a dropped connection is normal; keep serving */ }
            }
        }
    }

    private void serve(Socket c) throws IOException {
        InputStream in = c.getInputStream();
        StringBuilder line = new StringBuilder();
        int b;
        while ((b = in.read()) != -1 && b != '\n') { if (b != '\r') line.append((char) b); }
        String req = line.toString();

        // Only the app document is served. Everything the page actually talks to lives
        // on the player and is fetched cross-origin directly by the page.
        String path = "/";
        String[] parts = req.split(" ");
        if (parts.length >= 2) path = parts[1];
        int q = path.indexOf('?');
        if (q >= 0) path = path.substring(0, q);

        byte[] body;
        String type = "text/html; charset=utf-8";
        if ("/".equals(path) || "/index.html".equals(path)) {
            body = WebStore.currentDocument(ctx);
        } else if ("/build.json".equals(path)) {
            body = WebStore.currentManifest(ctx);
            type = "application/json";
        } else {
            byte[] nf = "not found".getBytes("UTF-8");
            write(c.getOutputStream(), "404 Not Found", "text/plain", nf);
            return;
        }
        write(c.getOutputStream(), "200 OK", type, body);
    }

    private void write(OutputStream out, String status, String type, byte[] body) throws IOException {
        StringBuilder h = new StringBuilder();
        h.append("HTTP/1.1 ").append(status).append("\r\n");
        h.append("Content-Type: ").append(type).append("\r\n");
        h.append("Content-Length: ").append(body.length).append("\r\n");
        // The document must never be cached by the WebView: an OTA swap replaces the
        // bytes behind this same URL, and a cached copy would keep the old build alive.
        h.append("Cache-Control: no-store, must-revalidate\r\n");
        h.append("Connection: close\r\n\r\n");
        out.write(h.toString().getBytes("UTF-8"));
        out.write(body);
        out.flush();
    }

    /** Reads a whole stream; small files only (the document is ~190KB). */
    static byte[] readAll(InputStream in) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) bos.write(buf, 0, n);
        return bos.toByteArray();
    }

    static byte[] readFile(File f) throws IOException {
        try (FileInputStream fis = new FileInputStream(f)) { return readAll(fis); }
    }
}
