package com.tarkilhk.wing.shareqa.fixture;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** A foreign UID's nonexported provider; Android must convey an explicit grant. */
public final class ProbeProvider extends ContentProvider {
    static final String AUTHORITY = "com.tarkilhk.wing.shareqa.fixture.files";
    static final String CONTENTS = "Wing external share boundary — ✓\n";
    private File blob;

    @Override public boolean onCreate() {
        blob = new File(getContext().getFilesDir(), "wing-share-probe.txt");
        try (FileOutputStream stream = new FileOutputStream(blob)) {
            stream.write(CONTENTS.getBytes(StandardCharsets.UTF_8));
            return true;
        } catch (Exception error) {
            throw new IllegalStateException("Cannot create owned provider fixture", error);
        }
    }

    private synchronized void count(String operation, Uri uri) {
        SharedPreferences preferences = getContext().getSharedPreferences("probe", 0);
        if (!preferences.edit()
                .putInt(operation, preferences.getInt(operation, 0) + 1)
                .putString("last_uri", uri.toString()).commit()) {
            throw new IllegalStateException("Cannot record provider observation");
        }
    }

    @Override public String getType(Uri uri) {
        count("type", uri);
        return "text/plain";
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] selectionArgs, String sortOrder) {
        count("query", uri);
        String[] columns = projection == null
                ? new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
        MatrixCursor cursor = new MatrixCursor(columns);
        Object[] row = new Object[columns.length];
        for (int index = 0; index < columns.length; index++) {
            if (OpenableColumns.DISPLAY_NAME.equals(columns[index])) row[index] = blob.getName();
            if (OpenableColumns.SIZE.equals(columns[index])) row[index] = blob.length();
        }
        cursor.addRow(row);
        return cursor;
    }

    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        count("open", uri);
        if (!"r".equals(mode) || !uri.getPath().startsWith("/blob/")) {
            throw new FileNotFoundException("Only the owned read fixture is available");
        }
        return ParcelFileDescriptor.open(blob, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
