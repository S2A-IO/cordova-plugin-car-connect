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
import Foundation
import UIKit
import CarPlay          // CarPlay symbols (CPListItem, …)

@available(iOS 14.0, *)
@objc(CarConnect)       // must match plugin.xml <feature ios-package>
class CarConnect: CDVPlugin {

    // ------------------------------------------------------------
    // Singleton reference so static emitters can reach the plugin.
    // ------------------------------------------------------------
    private static weak var shared: CarConnect?

    // Callback IDs cached so native UI can stream events
    private var initCallbackId:   String?
    private var listCallbackId:   String?
    private var detailCallbackId: String?

    // ------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------
    override func pluginInitialize() {
        super.pluginInitialize()
        CarConnect.shared = self               // keep reference
    }

    // ------------------------------------------------------------
    // JavaScript-exposed actions
    // Each one is annotated with @objc(actionName:)
    // ------------------------------------------------------------

    // JS → CarConnect.init(…)
    @objc(initialize:)
    private func initialize(_ cmd: CDVInvokedUrlCommand) {
        // 1️⃣ Close the previous global callback channel if we had one
        if let old = initCallbackId {
            let bye = CDVPluginResult(status: .noResult)
            bye?.setKeepCallbackAs(false)           // <- closes it
            commandDelegate.send(bye, callbackId: old)
        }

        // 2️⃣ Store the new callback-id
        initCallbackId = cmd.callbackId

        // 3️⃣ Configure placeholder strings
        let args      = cmd.arguments.first as? [String: Any] ?? [:]
        let title     = args["title"]       as? String
        let message   = args["description"] as? String

        CarConnectService.shared.configure(startupTitle: title,
                                           startupMessage: message)

        // 4️⃣ Keep the new channel open
        keepCallbackOpen(for: cmd.callbackId)   // stream native events back
    }

    /// JS → CarConnect.showListView(items,…)
    @objc(showListView:)
    private func showListView(_ cmd: CDVInvokedUrlCommand) {
        // Close any earlier list callback before replacing it
        closeCallback(&listCallbackId)
        listCallbackId = cmd.callbackId

        let payload = cmd.arguments.first as? [String: Any] ?? [:]
        NotificationCenter.default.post(
            name: .carConnectShowListView,
            object: nil,
            userInfo: ["payload": payload]
        )

        keepCallbackOpen(for: cmd.callbackId)
    }

    /// JS → CarConnect.showDetailView(pairs, buttons,…)
    @objc(showDetailView:)
    private func showDetailView(_ cmd: CDVInvokedUrlCommand) {
        closeCallback(&detailCallbackId)
        detailCallbackId = cmd.callbackId

        let payload = cmd.arguments.first as? [String: Any] ?? [:]
        NotificationCenter.default.post(
            name: .carConnectShowDetailView,
            object: nil,
            userInfo: ["payload": payload]
        )

        keepCallbackOpen(for: cmd.callbackId)
    }

    /// JS → CarConnect.isConnected()
    @objc(isConnected:)
    private func isConnected(_ cmd: CDVInvokedUrlCommand) {
        let state = CarConnectService.shared.connectionState.rawValue // 0 or 1
        let res   = CDVPluginResult(status: .ok, messageAs: state)
        commandDelegate.send(res, callbackId: cmd.callbackId)
    }

    @objc(goBack:)
    private func goBack(_ cmd: CDVInvokedUrlCommand) {
        CarConnectService.shared.goBack()          // pop on native side
        let res = CDVPluginResult(status: .ok)
        commandDelegate.send(res, callbackId: cmd.callbackId)
    }

    // ------------------------------------------------------------
    // Helper to keep callback channel open
    // ------------------------------------------------------------
    private func keepCallbackOpen(for cbID: String?) {
        guard let id = cbID else { return }
        let res = CDVPluginResult(status: .noResult)
        res?.setKeepCallbackAs(true)
        commandDelegate.send(res, callbackId: id)
    }

    private func closeCallback(_ id: inout String?) {
        guard let cb = id else { return }
        let res = CDVPluginResult(status: .noResult)
        res?.setKeepCallbackAs(false)
        commandDelegate.send(res, callbackId: cb)
        id = nil
    }

    static func closeListCallback()   { shared?.closeCallback(&shared!.listCallbackId) }
    static func closeDetailCallback() { shared?.closeCallback(&shared!.detailCallbackId) }

    // ------------------------------------------------------------
    // Native → JS emitters (called from CarConnectService)
    // ------------------------------------------------------------

    static func emitListItemTapped(_ jsonString: String) {
        guard 
            let plugin = CarConnect.shared 
        else { return }

        // Priority: screen-specific callback ➜ else fall back to global handler
        let cbID = plugin.listCallbackId ?? plugin.initCallbackId
        guard let id = cbID else { return }

        let res = CDVPluginResult(status: .ok, messageAs: jsonString)
        res?.setKeepCallbackAs(true)
        plugin.commandDelegate.send(res, callbackId: id)
    }

    static func emitDetailButtonPressed(_ jsonString: String) {
        guard
            let plugin = CarConnect.shared,
            let cbID   = plugin.detailCallbackId
        else { return }

        let res = CDVPluginResult(status: .ok, messageAs: jsonString)
        res?.setKeepCallbackAs(true)
        plugin.commandDelegate.send(res, callbackId: cbID)
    }
}

// ------------------------------------------------------------
// Notification names shared with CarConnectService
// ------------------------------------------------------------
extension Notification.Name {
    static let carConnectShowListView   = Notification.Name("CarConnectShowListView")
    static let carConnectShowDetailView = Notification.Name("CarConnectShowDetailView")
}


