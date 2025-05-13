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
import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONException;

import java.util.ArrayList;
import java.util.List;

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

    private final JSONObject payloadJson;
    private ListTemplate template;

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
                .addText(desc)
                .setOnClickListener(() -> cb.success(item.toString()));

        if (img != null && !img.isEmpty()) {
            Uri uri = Uri.parse(img);
            String scheme = uri.getScheme() == null ? "" : uri.getScheme();

            switch (scheme) {
                case "http":
                case "https":
                    Log.d(TAG, "remote image: " + img);

                    // Asynchronously download, then refresh
                    ImageCacheProvider.fetch(ctx, img, new ImageCacheProvider.Callback() {
                        @Override 
                        public void onReady(@NonNull Uri contentUri) {
                            Log.d(TAG, "icon ready: " + contentUri);

                            CarIcon icon = new CarIcon.Builder(
                            IconCompat.createWithContentUri(contentUri)).build();
                            builder.setImage(icon, Row.IMAGE_TYPE_ICON);

                            try {
                                // rebuild template now that at least one image is cached
                                template = ListViewScreen.this.buildTemplate(ctx, payloadJson, cb);
                            } catch (JSONException ignored) { }

                            // ask the framework to re-query onGetTemplate()
                            ListViewScreen.this.invalidate();
                        }
                    });
                    break;

                case "file":
                case "content":
                case "android.resource":
                    Log.d(TAG, "local image: " + img);

                    CarIcon icon = new CarIcon.Builder(
                            IconCompat.createWithContentUri(uri)).build();
                    builder.setImage(icon, Row.IMAGE_TYPE_ICON);
                    break;

                default:
                    // Unsupported scheme – leave row without image
            }
        }

        return builder.build();
    }
}