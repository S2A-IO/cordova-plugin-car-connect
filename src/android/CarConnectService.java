/**
 * CarConnectService.java – Entry point for Android Auto (Jetpack Car‑App Library)
 * 
 * Both the startup message **and** the screen title are now configurable via
 * AndroidManifest <meta‑data>. In the plugin.xml you can merge values that come
 * from Cordova <preference> entries, e.g.:
 *
 * <platform name="android">
 *  <config-file target="AndroidManifest.xml" parent="/manifest/application">
 *     <meta-data android:name="io.s2a.connect.STARTUP_MESSAGE"
 *                android:value="$CAR_CONNECT_STARTUP_MESSAGE" />
 *     <meta-data android:name="io.s2a.connect.STARTUP_TITLE"
 *                android:value="$CAR_CONNECT_STARTUP_TITLE" />
 *   </config-file>
 * </platform>
 *
 * When either meta‑data tag is absent we fall back to sensible defaults.
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */

package io.s2a.connect;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.car.app.validation.HostValidator;
import androidx.car.app.CarAppService;
import androidx.car.app.Screen;
import androidx.car.app.ScreenManager;
import androidx.car.app.Session;
import androidx.car.app.model.MessageTemplate;
import androidx.car.app.model.Template;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Android‑Auto service entry point for the Cordova "car-connect" plugin.
 */
public final class CarConnectService extends CarAppService {
    // Connection state constants ---------------------------------------
    public static final int STATE_NONE         = 0;
    public static final int STATE_CARPLAY      = 1; // Placeholder – not used on Android
    public static final int STATE_ANDROID_AUTO = 2;

    private static volatile int connectionState = STATE_NONE;
    public static int getConnectionState() { return connectionState; }

    private static final String META_STARTUP_MESSAGE = "io.s2a.connect.STARTUP_MESSAGE";
    private static final String META_STARTUP_TITLE   = "io.s2a.connect.STARTUP_TITLE";

    private static final String DEFAULT_STARTUP_MESSAGE =
            "CarConnect plugin ready.\nOpen the mobile app to send content.";
    private static final String DEFAULT_STARTUP_TITLE   = "Car Connect";

    private static final String ACTION_SHOW_LIST_VIEW   = CarConnect.ACTION_SHOW_LIST_VIEW;
    private static final String ACTION_SHOW_DETAIL_VIEW = CarConnect.ACTION_SHOW_DETAIL_VIEW;

    private CarConnectSession currentSession;

    // ------------------------------------------------------------------
    //  Cordova → Android Auto bootstrap
    // ------------------------------------------------------------------

