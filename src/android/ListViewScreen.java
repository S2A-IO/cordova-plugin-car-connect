/**
 * ListViewScreen.java – Renders a scrollable list in Android Auto
 * 
 * <p>This Screen receives the JSON payload forwarded from the Cordova bridge
 * (via {@code CarConnect.showListView}) and converts it into an Android‐Auto
 * {@link androidx.car.app.model.ListTemplate}. When the user taps a row we
 * notify the JavaScript layer through Cordova’s {@link
 * org.apache.cordova.CallbackContext}.</p>
 *
 * <h3>Expected JSON payload</h3>
 * <pre>
 * {
 *   "items": [
 *     {
 *       "id":    42,
 *       "image": "file:///path/to/icon.png",  // optional – can be content:// or https://
 *       "title": "Item title",
 *       "description": "Short description"
 *     }
 *   ]
 * }
 * </pre>
 * <p>The entire <code>JSONObject</code> for the tapped row is echoed back to
 * JavaScript via <code>CallbackContext.success(String)</code>.</p>
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */

package io.s2a.connect;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.InputStream;

import android.content.Intent;
import android.net.Uri;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.CarIcon;
import androidx.car.app.model.ItemList;
import androidx.car.app.model.ListTemplate;
import androidx.car.app.model.Row;
import androidx.core.graphics.drawable.IconCompat;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONException;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.HashMap;

/**
 * Screen responsible for displaying a list of rows.
 * ──────────────────────────────────────────────────────────────────────────
 * • Accepts https:// images – they’re downloaded once via {@link ImageCacheProvider},
 *   turned into a content:// URI, then injected into the row and the template
 *   is refreshed with {@link #invalidate()}.
 * • Local resource / file / content-scheme URIs are still used directly.
 */
public class ListViewScreen extends Screen {
    private static final String TAG = "CarConnect.ListScreen";

    private JSONObject payloadJson;
    private CallbackContext callback;
    private ListTemplate template;

    // One CarIcon per image URL – survives template rebuilds
    private final Map<String, CarIcon> iconCache = new HashMap<>();

    /**
     * Builds a {@link ListViewScreen} from the items JSON.
     *
     * @param ctx      Current {@link CarContext}
     * @param payload  JSON object containing an "items" array.
     * @param cb       Cordova callback to notify when a row is tapped.
     */
    public ListViewScreen(@NonNull CarContext ctx, @NonNull JSONObject payload,
                          @NonNull CallbackContext cb) throws JSONException {
        super(ctx);
        this.payloadJson = payload;
        this.callback = cb;
        this.template = buildTemplate(ctx, payload, cb);
    }

    @NonNull
    @Override
    public androidx.car.app.model.Template onGetTemplate() {
        return template;
    }

    // ------------------------------------------------------------------
    //  Helpers
    // ------------------------------------------------------------------

    private ListTemplate buildTemplate(CarContext ctx, JSONObject payload,
                                              CallbackContext cb) throws JSONException {
        JSONArray arr = payload.optJSONArray("items");
        if (arr == null || arr.length() == 0) {
            throw new JSONException("items array missing or empty in showListView payload");
        }

        ItemList.Builder listBuilder = new ItemList.Builder();
        List<Row> rows = new ArrayList<>(arr.length());

        for (int i = 0; i < arr.length(); i++) {
            JSONObject item = arr.getJSONObject(i);
            Row row = buildRow(ctx, item, cb);
            rows.add(row);
        }

        // Car UI guideline: must set isBrowsable = true for lists w/ > 6 items
        for (Row row : rows) {
            listBuilder.addItem(row);
        }
        listBuilder.setNoItemsMessage("No items available");

        return new ListTemplate.Builder()
                .setSingleList(listBuilder.build())
                .setTitle("Select an item")
                .build();
    }

    /**
     * Builds a single row. If the "image" is https:// it is downloaded
     * asynchronously; when ready we rebuild the ListTemplate and call
     * {@link #invalidate()} so the UI refreshes.
     */
    private Row buildRow(CarContext ctx, JSONObject item, CallbackContext cb) throws JSONException {
        final String title = item.optString("title", "");
        final String desc  = item.optString("description", "");
        final String img   = item.optString("image", null);

        final Row.Builder builder = new Row.Builder()
                .setTitle(title)
                .addText(desc);

        builder.setOnClickListener(() -> {
            PluginResult pr = new PluginResult(
                PluginResult.Status.OK,
                item.toString()            // JSON for the tapped row
            );
            pr.setKeepCallback(true);          // <-- keep channel open
            cb.sendPluginResult(pr);           // do NOT call cb.success(...)
        });

        // Icon already cached → use it and exit early.
        if (img != null && iconCache.containsKey(img)) {
            builder.setImage(iconCache.get(img), Row.IMAGE_TYPE_LARGE);
            return builder.build();
        }

        if (img != null && !img.isEmpty()) {
            Uri uri = Uri.parse(img);
            String scheme = uri.getScheme() == null ? "" : uri.getScheme();

            switch (scheme) {
                case "http":
                case "https":
                    // Asynchronously download, then refresh
                    ImageCacheProvider.fetch(ctx, img, new ImageCacheProvider.Callback() {
                        @Override 
                        public void onReady(@NonNull Uri contentUri) {
                            try (InputStream is = ctx.getContentResolver().openInputStream(contentUri)) {
                                Bitmap bmp = BitmapFactory.decodeStream(is);

                                // scale to Auto's small-icon size (48 dp ≈ 48 px on mdpi host)
                                Bitmap scaled = Bitmap.createScaledBitmap(bmp, 80, 80, true);

                                CarIcon icon = new CarIcon.Builder(
                                    IconCompat.createWithBitmap(scaled)).build();
                                iconCache.put(img, icon);

                                template = buildTemplate(ctx, payloadJson, cb);
                                invalidate();
                            } catch (Exception e) {
                                Log.w(TAG, "decode failed", e);
                            }
                        }
                    });
                    break;

                case "file":
                case "content":
                case "android.resource":
                    CarIcon icon = new CarIcon.Builder(
                            IconCompat.createWithContentUri(uri)).build();
                    builder.setImage(icon, Row.IMAGE_TYPE_ICON);

                    iconCache.put(img, icon);
                    break;

                default:
                    // Unsupported scheme – leave row without image
            }
        }

        return builder.build();
    }

    /**
     * Public refresh helper  (called from CarConnectService)
     */
    public void update(@NonNull JSONObject newPayload) {
        try {
            this.payloadJson = newPayload;
            this.template    = buildTemplate(getCarContext(), newPayload, callback);
            invalidate();          // tell the framework to call onGetTemplate() again
        } catch (JSONException e) {
            Log.w(TAG, "Bad payload for ListViewScreen.update", e);
        }
    }
}