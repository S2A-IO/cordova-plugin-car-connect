/**
 * CarConnect.swift ­– Cordova plugin entry-point (iOS side)
 * 
 * Mirrors the Android implementation:
 *
 *   • showListView(payload, successCB)   – pushes list UI inside CarPlay
 *   • showDetailView(payload, successCB) – shows key/value pane with buttons
 *   • isConnected()                      – returns 0 / 1 / 2
 *       0 → no in-car host
 *       1 → Apple CarPlay (the only in-car host on iOS)
 *       2 → Android Auto   (never on iOS – always 0 or 1)
 *
 * Heavy-lifting CarPlay UI code will live elsewhere (e.g. the App Delegate or a
 * dedicated SceneDelegate).  For now we broadcast a notification so that code
 * can react.  The Cordova callbacks are stored so row taps or button presses
 * can be echoed back later via `CDVPluginResult(keepCallback: true)`.
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */

/**
 * CarConnect.swift – Cordova plugin entry-point (iOS side)
 * -----------------------------------------------------------------------------
 * Exposes to JavaScript:
 *   • showListView(items, cb)
 *   • showDetailView(pairs, buttons, cb)
 *   • isConnected()   → 0 (none) | 1 (CarPlay) | 2 (Android Auto – never on iOS)
 *
 * Heavy UI work is done by CarConnectService.shared, which listens for the
 * notifications we post below.  Interaction events from CarPlay flow back to JS
 * through the kept Cordova callbacks.
 * -----------------------------------------------------------------------------
 */

import Foundation
import Cordova
import UIKit
import CarPlay

@objc(CarConnect)          // must match plugin.xml
class CarConnect: CDVPlugin {

    // MARK: – Callback IDs cached so native UI can stream events

    private var listCallbackId:   String?
    private var detailCallbackId: String?

    // MARK: – Lifecycle

    override func pluginInitialize() {
        super.pluginInitialize()
        // Nothing else: CarConnectService registers for our notifications.
    }

    // MARK: – JS action dispatcher

    override func execute(_ command: CDVInvokedUrlCommand!) {
        guard let action = command?.commandName else { return }

        switch action {
        case "showListView":
            showListView(command)
        case "showDetailView":
            showDetailView(command)
        case "isConnected":
            isConnected(command)
        default:
            let res = CDVPluginResult(status: .error,
                                      messageAs: "Unknown action \(action)")
            commandDelegate.send(res, callbackId: command.callbackId)
        }
    }

    // MARK: – Public API methods

    private func showListView(_ cmd: CDVInvokedUrlCommand) {
        listCallbackId = cmd.callbackId

        let payload = cmd.arguments.first as? [String: Any] ?? [:]
        NotificationCenter.default.post(name: .carConnectShowListView,
                                        object: nil,
                                        userInfo: ["payload": payload])

        keepCallbackOpen(for: cmd.callbackId)
    }

    private func showDetailView(_ cmd: CDVInvokedUrlCommand) {
        detailCallbackId = cmd.callbackId

        let payload = cmd.arguments.first as? [String: Any] ?? [:]
        NotificationCenter.default.post(name: .carConnectShowDetailView,
                                        object: nil,
                                        userInfo: ["payload": payload])

        keepCallbackOpen(for: cmd.callbackId)
    }

    private func isConnected(_ cmd: CDVInvokedUrlCommand) {
        let state = CarConnectService.shared.connectionState.rawValue  // 0 or 1
        let res   = CDVPluginResult(status: .ok, messageAs: state)
        commandDelegate.send(res, callbackId: cmd.callbackId)
    }

    // MARK: – Helpers

    private func keepCallbackOpen(for cbID: String?) {
        guard let id = cbID else { return }
        let res = CDVPluginResult(status: .noResult)
        res?.setKeepCallbackAs(true)
        commandDelegate.send(res, callbackId: id)
    }

    // MARK: – Native → JS emitters (called by CarConnectService)

    static func emitListItemTapped(_ jsonString: String) {
        guard
            let plugin = CDVPlugin.getInstance("CarConnect") as? CarConnect,
            let cbID   = plugin.listCallbackId
        else { return }

        let res = CDVPluginResult(status: .ok, messageAs: jsonString)
        res?.setKeepCallbackAs(true)
        plugin.commandDelegate.send(res, callbackId: cbID)
    }

    static func emitDetailButtonPressed(_ jsonString: String) {
        guard
            let plugin = CDVPlugin.getInstance("CarConnect") as? CarConnect,
            let cbID   = plugin.detailCallbackId
        else { return }

        let res = CDVPluginResult(status: .ok, messageAs: jsonString)
        res?.setKeepCallbackAs(true)
        plugin.commandDelegate.send(res, callbackId: cbID)
    }
}

// MARK: – Notification names used between plugin and service

extension Notification.Name {
    static let carConnectShowListView   = Notification.Name("CarConnectShowListView")
    static let carConnectShowDetailView = Notification.Name("CarConnectShowDetailView")
}