    @NonNull
    @Override
    public Session onCreateSession() {
        connectionState = STATE_ANDROID_AUTO; // Host bound – we’re live.
        currentSession = new CarConnectSession(
                fetchMetaOrDefault(META_STARTUP_MESSAGE, DEFAULT_STARTUP_MESSAGE),
                fetchMetaOrDefault(META_STARTUP_TITLE,   DEFAULT_STARTUP_TITLE)
        );
        return currentSession;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String action = intent.getAction();
            String json   = intent.getStringExtra("payload");

            if (ACTION_SHOW_LIST_VIEW.equals(action) && currentSession != null) {
                currentSession.showListView(json);
            }
            if (ACTION_SHOW_DETAIL_VIEW.equals(action) && currentSession != null) {
                currentSession.showDetailView(json);
            }
        }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        connectionState = STATE_NONE; // Clean up
        super.onDestroy();
    }

    @Override
    @NonNull
    public HostValidator createHostValidator() {

        // ------------------------------------------------------------------
        // 1. Development builds  →  allow everything (easier testing)
        // ------------------------------------------------------------------
        if (isDebugBuild()) {                  // true for debug variant
            return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR;
        }

        // ------------------------------------------------------------------
        // 2. Production / release builds  →  restrict to known hosts
        // ------------------------------------------------------------------
        // List official Android-Auto / Automotive host package names here
        final Set<AllowedHost> prodHostsSet = Set.of(
            new AllowedHost("com.google.android.projection.gearhead",
                        "fdb00c43dbde8b51cb312aa81d3b5fa17713adb94b28f598d77f8eb89daceedf"),
            new AllowedHost("com.google.android.projection.gearhead",
                        "70811a3eacfd2e83e18da9bfede52df16ce91f2e69a44d21f18ab66991130771"),
            new AllowedHost("com.google.android.projection.gearhead",
                        "1975b2f17177bc89a5dff31f9e64a6cae281a53dc1d1d59b1d147fe1c82afa00"),
            new AllowedHost("com.google.android.apps.automotive.templates.host",
                        "c241ffbc8e287c4e9a4ad19632ba1b1351ad361d5177b7d7b29859bd2b7fc631"),
            new AllowedHost("com.google.android.apps.automotive.templates.host",
                        "dd66deaf312d8daec7adbe85a218ecc8c64f3b152f9b5998d5b29300c2623f61"),
            new AllowedHost("com.google.android.apps.automotive.templates.host",
                        "50e603d333c6049a37bd751375d08f3bd0abebd33facd30bd17b64b89658b421")            
            // add OEM head units here …
        );
        
        HostValidator.Builder builder =
           new HostValidator.Builder(getApplicationContext());

        for (AllowedHost host : prodHostsSet) {
            builder.addAllowedHost(host.packageName(), host.sha256Digest());
        }

        HostValidator validator = builder.build();
        return validator;
    }

    /**
     * Determing if this is a debug build.
     */
    private boolean isDebugBuild() {
        return (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    /** Reads a <meta-data> string or returns the supplied default. */
    private String fetchMetaOrDefault(String key, String fallback) {
        try {
            ApplicationInfo ai = getPackageManager().getApplicationInfo(
                    getPackageName(), PackageManager.GET_META_DATA);
            Bundle md = ai.metaData;
            if (md != null && md.containsKey(key)) {
                return md.getString(key, fallback);
            }
        } catch (PackageManager.NameNotFoundException ignored) {
        }
        return fallback;
    }

    // ------------------------------------------------------------------
    //  Session subclass – one per host launch
    // ------------------------------------------------------------------

    private static final class CarConnectSession extends Session {
        private final String placeholderText;
        private final String title;

        CarConnectSession(String placeholderText, String title) {
            this.placeholderText = placeholderText;
            this.title = title;
        }

        @Override
        @NonNull
        public Screen onCreateScreen(@NonNull Intent intent) {
            return new PlaceholderScreen(getCarContext(), placeholderText, title);
        }

        void showListView(String json) {
            try {
                JSONObject payload = new JSONObject(json);
                ListViewScreen screen = new ListViewScreen(getCarContext(), payload,
                        CallbackRegistry.getListCallback());
                getCarContext().getCarService(ScreenManager.class).push(screen);
            } catch (JSONException ignored) {}
        }

        void showDetailView(String json) {
            try {
                JSONObject payload = new JSONObject(json);
                DetailViewScreen screen = new DetailViewScreen(getCarContext(), payload,
                        CallbackRegistry.getDetailCallback());
                getCarContext().getCarService(ScreenManager.class).push(screen);
            } catch (JSONException ignored) {}
        }
    }

    // ------------------------------------------------------------------
    //  Placeholder Screen
    // ------------------------------------------------------------------

    private static final class PlaceholderScreen extends Screen {
        private final String message;
        private final String title;

        PlaceholderScreen(@NonNull androidx.car.app.CarContext ctx, String message, String title) {
            super(ctx);
            this.message = message;
            this.title = title;
        }

        @NonNull
        @Override
        public Template onGetTemplate() {
            return new MessageTemplate.Builder(message)
                    .setTitle(title)
                    .build();
        }
    }
}
