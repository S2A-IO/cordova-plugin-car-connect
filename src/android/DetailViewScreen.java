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
import androidx.annotation.Nullable;
import androidx.activity.OnBackPressedCallback;
import androidx.car.app.CarContext;
import androidx.car.app.Screen;
import androidx.car.app.model.Action;
import androidx.car.app.model.ActionStrip;
import androidx.car.app.model.Pane;
import androidx.car.app.model.PaneTemplate;
import androidx.car.app.model.Row;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.LifecycleOwner;

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

    // Screen identity & back options (from JS payload)
    private String screenId = "";
    private boolean interceptBack = false;
    private OnBackPressedCallback backCallback;

    public DetailViewScreen(@NonNull CarContext ctx, @NonNull JSONObject payload,
                            @NonNull CallbackContext cb) throws JSONException {
        super(ctx);
        this.callback = cb;
        parseMeta(payload);

        // Lifecycle-driven appear/disappear events; only register a back override if intercepting
        getLifecycle().addObserver(new DefaultLifecycleObserver() {
            @Override public void onStart(@NonNull LifecycleOwner owner) {
                emitInitEvent("screen:appear", null);
                if (interceptBack) {
                    backCallback = new OnBackPressedCallback(true) {
                        @Override public void handleOnBackPressed() {
                            // Consume and just notify; JS decides when to pop
                            emitInitEvent("screen:back", "nav");
                        }
                    };
                    getCarContext().getOnBackPressedDispatcher().addCallback(DetailViewScreen.this, backCallback);
                }
            }
            @Override public void onStop(@NonNull LifecycleOwner owner) {
                emitInitEvent("screen:disappear", null);
                if (backCallback != null) { backCallback.remove(); backCallback = null; }
            }
        });

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
    public void update(@NonNull JSONObject newPayload, @NonNull CallbackContext newCb) {
        try {
            this.callback = newCb;
            parseMeta(newPayload);
            this.template = buildTemplate(newPayload, callback);
            invalidate();              // ask framework to fetch new template
        } catch (JSONException e) {
            Log.w("CarConnect.Detail", "Bad payload for DetailViewScreen.update", e);
        }
    }

    /** Match against a JS ScreenHandle id */
    public boolean matchesId(@NonNull String id) {
        return id.equals(this.screenId);
    }

    // ──────────────────────────────────────────────────────────────
    // Metadata parsing & event emission
    // ──────────────────────────────────────────────────────────────
    private void parseMeta(JSONObject payload) {
        // Screen id (required for JS correlation)
        this.screenId = payload.optString("screenId", "");
        // Back options
        JSONObject back = payload.optJSONObject("back");
        if (back != null) {
            this.interceptBack = back.optBoolean("intercept", false);
        }
    }

    private void emitInitEvent(@NonNull String type, @Nullable String reason) {
        CallbackContext initCb = CallbackRegistry.getInitCallback();
        if (initCb == null) return;
        try {
            JSONObject event = new JSONObject();
            event.put("type", type);
            if (!screenId.isEmpty()) event.put("screenId", screenId);
            if (reason != null) event.put("reason", reason);

            PluginResult pr = new PluginResult(PluginResult.Status.OK, event.toString());
            pr.setKeepCallback(true);
            initCb.sendPluginResult(pr);
        } catch (Exception ignored) { }
    }
}
