/**
 * ImageCacheProvider.java – Below is a self-contained helper that turns a public https://… image 
 * URL into a content://… URI you can safely feed to Jetpack Car-App. It downloads the file once 
 * (into your app’s cache), then hands back a Uri produced by a private FileProvider.
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */
package io.s2a.connect;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Utility to fetch a remote image <https://…> and expose it as a
 * content:// URI via FileProvider.  Intended for Car-App list rows.
 *
 * Usage (from ListViewScreen):
 * ImageCacheProvider.fetch(context, imageUrl, uri -> row.setImage(
 *         new CarIcon.Builder(IconCompat.createWithContentUri(uri)).build()));
 */
public final class ImageCacheProvider {
    private static final Map<String, List<Callback>> inFlight = new HashMap<>();
    private static final String TAG = "CarConnect.ImageCache";

    public interface Callback {
        void onReady(@NonNull Uri contentUri);
        default void onError(@NonNull Exception e) { /* optional */ }
    }

    private static final String AUTHORITY_SUFFIX = ".cdv.core.file.provider";

    private ImageCacheProvider() { }

    /** Asynchronously download + cache the image, then invoke the callback. */
    public static void fetch(Context ctx, String url, Callback cb) {
        Log.d(TAG, "fetch → " + url);

        File cacheFile = new File(ctx.getCacheDir(),
                          Integer.toHexString(url.hashCode()) + ".img");
        if (cacheFile.exists()) {                      // ← quick exit
            Uri uri = FileProvider.getUriForFile(
                 ctx, ctx.getPackageName() + AUTHORITY_SUFFIX, cacheFile);
            new Handler(Looper.getMainLooper()).post(() -> cb.onReady(uri));
            return;
        }

        synchronized (inFlight) {
            // somebody else already started the download → just queue our callback
            if (inFlight.containsKey(url)) {
                inFlight.get(url).add(cb);
                return;
            }
            inFlight.put(url, new ArrayList<>(List.of(cb)));
        }

        new Thread(() -> {
            Uri uri = null; Exception err = null;
            try { uri = downloadToCache(ctx, url); }
            catch (Exception e) { err = e; }

            Log.d(TAG, "→ downloaded & cached: " + uri);

            // deliver the result to *all* waiting callbacks
            List<Callback> cbs;
            synchronized (inFlight) { cbs = inFlight.remove(url); }
            Handler h = new Handler(Looper.getMainLooper());
            for (Callback c : cbs) {
                Uri finalUri = uri; Exception finalErr = err;
                h.post(() -> {
                    if (finalErr == null) c.onReady(finalUri);
                    else                  c.onError(finalErr);
                });
            }
        }).start();
    }

    // ------------------------------------------------------------------ //
    // Internal helpers
    // ------------------------------------------------------------------ //
    private static Uri downloadToCache(Context ctx, String urlStr) throws Exception {
        String fileName = Integer.toHexString(urlStr.hashCode()) + ".img";
        File cacheFile  = new File(ctx.getCacheDir(), fileName);

        if (cacheFile.exists()) {               // <-- fast path
            String authority = ctx.getPackageName() + AUTHORITY_SUFFIX;
            return FileProvider.getUriForFile(ctx, authority, cacheFile);
        }

        URL url = new URL(urlStr);
        HttpURLConnection con = (HttpURLConnection) url.openConnection();
        con.setConnectTimeout(8000);
        con.setReadTimeout(8000);
        con.connect();

        if (con.getResponseCode() != HttpURLConnection.HTTP_OK) {
            throw new Exception("HTTP " + con.getResponseCode());
        }

        try (InputStream in = con.getInputStream();
             FileOutputStream out = new FileOutputStream(cacheFile)) {
            byte[] buf = new byte[8 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        } finally {
            con.disconnect();
        }

        String authority = ctx.getPackageName() + AUTHORITY_SUFFIX;
        return FileProvider.getUriForFile(ctx, authority, cacheFile);
    }
}
