/**
 * CarConnect.java – Cordova plugin logic (mobile side)
 *
 * • Starts io.s2a.connect.CarConnectService on plugin initialization so the
 *   head-unit can bind immediately.
 * • Forwards showListView, showDetailView, and isConnected actions from
 *   JavaScript to the Android layer.  List/detail requests are delivered via
 *   explicit Intents; callbacks are kept open for streaming events.
 * • isConnected() returns 0 = no connection, 1 = CarPlay (reserved),
 *   2 = Android Auto.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */
package io.s2a.connect;

import android.content.Context;
import android.content.Intent;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Cordova-side entry point exposed to JavaScript. */
public class CarConnect extends CordovaPlugin {

    /* Intent actions understood by CarConnectService */
    public static final String ACTION_INITIALIZE = "io.s2a.connect.INITIALIZE";
    public static final String ACTION_SHOW_LIST_VIEW = "io.s2a.connect.SHOW_LIST_VIEW";
    public static final String ACTION_SHOW_DETAIL_VIEW = "io.s2a.connect.SHOW_DETAIL_VIEW";
    public static final String ACTION_GO_BACK = "io.s2a.connect.GO_BACK";

    /* Intent extra key */
    private static final String EXTRA_PAYLOAD = "payload";

    // ------------------------------------------------------------------
    //  Lifecycle
    // ------------------------------------------------------------------

    @Override
    protected void pluginInitialize() {
        // Keep the car-app service alive so Android Auto can bind at any time
        Context ctx = this.cordova.getContext();
        ctx.startService(new Intent(ctx, CarConnectService.class));
    }

    // ------------------------------------------------------------------
    //  Dispatch JS actions
    // ------------------------------------------------------------------

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext cb)
            throws JSONException {

        switch (action) {
            case "initialize":
                init(args.optJSONObject(0), cb);
                return true;

            case "showListView":
                showListView(args.optJSONObject(0), cb);
                return true;

            case "showDetailView":
                showDetailView(args.optJSONObject(0), cb);
                return true;

            case "isConnected":
                isConnected(cb);
                return true;

            case "goBack":
                goBack(cb);
                return true;

            default:
                return false;   // Unknown action
        }
    }

    // ------------------------------------------------------------------
    //  Public API – delegates to the service
    // ------------------------------------------------------------------

    private void init(JSONObject payload, CallbackContext cb) {
        // Keep callback so placeholder-taps stream back to JS
        CallbackRegistry.setInitCallback(cb);
        forwardToService(ACTION_INITIALIZE, payload);
        keepCallbackOpen(cb);              // leave JS callback hanging open
    }

    private void showListView(JSONObject payload, CallbackContext cb) {
        // Cache callback so row-taps stream back to JS
        CallbackRegistry.setListCallback(cb);
        forwardToService(ACTION_SHOW_LIST_VIEW, payload);
        keepCallbackOpen(cb);
    }

    private void showDetailView(JSONObject payload, CallbackContext cb) {
        // Cache callback so button presses stream back to JS
        CallbackRegistry.setDetailCallback(cb);
        forwardToService(ACTION_SHOW_DETAIL_VIEW, payload);
        keepCallbackOpen(cb);
    }

    /** Immediately returns 0/1/2 indicating current connection status. */
    private void isConnected(CallbackContext cb) {
        int state = CarConnectService.getConnectionState(); // 0, 1, or 2
        cb.success(state);
    }

    private void goBack(CallbackContext cb) {
        forwardToService(ACTION_GO_BACK, null);
        cb.success();                      // nothing to return
    }

    // ------------------------------------------------------------------
    //  Helpers
    // ------------------------------------------------------------------

    private void forwardToService(String action, JSONObject payload) {
        Context ctx = this.cordova.getContext();
        Intent i = new Intent(ctx, CarConnectService.class)
                .setAction(action)
                .putExtra(EXTRA_PAYLOAD,
                          payload != null ? payload.toString() : "{}");
        ctx.startService(i);
    }

    private static void keepCallbackOpen(CallbackContext cb) {
        PluginResult pr = new PluginResult(PluginResult.Status.NO_RESULT);
        pr.setKeepCallback(true);
        cb.sendPluginResult(pr);
    }
}
