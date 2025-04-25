/**
 * CallbackRegistry – Holds Cordova CallbackContext references shared between
 * the plugin (mobile) and Android‑Auto service layer.
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */

package io.s2a.connect;

import org.apache.cordova.CallbackContext;

public final class CallbackRegistry {
    private CallbackRegistry() {}

    private static volatile CallbackContext listCallback;
    private static volatile CallbackContext detailCallback;

    // List callbacks ----------------------------------------------------
    public static synchronized void setListCallback(CallbackContext cb) {
        listCallback = cb;
    }
    public static synchronized CallbackContext getListCallback() {
        return listCallback;
    }

    // Detail callbacks --------------------------------------------------
    public static synchronized void setDetailCallback(CallbackContext cb) {
        detailCallback = cb;
    }
    public static synchronized CallbackContext getDetailCallback() {
        return detailCallback;
    }
}
