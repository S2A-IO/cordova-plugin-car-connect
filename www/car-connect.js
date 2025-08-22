// car-connect.js – JavaScript bridge for cordova-plugin-car-connect
// ---------------------------------------------------------------
// This module exposes a clean JavaScript API for Cordova apps while delegating
// all heavy lifting to the native Android Auto / Apple CarPlay implementations
// (to be added later). Use cordova.exec to forward calls.
//
// Copyright © 2025 – RIKSOF. MIT License.

/* global require, module */

/**
 * Cordova exec helper.
 * @type {Function}
 */
var exec = require('cordova/exec');

/** The service name registered on the native side. */
var PLUGIN_NAME = 'CarConnect';

/** No‑op placeholder for optional callbacks. */
function noop() {}

/** Remember the global handler registered via `init()` */
var globalHandler = noop;

// ──────────────────────────────────────────────────────────────────────────
// Internal event hub & screen registry
// ──────────────────────────────────────────────────────────────────────────
/** @type {Map<string, { kind: 'list'|'detail', onItem?:Function, onAction?:Function, options?:CommonScreenOptions }>} */
var screens = new Map();

/** @type {Record<string, Set<Function>>} */
var globalListeners = Object.create(null);

/** Monotonic id for ScreenHandle */
var _idSeq = 1;
function nextScreenId() { return String(_idSeq++); }

/**
 * @typedef {Object} BackEvent
 * @property {string} screenId
 * @property {'nav'|'gesture'|'hardware'|'system'} reason
 */

/**
 * @typedef {Object} CommonScreenOptions
 * @property {(e: BackEvent) => (boolean|void)} [onBack]       // return true → intercept (native should NOT pop)
 * @property {boolean} [interceptBack=false]
 * @property {(screenId: string) => void} [onAppear]
 * @property {(screenId: string) => void} [onDisappear]
 * @property {(err: Error) => void} [onError]
 * @property {string} [tag]
 */

function emitGlobal(eventName, payload) {
  var set = globalListeners[eventName];
  if (!set) return;
  set.forEach(function (fn) {
    try { fn(payload); } catch (_) {}
  });
}

/**
 * Lightweight ScreenHandle returned by showListView/showDetailView.
 * @param {string} id
 */
function makeScreenHandle(id) {
  return {
    id: id,
    close: function () { execNative('closeScreen', { screenId: id }, noop, noop); },
    on: function (event, handler) {
      // sugar for local per-screen hooks via options was already provided;
      // this is a minimal no-op for now to avoid over-designing the JS shim.
      // (You can extend to maintain per-handle listeners if you like.)
      return function off() {};
    }
  };
}

/**
 * Ensures the provided value is a function, otherwise returns a no‑op.
 * @param {*} fn
 * @returns {Function}
 */
function asFn(fn) {
  return (typeof fn === 'function') ? fn : noop;
}

/**
 * Calls into the platform implementation via `cordova.exec()`.
 * Wraps the arguments in an array so they map cleanly to JSObject / NSDictionary.
 *
 * @param {String} action   Native action name.
 * @param {Object} payload  Arguments to pass to native side.
 * @param {Function} ok     Success callback.
 * @param {Function} fail   Error callback.
 */
function execNative(action, payload, ok, fail) {
  exec(asFn(ok), asFn(fail), PLUGIN_NAME, action, [payload]);
}

/**
 * One-time initialisation.
 *
 * @param {String} title         Placeholder-screen title.
 * @param {String} description   Placeholder-screen body text.
 * @param {Function} [handler]   Called on native events (e.g. list-item taps).
 * @param {Function} [onError]   Error callback.
 */
function init(title, description, handler, onError) {
  globalHandler = asFn(handler);
  execNative(
    'initialize',
    { title: String(title), description: String(description) },
    function onStream(event) {
      // First pass the raw event to the legacy handler for back-compat
      try { globalHandler(event); } catch (_) {}

      // Then route to screen-specific hooks & global listeners
      if (!event || !event.type) return;
      var scr = event.screenId ? screens.get(String(event.screenId)) : null;
      switch (event.type) {
        case 'list:select':
          if (scr && asFn(scr.onItem)) scr.onItem(event.payload);
          break;
        case 'detail:action':
          if (scr && asFn(scr.onAction)) scr.onAction(event.payload);
          break;
        case 'screen:appear':
          if (scr && scr.options && asFn(scr.options.onAppear)) scr.options.onAppear(String(event.screenId));
          emitGlobal('screen:appear', { screenId: String(event.screenId), screenType: scr ? scr.kind : undefined });
          break;
        case 'screen:disappear':
          if (scr && scr.options && asFn(scr.options.onDisappear)) scr.options.onDisappear(String(event.screenId));
          emitGlobal('screen:disappear', { screenId: String(event.screenId), screenType: scr ? scr.kind : undefined });
          // once disappeared, native may reuse ids; GC the entry
          if (scr) screens.delete(String(event.screenId));
          break;
        case 'screen:back': {
          var payload = { screenId: String(event.screenId), reason: event.reason || 'nav' };
          var intercepted = false;
          if (scr && scr.options && scr.options.interceptBack && typeof scr.options.onBack === 'function') {
            try { intercepted = !!scr.options.onBack(payload); } catch (_) { intercepted = false; }
          } else if (scr && scr.options && typeof scr.options.onBack === 'function') {
            // notify-only
            try { scr.options.onBack(payload); } catch (_) {}
          }
          emitGlobal('screen:back', { screenId: payload.screenId, reason: payload.reason, screenType: scr ? scr.kind : undefined, intercepted: !!intercepted });
          // Let native decide what to do with "intercepted"; if you later need
          // an explicit ack, add a dedicated execNative call here.
          break;
        }
        default:
          // ignore unknown events
          break;
      }
    },
    onError
  );
}

