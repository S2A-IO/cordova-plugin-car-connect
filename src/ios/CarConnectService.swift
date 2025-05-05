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

@available(iOS 14.0, *)
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

    // Call from SceneDelegate when CarPlay scene connects
    func scene(_ scene: CPTemplateApplicationScene,
               didConnect interfaceController: CPInterfaceController,
               to window: UIWindow) {

        self.interfaceController = interfaceController
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
        guard
            #available(iOS 14.0, *),
            let payload = note.userInfo?["payload"] as? [String: Any],
            let items   = payload["items"] as? [[String: Any]],
            let iface   = interfaceController
        else { return }

        var listItems: [CPListItem] = []

        for itm in items {
            let li = CPListItem(text: itm["title"] as? String ?? "",
                                detailText: itm["description"] as? String ?? "")
            li.handler = { _, _ in         // handler is iOS 14+
                if
                  let data = try? JSONSerialization.data(withJSONObject: itm),
                  let json = String(data: data, encoding: .utf8) {
                    CarConnect.emitListItemTapped(json)
                }
            }
            listItems.append(li)
        }

        let section = CPListSection(items: listItems)
        let listTpl = CPListTemplate(title: "Select an item",
                                     sections: [section])
        iface.pushTemplate(listTpl, animated: true)
    }

    // MARK: - Show detail view

    @objc private func handleShowDetailView(_ note: Notification) {
        guard
            #available(iOS 14.0, *),
            let payload = note.userInfo?["payload"] as? [String: Any],
            let pairs   = payload["pairs"]   as? [[String: Any]],
            let buttons = payload["buttons"] as? [[String: Any]],
            let iface   = interfaceController
        else { return }

        // Key/value rows
        var rows: [CPInformationItem] = []
        for p in pairs {
            rows.append(CPInformationItem(title: p["key"] as? String ?? "",
                                          detail: p["value"] as? String ?? ""))
        }

        // Up to two buttons
        var actions: [CPTextButton] = []
        for b in buttons.prefix(2) {
            let style: CPTextButton.Style =
                (b["type"] as? String)?.lowercased() == "primary"
                ? .confirm : .normal

            let btn = CPTextButton(title: b["text"] as? String ?? "Button",
                                   style: style) { _ in
                if
                  let data = try? JSONSerialization.data(withJSONObject: b),
                  let json = String(data: data, encoding: .utf8) {
                    CarConnect.emitDetailButtonPressed(json)
                }
            }
            actions.append(btn)
        }

        let pane = CPInformationTemplate(title: "Details",
                                         layout: .leading,
                                         items: rows,
                                         actions: actions)
        iface.pushTemplate(pane, animated: true)
    }
}
