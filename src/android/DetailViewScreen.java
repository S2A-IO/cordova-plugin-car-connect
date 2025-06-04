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

import android.util.Log;

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

    private CallbackContext callback;
    private PaneTemplate template;

    public DetailViewScreen(@NonNull CarContext ctx, @NonNull JSONObject payload,
                            @NonNull CallbackContext cb) throws JSONException {
        super(ctx);
        this.callback = cb;
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
        JSONArray pairsArr = payload.optJSONArray("pairs");
        if (pairsArr == null || pairsArr.length() == 0) {
            throw new JSONException("pairs array missing or empty in showDetailView payload");
        }

        // Build rows for each key/value.
        Pane.Builder pane = new Pane.Builder();
        for (int i = 0; i < pairsArr.length(); i++) {
            JSONObject p = pairsArr.getJSONObject(i);
            pane.addRow(new Row.Builder()
                .setTitle(p.optString("key", ""))
                .addText(p.optString("value", ""))
                .build());
        }

        // Build up to two actions
        Action  primary = null;
        ActionStrip.Builder strip = new ActionStrip.Builder();
        boolean hasStripAction = false;

        JSONArray buttonsArr = payload.optJSONArray("buttons");
        if (buttonsArr != null) {
            for (int i = 0; i < buttonsArr.length(); i++) {
                JSONObject b = buttonsArr.getJSONObject(i);
                Action a = buildAction(b, cb);

                if ("primary".equalsIgnoreCase(b.optString("type")) && primary == null) {
                    primary = a;                 // first “primary” wins
                } else {
                    strip.addAction(a);          // all others go to the strip
                    hasStripAction = true;
                }
            }
        }

        if (primary != null) {
            pane.addAction(primary);             // put primary in the Pane
        }

        PaneTemplate.Builder tmplBuilder =
            new PaneTemplate.Builder(pane.build())
                .setTitle(payload.optString("title", "Details"))
                .setHeaderAction(Action.BACK);

        // Only add the strip if there is at least one action in it:
        if (hasStripAction) {
            tmplBuilder.setActionStrip(strip.build());
        }

        return tmplBuilder.build();
    }

    private static Action buildAction(JSONObject btn, CallbackContext cb) {
        String text = btn.optString("text", "Button");

        Action.Builder builder = new Action.Builder()
            .setTitle(text)
            .setOnClickListener(() -> {
                PluginResult pr = new PluginResult(PluginResult.Status.OK, btn.toString());
                pr.setKeepCallback(true);
                cb.sendPluginResult(pr);
            });

        return builder.build();
    }

    /**
     * Public refresh helper  (called from CarConnectService)
     */
    public void update(@NonNull JSONObject newPayload) {
        try {
            this.template = buildTemplate(newPayload, callback);
            invalidate();              // ask framework to fetch new template
        } catch (JSONException e) {
            Log.w("CarConnect.Detail", "Bad payload for DetailViewScreen.update", e);
        }
    }
}
