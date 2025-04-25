/**
 * DetailViewScreen.java – Shows key/value details with up to two buttons
 * 
 * <p>Payload expected from JavaScript (<code>CarConnect.showDetailView</code>):</p>
 *
 * <pre>
 * {
 *   "pairs": [ { "key": "Artist", "value": "Hans Zimmer" }, … ],
 *   "buttons": [
 *       { "id": "play",  "type": "primary",   "text": "Play" },
 *       { "id": "share", "type": "secondary", "text": "Share" }
 *   ]
 * }
 * </pre>
 *
 * When a button is pressed, we send the full button JSON back through the kept
 * Cordova callback channel (<code>PluginResult.keepCallback = true</code>).
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */

package io.s2a.connect;

import androidx.annotation.NonNull;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.Action;
import androidx.car.app.model.ActionStrip;
import androidx.car.app.model.Pane;
import androidx.car.app.model.PaneTemplate;
import androidx.car.app.model.Row;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Screen responsible for a detail view of label/value pairs.
 */
public class DetailViewScreen extends Screen {

    private final PaneTemplate template;

    public DetailViewScreen(@NonNull CarContext ctx, @NonNull JSONObject payload,
                            @NonNull CallbackContext cb) throws JSONException {
        super(ctx);
        this.template = buildTemplate(payload, cb);
    }

    @NonNull
    @Override
    public androidx.car.app.model.Template onGetTemplate() {
        return template;
    }

    // ------------------------------------------------------------------
    //  Builders
    // ------------------------------------------------------------------

    private static PaneTemplate buildTemplate(JSONObject payload, CallbackContext cb) throws JSONException {
        JSONArray pairsArr   = payload.optJSONArray("pairs");
        JSONArray buttonsArr = payload.optJSONArray("buttons");

        if (pairsArr == null || pairsArr.length() == 0) {
            throw new JSONException("pairs array missing or empty in showDetailView payload");
        }

        // Build rows for each key/value.
        Pane.Builder paneBuilder = new Pane.Builder();
        for (int i = 0; i < pairsArr.length(); i++) {
            JSONObject p = pairsArr.getJSONObject(i);
            String key   = p.optString("key", "");
            String value = p.optString("value", "");
            Row row = new Row.Builder()
                    .setTitle(key)
                    .addText(value)
                    .build();
            paneBuilder.addRow(row);
        }

        // Build up to two actions
        ActionStrip.Builder actionStripBuilder = new ActionStrip.Builder();
        if (buttonsArr != null) {
            for (int i = 0; i < Math.min(2, buttonsArr.length()); i++) {
                JSONObject b = buttonsArr.getJSONObject(i);
                actionStripBuilder.addAction(buildAction(b, cb));
            }
        }

        return new PaneTemplate.Builder(paneBuilder.build())
                .setTitle("Details")
                .setActionStrip(actionStripBuilder.build())
                .setHeaderAction(Action.BACK)
                .build();
    }

    private static Action buildAction(JSONObject btn, CallbackContext cb) {
        String id   = btn.optString("id", "");
        String text = btn.optString("text", "Button");
        String type = btn.optString("type", "secondary");

        Action.Builder builder = new Action.Builder()
                .setTitle(text)
                .setOnClickListener(() -> {
                    PluginResult pr = new PluginResult(PluginResult.Status.OK, btn.toString());
                    pr.setKeepCallback(true);
                    cb.sendPluginResult(pr);
                });

        if ("primary".equalsIgnoreCase(type)) {
            builder.setFlags(Action.FLAG_PRIMARY);
        }
        return builder.build();
    }
}
