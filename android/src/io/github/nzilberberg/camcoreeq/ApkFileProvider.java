package io.github.nzilberberg.camcoreeq;

// A minimal content provider so the system package installer can read the downloaded
// update APK. AndroidX's FileProvider is not available in this dependency-free
// (raw aapt2/javac/d8) build, so this serves the one update file itself: openFile()
// hands over a read-only descriptor and query() answers the installer's
// OpenableColumns (name + size). Grants are per-Intent; no other file is exposed.
// Ported from the sibling TomeRoam project, where this flow is device-proven.

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

public class ApkFileProvider extends ContentProvider {

    static File apkFile(android.content.Context ctx) {
        return new File(new File(ctx.getCacheDir(), "update"), "CamCoreEQ.apk");
    }

    @Override public boolean onCreate() { return true; }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        return ParcelFileDescriptor.open(apkFile(getContext()), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
        File f = apkFile(getContext());
        String[] cols = { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE };
        MatrixCursor cur = new MatrixCursor(cols, 1);
        cur.addRow(new Object[] { "CamCoreEQ.apk", f.length() });
        return cur;
    }

    @Override public String getType(Uri uri) { return "application/vnd.android.package-archive"; }
    @Override public Uri insert(Uri uri, ContentValues v) { return null; }
    @Override public int delete(Uri uri, String s, String[] a) { return 0; }
    @Override public int update(Uri uri, ContentValues v, String s, String[] a) { return 0; }
}
