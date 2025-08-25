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
import androidx.car.app.ScreenManager;
import androidx.car.app.model.Action;
import androidx.car.app.model.ActionStrip;
import androidx.car.app.model.Pane;
import androidx.car.app.model.PaneTemplate;
import androidx.car.app.model.Row;
import androidx.lifecycle.DefaultLifecycleObserver;

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
    private OnBackPressedCallback backCallback;

    private static final String TAG = "CarConnect.Detail";
    private boolean interceptBack = false;
    private String screenId = "";
    private String title = "Details";

    public DetailViewScreen(@NonNull CarContext ctx, @NonNull JSONObject payload,
                            @NonNull CallbackContext cb) throws JSONException {
        super(ctx);
        this.callback = cb;
        parseMeta(payload);
        this.template = buildTemplate(payload, cb);
       
        // Always enabled so we get notified even when not intercepting
        backCallback = new OnBackPressedCallback(true) {
            @Override public void handleOnBackPressed() {
                Log.d("CarConnect.Detail", "backCallback(): interceptBack=" + interceptBack + " screenId=" + screenId);
                emitInitEvent("screen:back", "nav");
                if (!interceptBack) {
                    try {
                        getCarContext().getCarService(ScreenManager.class).pop();
                    } catch (Exception e) {
                        Log.w("CarConnect.Detail", "Screen pop failed", e);
                    }
                }
            }
        };
        getCarContext().getOnBackPressedDispatcher().addCallback(this, backCallback);
        
    }

    @NonNull
    @Override
    public androidx.car.app.model.Template onGetTemplate() {
        Log.d(TAG, "onGetTemplate(): screenId=" + screenId + " interceptBack=" + interceptBack);
        return template;
    }

    // ------------------------------------------------------------------
    //  Builders
    // ------------------------------------------------------------------

    private PaneTemplate buildTemplate(JSONObject payload, CallbackContext cb) throws JSONException {
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

        final Action headerAction = Action.BACK;
        Log.d(TAG, "buildTemplate(): pairs=" + (pairsArr != null ? pairsArr.length() : 0)
                + " buttons=" + (buttonsArr != null ? buttonsArr.length() : 0)
                + " title=\"" + title + "\" headerAction=BACK");

        PaneTemplate.Builder tmplBuilder =
            new PaneTemplate.Builder(pane.build())
                .setTitle(title)
                .setHeaderAction(headerAction);

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
                Log.d(TAG, "button pressed: " + btn.toString());
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
            Log.d(TAG, "update(): rebuilt template; title=\"" + title + "\" interceptBack=" + interceptBack);
            invalidate();              // ask framework to fetch new template
        } catch (JSONException e) {
            Log.w("CarConnect.Detail", "Bad payload for DetailViewScreen.update", e);
        }
    }

    /** Match against a JS ScreenHandle id */
    public boolean matchesId(@NonNull String id) {
        return id.equals(this.screenId);
    }

    // ------------------------------------------------------------------
    //  Back dispatcher + metadata + event emission
    // ------------------------------------------------------------------
    private void parseMeta(JSONObject payload) {
        this.title = payload.optString("title", this.title);
        this.screenId = payload.optString("screenId", "");
        JSONObject back = payload.optJSONObject("back");
        if (back != null) {
            this.interceptBack = back.optBoolean("intercept", false);
        }
        Log.d(TAG, "parseMeta(): title=\"" + this.title + "\" screenId=" + this.screenId + " interceptBack=" + this.interceptBack);
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
            Log.d(TAG, "emitInitEvent(): " + event.toString());
        } catch (Exception ignored) { }
    }
}
