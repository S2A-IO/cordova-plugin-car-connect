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
                                            animated: false, completion: nil)
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
        DispatchQueue.main.async { [weak self] in
            self?.handleShowListViewInternal(note)
        }
    }

    @objc
    private func handleShowListViewInternal(_ note: Notification) {
        guard
            let payload = note.userInfo?["payload"] as? [String: Any],
            let items   = payload["items"] as? [[String: Any]],
            let iface   = interfaceController
        else { return }

        let listTitle = payload["title"] as? String ?? "Select an item"

        // Build the section
        let section = CPListSection(items: items.map { item in
            let li = CPListItem(
                text:       item["title"]       as? String ?? "",
                detailText: item["description"] as? String ?? ""
            )

            // 1. Placeholder
            li.setImage(UIImage(systemName: "photo.on.rectangle"))

            // 2. Resolve the image
            if let raw = item["image"] as? String, !raw.isEmpty {
                if let url = URL(string: raw), url.scheme != nil {
                    // Remote or file:// URL ➜ fetch & cache
                    ImageCacheProvider.shared.fetch(url) { [weak li] img in
                        guard let img else { return }
                        DispatchQueue.main.async {
                            li?.setImage(img)                // safe on main thread
                        }
                    }
                } else if let asset = UIImage(named: raw) {
                    li.setImage(asset)                 //  asset name in bundle
                }
            }

            // 3. Tap-handler
            li.handler = { _, _ in
                guard
                    let data = try? JSONSerialization.data(withJSONObject: item),
                    let json = String(data: data, encoding: .utf8)
                else { return }
                CarConnect.emitListItemTapped(json)
            }
            return li
        })

        // Re-use template if it’s already on screen
        if
            let current = iface.topTemplate as? CPListTemplate,
            current.title == listTitle
        {
            current.updateSections([section])
            return
        }

        // Otherwise make it the new root
        let tpl = CPListTemplate(title: listTitle, sections: [section])
        iface.setRootTemplate(tpl, animated: true, completion: nil)
    }

    // MARK: - Show detail view ------------------------------------------
    @objc private func handleShowDetailView(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.handleShowDetailViewInternal(note)
        }
    }

    @objc private func handleShowDetailViewInternal(_ note: Notification) {
        guard
            let payload = note.userInfo?["payload"] as? [String: Any],
            let pairs   = payload["pairs"]   as? [[String: Any]],
            let buttons = payload["buttons"] as? [[String: Any]],
            let iface   = interfaceController
        else { return }

        // ───────── Build the new CPInformationTemplate ─────────
        let title   = payload["title"] as? String ?? "Details"

        let rows    = pairs.map {
            CPInformationItem(title: $0["key"] as? String ?? "",
                          detail: $0["value"] as? String ?? "")
        }

        let actions = buttons.prefix(2).map { btnJSON -> CPTextButton in
            let style: CPTextButtonStyle =
                (btnJSON["type"] as? String)?.lowercased() == "primary" ? .confirm : .normal

            return CPTextButton(title: btnJSON["text"] as? String ?? "Button",
                            textStyle: style) { _ in
                if let data = try? JSONSerialization.data(withJSONObject: btnJSON),
                let json = String(data: data, encoding: .utf8) {
                    CarConnect.emitDetailButtonPressed(json)
                }
            }
        }

        let pane = CPInformationTemplate(title: title,
                                     layout: .leading,
                                     items: rows,
                                     actions: actions)

        // ───────── Replace or pop-and-push to stay within CarPlay’s 5-template limit ─────────
        if let current = iface.topTemplate as? CPInformationTemplate {
            if #available(iOS 17.0, *) {
                // Native replace API (non-blocking) avoids flicker
                iface.replaceTemplate(current, with: pane, animated: true, completion: nil)
            } else {
                // Earlier iOS – pop current, then push the new one
                iface.popTemplate(animated: false) { _ in
                    iface.pushTemplate(pane, animated: true, completion: nil)
                }
            }
        } else {
            // No detail screen on top yet – just push
            iface.pushTemplate(pane, animated: true, completion: nil)
        }
    }
}


