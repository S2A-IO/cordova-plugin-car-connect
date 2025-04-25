/**
 * CarConnectService.swift – iOS counterpart to CarConnectService.java
 * 
 * A lightweight singleton that:
 *
 *   • Tracks whether the app is currently connected to Apple CarPlay.
 *   • Listens for notifications posted by `CarConnect.swift` (“show list /
 *     show detail”) and pushes the corresponding templates onto the active
 *     CarPlay interface controller.
 *   • Sends user-interaction events back to JavaScript via the helper emitters
 *     in `CarConnect` (list-item tapped / detail button pressed).
 *
 * NOTE:
 *   – Android Auto doesn’t exist on iOS, so `connectionState` will only be
 *     0 (not connected) or 1 (CarPlay). 2 is reserved for parity.
 *   – UI code is intentionally minimal; adjust layouts, titles, and artwork
 *     to match your brand guidelines.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */

import Foundation
import CarPlay
import UIKit

class CarConnectService: NSObject {

    // MARK: - Singleton
    static let shared = CarConnectService()

    private override init() {
        super.init()
        registerForPluginNotifications()
    }

    // MARK: - Connection state (0 / 1 / 2)
    enum State: Int { case none = 0, carPlay = 1, androidAuto = 2 }
    private(set) var connectionState: State = .none {
        didSet { /* Could post a Notification if the JS side wants push updates */ }
    }

    // MARK: - Scene / interface references
    private weak var interfaceController: CPInterfaceController?
    private weak var carWindow: UIWindow?

    // Call from SceneDelegate when CarPlay scene connects
    func scene(_ scene: CPTemplateApplicationScene,
               didConnect interfaceController: CPInterfaceController,
               to window: UIWindow) {

        self.interfaceController = interfaceController
        self.carWindow           = window
        connectionState          = .carPlay

        // Initial placeholder screen
        let msg = CPMessageTemplate(title: "Open the app on your phone.")
        interfaceController.setRootTemplate(msg, animated: false)
    }

    // Call from SceneDelegate when CarPlay disconnects
    func sceneDidDisconnect(_ scene: UIScene) {
        connectionState = .none
        interfaceController = nil
    }

    // MARK: - Notification wiring (“show*” from Cordova plugin)

    private func registerForPluginNotifications() {
        let nc = NotificationCenter.default

        nc.addObserver(self,
                       selector: #selector(handleShowListView(_:)),
                       name: .carConnectShowListView,
                       object: nil)

        nc.addObserver(self,
                       selector: #selector(handleShowDetailView(_:)),
                       name: .carConnectShowDetailView,
                       object: nil)
    }

    // MARK: - Show list view

    @objc private func handleShowListView(_ note: Notification) {
        guard let uiPayload = note.userInfo?["payload"] as? [String: Any],
              let items     = uiPayload["items"] as? [[String: Any]],
              let iface     = interfaceController else { return }

        var listItems: [CPListItem] = []

        for itm in items {
            let title = itm["title"] as? String ?? ""
            let desc  = itm["description"] as? String ?? ""

            let li = CPListItem(text: title, detailText: desc)
            li.handler = { _, _ in
                // Echo entire item back to JS
                if let jsonData = try? JSONSerialization.data(withJSONObject: itm),
                   let jsonStr  = String(data: jsonData, encoding: .utf8) {
                    CarConnect.emitListItemTapped(jsonStr)
                }
            }
            listItems.append(li)
        }

        let section = CPListSection(items: listItems)
        let list    = CPListTemplate(title: "Select an item", sections: [section])
        iface.pushTemplate(list, animated: true)
    }

    // MARK: - Show detail view

    @objc private func handleShowDetailView(_ note: Notification) {
        guard let uiPayload = note.userInfo?["payload"] as? [String: Any],
              let pairs   = uiPayload["pairs"]   as? [[String: Any]],
              let buttons = uiPayload["buttons"] as? [[String: Any]]?,
              let iface   = interfaceController else { return }

        // Compose rows
        var rows: [CPInformationItem] = []
        for p in pairs {
            let key   = p["key"]   as? String ?? ""
            let value = p["value"] as? String ?? ""
            rows.append(CPInformationItem(title: key, detail: value))
        }

        // Compose up to 2 actions
        var actions: [CPTextButton] = []
        if let btns = buttons {
            for b in btns.prefix(2) {
                let text = b["text"] as? String ?? "Button"
                let id   = b["id"]   as? String ?? ""
                let role = (b["type"] as? String)?.lowercased() == "primary"
                           ? CPTextButton.Role.confirm
                           : CPTextButton.Role.none

                let btn  = CPTextButton(title: text, style: role) { _ in
                    if let jsonData = try? JSONSerialization.data(withJSONObject: b),
                       let jsonStr  = String(data: jsonData, encoding: .utf8) {
                        CarConnect.emitDetailButtonPressed(jsonStr)
                    }
                }
                actions.append(btn)
            }
        }

        let pane = CPInformationTemplate(
            title: "Details",
            layout: .leading,
            items: rows,
            actions: actions
        )
        iface.pushTemplate(pane, animated: true)
    }
}
