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
import UIKit
import CarPlay

@available(iOS 14.0, *)
class CarConnectService: NSObject {

    // MARK: - Singleton -------------------------------------------------
    static let shared = CarConnectService()
    private override init() {
        super.init()
        registerForPluginNotifications()
    }

    // MARK: - Connection state (0 / 1 / 2) ------------------------------
    enum State: Int { case none = 0, carPlay = 1, androidAuto = 2 }
    private(set) var connectionState: State = .none

    // MARK: - Scene references ------------------------------------------
    private weak var interfaceController: CPInterfaceController?

    // Called from SceneDelegate when CarPlay scene connects
    func scene(_ scene: CPTemplateApplicationScene,
               didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        connectionState          = .carPlay

        interfaceController.setRootTemplate(placeholderTemplate(),
                                            animated: false)
    }

    // For future-proofing you may keep the window variant and forward to
    // the two-parameter method; harmless if never called.
    func scene(_ scene: CPTemplateApplicationScene,
               didConnect interfaceController: CPInterfaceController,
               to window: CPWindow) {

        self.scene(scene, didConnect: interfaceController)
    }

    // -------------------------------------------------------------------
    //  CarPlay scene disconnected
    // -------------------------------------------------------------------
    func sceneDidDisconnect(_ scene: CPTemplateApplicationScene) {
        connectionState    = .none
        interfaceController = nil
    }

    // MARK: - Placeholder template --------------------------------------
    private func placeholderTemplate() -> CPTemplate {
        // Values injected via plugin.xml → Info.plist
        let startup  = Bundle.main.object(forInfoDictionaryKey: "CarConnectStartup") as? [String: Any]
        let title    = startup?["Title"]   as? String ?? "Car Connect"
        let message  = startup?["Message"] as? String ?? "Open the app on your phone."

        let item    = CPListItem(text: message, detailText: nil)
        let section = CPListSection(items: [item])
        return CPListTemplate(title: title, sections: [section])
    }

    // MARK: - Notification wiring ---------------------------------------
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

    // MARK: - Show list view --------------------------------------------
    @objc private func handleShowListView(_ note: Notification) {
        guard
            let payload = note.userInfo?["payload"] as? [String: Any],
            let items   = payload["items"] as? [[String: Any]],
            let iface   = interfaceController
        else { return }

        // Title sent from JS; fall back to a sensible default
        let listTitle = payload["title"] as? String ?? "Select an item"

        // Build section
        let section = CPListSection(items: items.map { item in
            let li = CPListItem(
                text: item["title"] as? String ?? "",
                detailText: item["description"] as? String ?? ""
            )
            li.handler = { _, _ in
                if
                let data = try? JSONSerialization.data(withJSONObject: item),
                let json = String(data: data, encoding: .utf8) {
                    CarConnect.emitListItemTapped(json)
                }
            }
            return li
        })

        // If a list is already on top, just refresh its contents
        if let current = iface.topTemplate as? CPListTemplate {
            current.updateSections([section])
            //  Update title if it changed (iOS 14+: `title` is writable)
            if current.title != listTitle {
                current.title = listTitle
            }
            return
        }

        // Otherwise reset the stack with this list as the new root
        let listTpl = CPListTemplate(title: listTitle,
                                 sections: [section])
        iface.setRootTemplate(listTpl, animated: true)
    }


    // MARK: - Show detail view ------------------------------------------
    @objc private func handleShowDetailView(_ note: Notification) {
        guard
            let payload = note.userInfo?["payload"] as? [String: Any],
            let pairs   = payload["pairs"]   as? [[String: Any]],
            let buttons = payload["buttons"] as? [[String: Any]],
            let iface   = interfaceController
        else { return }

        // Title sent from JS; fall back to a sensible default
        let title = payload["title"] as? String ?? "Details"

        // Rows
        var rows = [CPInformationItem]()
        for p in pairs {
            rows.append(CPInformationItem(title: p["key"] as? String ?? "",
                                          detail: p["value"] as? String ?? ""))
        }

        // Up to two buttons
        var actions = [CPTextButton]()
        for b in buttons.prefix(2) {
            let style: CPTextButtonStyle =
                (b["type"] as? String)?.lowercased() == "primary"
                ? .confirm : .normal

            let btn = CPTextButton(title: b["text"] as? String ?? "Button",
                                   textStyle: style) { _ in
                if
                  let data = try? JSONSerialization.data(withJSONObject: b),
                  let json = String(data: data, encoding: .utf8) {
                    CarConnect.emitDetailButtonPressed(json)
                }
            }
            actions.append(btn)
        }

        let pane = CPInformationTemplate(title: title,
                                         layout: .leading,
                                         items: rows,
                                         actions: actions)
        iface.pushTemplate(pane, animated: true)
    }
}


