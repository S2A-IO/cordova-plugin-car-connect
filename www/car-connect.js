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
 * @param {Function} [onError]
 *        Called with an `Error` instance on failure.
 * @throws {TypeError} If `items` is not a non‑empty array.
 */
function showListView(title, items, onItemTapped, onError) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new TypeError('showListView expects a non‑empty array of items');
  }
  execNative('showListView', 
    { title: String(title), items: items }, 
    onItemTapped,
    onError
  );
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
 * @param {Function} [onError]
 *        Called with an `Error` instance on failure.
 * @throws {TypeError|RangeError} For invalid arguments.
 */
function showDetailView(title, pairs, buttons, onButtonPressed, onError) {
  if (!Array.isArray(pairs) || pairs.length === 0) {
    throw new TypeError('showDetailView expects a non‑empty array of key/value pairs');
  }
  if (buttons && buttons.length > 2) {
    throw new RangeError('showDetailView supports at most two buttons');
  }
  execNative('showDetailView', {
    title: String(title),
    pairs: pairs,
    buttons: Array.isArray(buttons) ? buttons : []
  }, onButtonPressed, onError);
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

//--------------------------------------------------------------------
// Public API
//--------------------------------------------------------------------

/**
 * `CarConnect` public facade.
 * @namespace CarConnect
 */
var CarConnect = {
  isConnected: isConnected,
  showListView: showListView,
  showDetailView: showDetailView
};

module.exports = CarConnect;
