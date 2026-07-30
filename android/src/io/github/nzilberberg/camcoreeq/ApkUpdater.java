package io.github.nzilberberg.camcoreeq;

// Self-update the NATIVE APK, for the changes the web OTA cannot ship (this shell
// itself). Triggered by WebUpdater when the published manifest's nativeVersion
// exceeds the value baked into the running APK, so ordinary web-only pushes never
// nag. Flow: confirm with the user, download the latest signed CamCoreEQ.apk from
// the GitHub release, hand it to the system package installer. Same signing key, so
// Android does an in-place UPDATE with data preserved -- one tap.
//
// The one unavoidable OS gate for a sideloaded self-update: "install unknown apps"
// must be allowed for this app (API 26+). The user is sent straight to that toggle
// the first time; after that, updates are one tap.
// Ported from the sibling TomeRoam project, where this flow is device-proven.

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

final class ApkUpdater {

    private static final String APK_URL =
        "https://github.com/nzilberberg/CamCoreEQ/releases/latest/download/CamCoreEQ.apk";
    private static final String AUTHORITY = "io.github.nzilberberg.camcoreeq.fileprovider";

    private static boolean prompted = false;   // once per process -- don't nag repeatedly

    private ApkUpdater() {}

    // SOFT: a newer native shell merely exists; the current app still runs fine.
    // Dismissible, shown at most once per process.
    static void prompt(final Activity act) {
        if (prompted || act.isFinishing()) return;
        prompted = true;
        new AlertDialog.Builder(act)
            .setTitle("Update available")
            .setMessage("A new version of CamCoreEQ is ready to install. Update now?")
            .setPositiveButton("Update", (d, w) -> ensurePermissionThenInstall(act))
            .setNegativeButton("Later", null)
            .show();
    }

    // HARD: the latest web build requires a newer shell than this APK has, so the app
    // is pinned to its current older web build until updated. Re-prompts each launch
    // (bypasses the once-per-process guard) and cannot be dismissed by tapping
    // outside. "Not now" keeps the current version working -- the incompatible web
    // build was simply not applied, nothing was broken.
    static void promptRequired(final Activity act) {
        if (act.isFinishing()) return;
        prompted = true;
        new AlertDialog.Builder(act)
            .setTitle("Update required")
            .setMessage("The latest version of CamCoreEQ needs a newer app than the one "
                + "installed. Update the app to keep getting the newest version.")
            .setCancelable(false)
            .setPositiveButton("Update", (d, w) -> ensurePermissionThenInstall(act))
            .setNegativeButton("Not now", null)
            .show();
    }

    // Direct entry for the in-page "Update app" button (camcoreeq://update). No dialog:
    // the user's tap on the button IS the consent the dialogs exist to collect.
    static void startUpdate(final Activity act) {
        ensurePermissionThenInstall(act);
    }

    private static void ensurePermissionThenInstall(final Activity act) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !act.getPackageManager().canRequestPackageInstalls()) {
            Toast.makeText(act, "Allow CamCoreEQ to install updates, then reopen the app",
                    Toast.LENGTH_LONG).show();
            try {
                act.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + act.getPackageName())));
            } catch (Exception e) {
                act.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES));
            }
            return;
        }
        Toast.makeText(act, "Downloading update…", Toast.LENGTH_SHORT).show();
        new Thread(() -> downloadAndInstall(act), "camcoreeq-apk").start();
    }

    private static void downloadAndInstall(final Activity act) {
        File apk = ApkFileProvider.apkFile(act);
        apk.getParentFile().mkdirs();
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(APK_URL).openConnection();
            c.setConnectTimeout(15000);
            c.setReadTimeout(60000);
            c.setInstanceFollowRedirects(true);
            try {
                if (c.getResponseCode() != 200) { toast(act, "Update download failed"); return; }
                try (InputStream in = c.getInputStream(); OutputStream out = new FileOutputStream(apk)) {
                    byte[] buf = new byte[8192];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                }
            } finally { c.disconnect(); }

            if (apk.length() == 0) { toast(act, "Update download failed"); return; }

            Uri uri = Uri.parse("content://" + AUTHORITY + "/CamCoreEQ.apk");
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(uri, "application/vnd.android.package-archive");
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            act.startActivity(i);
        } catch (Exception e) {
            toast(act, "Update failed: " + e.getMessage());
        }
    }

    private static void toast(final Activity act, final String msg) {
        act.runOnUiThread(() -> Toast.makeText(act, msg, Toast.LENGTH_LONG).show());
    }
}