/**
 * Displays a list UI with image, title, and description.
 *
 * ```js
 * CarConnect.showListView('Screen title', [
 *   { id: 42, image: 'img/spoon.png', title: 'Spoon', description: 'A shiny spoon' }
 * ], item => console.log('Item tapped:', item));
 * ```
 *
 * @param {String} title
 *        Title for the CarPlay list screen (shown in the HMI header)
 * @param {Array<{id:string|number, image:string, title:string, description:string}>} items
 *        Data to render. **Must be ≤ 40 items** (typical HMI limit).
 * @param {Function} [onItemTapped]
 *        Called with the full item object when user taps a list row.
 * @param {CommonScreenOptions} [options]
 *        Lifecycle hooks & error handler.
 * @throws {TypeError} If `items` is not a non‑empty array.
 */
function showListView(title, items, onItemTapped, options) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new TypeError('showListView expects a non‑empty array of items');
  }
  var screenId = nextScreenId();
  screens.set(screenId, { kind: 'list', onItem: asFn(onItemTapped), options: options || {} });
  execNative('showListView',
    {
      screenId: screenId,
      title: String(title),
      items: items,
      back: {
        intercept: !!(options && options.interceptBack === true),
        tag: options && options.tag || undefined
      }
    },
    asFn(onItemTapped),
    options && options.onError ? options.onError : noop
  );
  return makeScreenHandle(screenId);
}

/**
 * Displays a detail screen consisting of label/value pairs and ≤ 2 buttons.
 *
 * ```js
 * CarConnect.showDetailView(
 *   'Screen title',
 *   [
 *     { key: 'Artist', value: 'Hans Zimmer' },
 *     { key: 'Album',  value: 'Dune (OST)' }
 *   ],
 *   [
 *     { id: 'play',  type: 'primary',   text: 'Play' },
 *     { id: 'share', type: 'secondary', text: 'Share' }
 *   ],
 *   btn => console.log('Pressed:', btn.id)
 * );
 * ```
 *
 * @param {String} title
 *        Title for the CarPlay detail view screen (shown in the HMI header)
 * @param {Array<{key:string, value:string}>} pairs
 *        Key/value pairs to render.
 * @param {Array<{id?:string, type:'primary'|'secondary', text:string}>} [buttons=[]]
 *        Up to two buttons. `id` is echoed back in the callback.
 * @param {Function} [onButtonPressed]
 *        Receives the full button object when pressed.
 * @param {CommonScreenOptions} [options]
+ *        Lifecycle hooks & error handler.
 * @throws {TypeError|RangeError} For invalid arguments.
 */
function showDetailView(title, pairs, buttons, onButtonPressed, options) {
  if (!Array.isArray(pairs) || pairs.length === 0) {
    throw new TypeError('showDetailView expects a non‑empty array of key/value pairs');
  }
  if (buttons && buttons.length > 2) {
    throw new RangeError('showDetailView supports at most two buttons');
  }
  
  var screenId = nextScreenId();
  screens.set(screenId, { kind: 'detail', onAction: asFn(onButtonPressed), options: options || {} });
  execNative('showDetailView', {
    screenId: screenId,
    title: String(title),
    pairs: pairs,
    buttons: Array.isArray(buttons) ? buttons : [],
    back: {
      intercept: !!(options && options.interceptBack === true),
      tag: options && options.tag || undefined
    }
  }, onButtonPressed, options && options.onError ? options.onError : noop);
  return makeScreenHandle(screenId);
}

/**
 * Returns a promise that resolves with:
 *   0 – not connected
 *   1 – connected to Apple CarPlay
 *   2 – connected to Android Auto
 */
function isConnected() {
  return new Promise(function (resolve, reject) {
    exec(resolve, reject, PLUGIN_NAME, 'isConnected', []);
  });
}

/**
 * Pops the current CarPlay template (same as tapping the back button).
 * @param {Function} [ok]   Called when the pop completes.
 * @param {Function} [err]  Called on error.
 */
function goBack(ok, err) {
  execNative('goBack', {}, ok, err);
}

/**
 * Global listeners (optional): screen:back | screen:appear | screen:disappear
 * @param {'screen:back'|'screen:appear'|'screen:disappear'} eventName
 * @param {Function} handler
 */
function addListener(eventName, handler) {
  if (typeof handler !== 'function') return function () {};
  if (!globalListeners[eventName]) globalListeners[eventName] = new Set();
  globalListeners[eventName].add(handler);
  return function remove() { removeListener(eventName, handler); };
 }

function removeListener(eventName, handler) {
  var set = globalListeners[eventName];
  if (set) set.delete(handler);
}

//--------------------------------------------------------------------
// Public API
//--------------------------------------------------------------------

/**
 * `CarConnect` public facade.
 * @namespace CarConnect
 */
var CarConnect = {
  init: init,
  isConnected: isConnected,
  showListView: showListView,
  showDetailView: showDetailView,
  goBack: goBack,
  addListener: addListener,
  removeListener: removeListener
};

module.exports = CarConnect;
