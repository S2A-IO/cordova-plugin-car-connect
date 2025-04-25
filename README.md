# cordova-plugin-car-connect

> **Seamless Apple CarPlay + Android Auto integration for Cordova apps**
>
> Render fully‑native list & detail screens, stream user interactions back to JavaScript, and detect whether a head‑unit is connected — all from a single plugin.

---

## Features

| Capability | Android Auto | Apple CarPlay |
|------------|-------------|---------------|
|Native list view (`showListView`) | ✔ Jetpack Car‑App `ListTemplate` | ✔ `CPListTemplate` |
|Native detail pane (`showDetailView`) | ✔ `PaneTemplate` | ✔ `CPInformationTemplate` |
|Live interaction events | List‑row taps | Button presses |
|Connection status (`isConnected`) | Returns **0** / **2** | Returns **0** / **1** |
|Configurable startup title & message | Manifest `<meta‑data>` | Info.plist (optional) |

> ℹ️ No UI WebViews are shown in‑car — every screen is rendered by the platform’s own HMI for a consistent, distraction‑optimised experience.

---

## Installation

```bash
cordova plugin add cordova-plugin-car-connect
```

### Android requirements

* **minSdk 21** (Android 5.0)
* **compileSdk 34** or your project’s own compileSdk
* Gradle pulls `androidx.car.app:app:1.3.0`

### iOS requirements

* Xcode 14+, **Swift 5** runtime
* iOS 14+ for CarPlay scene support
* The plugin adds `CarPlay.framework` and a CarPlay scene manifest automatically.

---

## Configuration (optional)

In your project’s **`config.xml`**:

```xml
<preference name="CAR_CONNECT_STARTUP_TITLE"   value="Drive Connect" />
<preference name="CAR_CONNECT_STARTUP_MESSAGE" value="Waiting for content…" />
```

These values populate the placeholder screen that appears on the head‑unit before your app sends real content.

---

## JavaScript API

```js
import CarConnect from 'cordova-plugin-car-connect';

// Check connectivity
CarConnect.isConnected().then(state => {
  // 0 = none, 1 = CarPlay, 2 = Android Auto
});

// Show a selectable list
CarConnect.showListView([
  {
    id: 1,
    image: 'file:///android_asset/icon.png', // optional for Android Auto
    title: 'Song A',
    description: 'Tap to see details',
  },
  // …up to ~40 items (HMI limit)
], itemJson => {
  const item = JSON.parse(itemJson);
  console.log('User chose', item);
});

// Show a detail pane with buttons
CarConnect.showDetailView(
  [
    { key: 'Artist', value: 'Hans Zimmer' },
    { key: 'Album',  value: 'Dune (OST)' },
  ],
  [
    { id: 'play',  type: 'primary',   text: 'Play' },
    { id: 'share', type: 'secondary', text: 'Share' },
  ],
  btnJson => {
    const btn = JSON.parse(btnJson);
    console.log('Pressed', btn.id);
  }
);
```

### Return codes

| Method | Success payload | Notes |
|--------|----------------|-------|
|`isConnected()`| `0 \| 1 \| 2` | resolves a single integer |
|`showListView()`| tapped row JSON | multiple callbacks possible |
|`showDetailView()`| pressed button JSON | multiple callbacks possible |

---

## File structure

```
www/
  car-connect.js
src/
  android/
    io/s2a/connect/… (all Java sources)
    build/build.gradle
  ios/
    CarConnect.swift
    CarConnectService.swift
    SceneDelegate.swift
```

---

## Contributing

Pull requests are welcome!  Please run `npm version patch` (or minor/major) so the Cordova registry picks up your change.  Remember to align Android & iOS features for parity.

---

## License

MIT © RIKSOF 2025

