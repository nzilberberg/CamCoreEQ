package io.github.nzilberberg.camcoreeq;

import android.content.Context;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Where the web app lives, and which copy wins.
 *
 * Two copies exist:
 *   - the BUNDLED one in assets/www/, shipped inside the APK. Always present, so the
 *     app is fully functional with no network and on first launch.
 *   - a DOWNLOADED one in filesDir/web/, written by WebUpdater after a successful OTA.
 *
 * The downloaded copy wins, but only when it is complete AND newer. "Complete" is
 * enforced by writing to a temp file and renaming into place, so a connection dropped
 * mid-download can never leave a truncated document that the loopback server would
 * then serve as the app. "Newer" is decided by comparing the manifest build string,
 * never by file timestamps.
 */
final class WebStore {

    private static final String DOC = "index.html";
    private static final String MAN = "build.json";

    private WebStore() {}

    static File webDir(Context c) {
        File d = new File(c.getFilesDir(), "web");
        if (!d.exists()) d.mkdirs();
        return d;
    }

    private static File downloadedDoc(Context c) { return new File(webDir(c), DOC); }
    private static File downloadedMan(Context c) { return new File(webDir(c), MAN); }

    /** True when a complete downloaded pair is present. */
    static boolean hasDownload(Context c) {
        File d = downloadedDoc(c), m = downloadedMan(c);
        return d.isFile() && d.length() > 0 && m.isFile() && m.length() > 0;
    }

    /**
     * Numeric rank of a "bNNN" build string, or -1 when it cannot be read.
     * Builds are ordered, so an ordering is what decides which copy is newer -- not
     * merely the presence of a download.
     */
    static int buildRank(String build) {
        if (build == null) return -1;
        StringBuilder n = new StringBuilder();
        for (int i = 0; i < build.length(); i++) {
            char ch = build.charAt(i);
            if (Character.isDigit(ch)) n.append(ch);
            else if (n.length() > 0) break;
        }
        if (n.length() == 0) return -1;
        try { return Integer.parseInt(n.toString()); } catch (Exception e) { return -1; }
    }

    /**
     * Pure decision: should the downloaded copy be served instead of the bundled one?
     *
     * THE BUG THIS FIXES: this used to be "is there a download?", which meant that after
     * an APK upgrade a STALE downloaded copy permanently shadowed the NEWER copy shipped
     * inside the new APK. Installing a new app version then appeared to change nothing.
     *
     * Ties go to the BUNDLE, and so does any unparseable build on either side: the
     * bundled copy is the signed artifact, so it is the safer default whenever the
     * ordering is not clear.
     */
    static boolean preferDownload(String downloadedBuild, String bundledBuild) {
        int dl = buildRank(downloadedBuild), bd = buildRank(bundledBuild);
        if (dl < 0) return false;
        if (bd < 0) return false;
        return dl > bd;
    }

    /** True when a complete download exists AND is newer than what the APK bundles. */
    private static boolean useDownload(Context c) {
        if (!hasDownload(c)) return false;
        String dl, bd;
        try { dl = buildOf(new String(LoopbackServer.readFile(downloadedMan(c)), "UTF-8")); }
        catch (Exception e) { return false; }
        try { bd = buildOf(new String(asset(c, "www/" + MAN), "UTF-8")); }
        catch (Exception e) { return false; }
        return preferDownload(dl, bd);
    }

    static byte[] currentDocument(Context c) throws IOException {
        if (useDownload(c)) return LoopbackServer.readFile(downloadedDoc(c));
        return asset(c, "www/" + DOC);
    }

    static byte[] currentManifest(Context c) throws IOException {
        if (useDownload(c)) return LoopbackServer.readFile(downloadedMan(c));
        return asset(c, "www/" + MAN);
    }

    static byte[] asset(Context c, String name) throws IOException {
        try (InputStream in = c.getAssets().open(name)) { return LoopbackServer.readAll(in); }
    }

    /** The build id of whatever is currently being served. */
    static String currentBuild(Context c) {
        try { return buildOf(new String(currentManifest(c), "UTF-8")); }
        catch (Exception e) { return ""; }
    }

    /**
     * Pulls "build" out of the manifest without a JSON library. The manifest is written
     * by this project and its shape is fixed, so a targeted scan is honest here -- but
     * it returns "" rather than guessing when the field is absent, and an empty build is
     * treated as "do not swap" by the caller.
     */
    static String buildOf(String json) {
        if (json == null) return "";
        int i = json.indexOf("\"build\"");
        if (i < 0) return "";
        int c = json.indexOf(':', i);
        if (c < 0) return "";
        int q1 = json.indexOf('"', c);
        if (q1 < 0) return "";
        int q2 = json.indexOf('"', q1 + 1);
        if (q2 < 0) return "";
        return json.substring(q1 + 1, q2).trim();
    }

    static int intField(String json, String field, int fallback) {
        if (json == null) return fallback;
        int i = json.indexOf("\"" + field + "\"");
        if (i < 0) return fallback;
        int c = json.indexOf(':', i);
        if (c < 0) return fallback;
        int e = c + 1;
        StringBuilder n = new StringBuilder();
        while (e < json.length()) {
            char ch = json.charAt(e++);
            if (Character.isDigit(ch)) n.append(ch);
            else if (n.length() > 0) break;
            else if (ch == ',' || ch == '}') break;
        }
        try { return Integer.parseInt(n.toString()); } catch (Exception ex) { return fallback; }
    }

    /**
     * Commit a downloaded pair atomically. Both files are written to temp names first
     * and only renamed once BOTH are complete, so the store never holds a document from
     * one build alongside a manifest from another.
     */
    static void commit(Context c, byte[] doc, byte[] man) throws IOException {
        File dir = webDir(c);
        File dTmp = new File(dir, DOC + ".tmp"), mTmp = new File(dir, MAN + ".tmp");
        write(dTmp, doc);
        write(mTmp, man);
        File d = downloadedDoc(c), m = downloadedMan(c);
        // Rename the document LAST: if the process dies between the two renames, a new
        // manifest beside an old document would claim a build that is not being served.
        if (!mTmp.renameTo(m)) { mTmp.delete(); dTmp.delete(); throw new IOException("manifest rename failed"); }
        if (!dTmp.renameTo(d)) { dTmp.delete(); throw new IOException("document rename failed"); }
    }

    private static void write(File f, byte[] b) throws IOException {
        try (FileOutputStream fos = new FileOutputStream(f)) { fos.write(b); fos.flush(); fos.getFD().sync(); }
    }

    /** Discard any downloaded copy and fall back to the bundled one. */
    static void reset(Context c) {
        File dir = webDir(c);
        File[] fs = dir.listFiles();
        if (fs != null) for (File f : fs) f.delete();
    }
}
