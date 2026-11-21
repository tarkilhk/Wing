package com.tarkilhk.wing.shareqa.fixture;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/** Separate UID proves the chooser grants readable ZIP bytes after source cleanup. */
public final class DiagnosticReceiveActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        try {
            Intent intent = getIntent();
            if (!Intent.ACTION_SEND.equals(intent.getAction()) || !"application/zip".equals(intent.getType()))
                throw new IllegalArgumentException("Expected ZIP share");
            Uri source = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (source == null || !"content".equals(source.getScheme()))
                throw new IllegalArgumentException("Expected granted content URI");
            try (InputStream input = getContentResolver().openInputStream(source);
                 FileOutputStream output = new FileOutputStream(new File(getFilesDir(), "diagnostics.zip"))) {
                byte[] bytes = new byte[8192];
                int total = 0, count;
                while ((count = input.read(bytes)) != -1) {
                    total += count;
                    if (total > 4 * 1024 * 1024) throw new IllegalArgumentException("Oversized diagnostic ZIP");
                    output.write(bytes, 0, count);
                }
            }
            getSharedPreferences("diagnostics", MODE_PRIVATE).edit().putBoolean("received", true).commit();
        } catch (Exception error) {
            getSharedPreferences("diagnostics", MODE_PRIVATE).edit().putString("error", error.toString()).commit();
        }
        finish();
    }
}
