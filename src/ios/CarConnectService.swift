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
class CarConnectService: NSObject, CPInterfaceControllerDelegate {

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

    // MARK: - Placeholder bookkeeping -----------------------------------
    private var placeholderTemplateRef: CPListTemplate?
    private var detailTemplateRef: CPInformationTemplate?
    private var listTemplateRef: CPListTemplate?

    // Customisable placeholder strings  (set by  CarConnect.initialize)
    private var startupTitle: String?
    private var startupMessage: String?

    /** 
     * Update the placeholder strings shown on the root template.
     * – If only the **message** changes → mutate the existing row in place.
     * – If the **title** changes → replace the root *once* (debounced via
     *   `runTemplateOp`).
     */
    func configure(startupTitle: String?, startupMessage: String?) {
        self.startupTitle   = startupTitle
        self.startupMessage = startupMessage

        DispatchQueue.main.async { [weak self] in
            guard let self, let iface = self.interfaceController else { return }

            // rebuild placeholder, clear any previous refs
            let root = self.buildPlaceholderTemplate()
            self.placeholderTemplateRef = root
            self.listTemplateRef   = nil
            self.detailTemplateRef = nil

            // pop everything & install the fresh placeholder as the new root
            iface.setRootTemplate(root, animated: false, completion: nil)
        }
    }

    // Called from SceneDelegate when CarPlay scene connects
    func scene(_ scene: CPTemplateApplicationScene,
               didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        self.interfaceController?.delegate = self
        connectionState          = .carPlay

        let root = buildPlaceholderTemplate()
        interfaceController.setRootTemplate(root,
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
    private func buildPlaceholderTemplate() -> CPListTemplate {
        // 1️⃣ values supplied from JS-side init() if available …
        if let t = startupTitle, let m = startupMessage {
            let item    = CPListItem(text: m, detailText: nil)
            let section = CPListSection(items: [item])
            return CPListTemplate(title: t, sections: [section])
        }

        // 2️⃣ …otherwise fall back to Info.plist defaults
        let startup = Bundle.main.object(forInfoDictionaryKey: "CarConnectStartup") as? [String: Any]
        let t       = startup?["Title"]   as? String ?? "Car Connect"
        let m       = startup?["Message"] as? String ?? "Open the app on your phone."

        let item    = CPListItem(text: m, detailText: nil)
        item.handler = { _, completion in
            CarConnect.emitListItemTapped("")
            completion()
        }

        let section = CPListSection(items: [item])
        let tpl     = CPListTemplate(title: t, sections: [section])
        placeholderTemplateRef = tpl                      // <-- NEW
        return tpl
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
            let items   = payload["items"] as? [[String: Any]]
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
            li.handler = { _, completion in
                // Send the event to JavaScript
                if let data  = try? JSONSerialization.data(withJSONObject: item),
                    let json  = String(data: data, encoding: .utf8) {
                    CarConnect.emitListItemTapped(json)
                }

                completion()          // stop spinner
            }

            return li
        })

        // --- If the list template already exists → update it in place --
        if let tpl = listTemplateRef {
            if tpl.title == listTitle {
                // same title → safe to mutate just the rows/sections
                tpl.updateSections([section])
                replaceTemplate(existingOfType: CPListTemplate.self, with: tpl)
                return
            } else {
                // title changed → need a new template
                listTemplateRef = nil   // fall through to create-push block
            }
        }

        // --- First-time push → build & store ---------------------------
        let tpl = CPListTemplate(title: listTitle, sections: [section])
        listTemplateRef = tpl
        replaceTemplate(existingOfType: CPListTemplate.self, with: tpl)
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
            let buttons = payload["buttons"] as? [[String: Any]]
        else { return }

        // ---------------- Build the new CPInformationTemplate -------------
        let title = payload["title"] as? String ?? "Details"

        let rows = pairs.map {
            CPInformationItem(title: $0["key"] as? String ?? "",
                          detail: $0["value"] as? String ?? "")
        }

        let actions = buttons.prefix(2).map { b -> CPTextButton in
            let style: CPTextButtonStyle =
                (b["type"] as? String)?.lowercased() == "primary" ? .confirm : .normal

            return CPTextButton(title: b["text"] as? String ?? "Button",
                                textStyle: style) { _ in
                if let data  = try? JSONSerialization.data(withJSONObject: b),
                let json  = String(data: data, encoding: .utf8) {
                    CarConnect.emitDetailButtonPressed(json)
                }
            }
        }

        // ------------------------------------------------------------------
        //  1. If the template already exists → update it in place
        // ------------------------------------------------------------------
        if let tmpl = detailTemplateRef {
            tmpl.items   = rows
            tmpl.actions = actions
            // Bring it to the top if it isn’t already
            replaceTemplate(existingOfType: CPInformationTemplate.self, with: tmpl)
            return
        }

        // ------------------------------------------------------------------
        //  2. Otherwise build & push a fresh template once
        // ------------------------------------------------------------------
        let pane = CPInformationTemplate(title: title,
                                     layout: .leading,
                                     items: rows,
                                     actions: actions)

        
        detailTemplateRef = pane           // keep a strong reference
        replaceTemplate(existingOfType: CPInformationTemplate.self, with: pane)
    }

    func goBack() {
        guard let iface = interfaceController else { return }

        // Don’t pop the root placeholder:
        guard let top = iface.topTemplate,
              !(top is CPListTemplate) else { return }

        iface.popTemplate(animated: true, completion: nil)
    }

    // MARK: - CPInterfaceControllerDelegate -------------------------------
    func interfaceController(_ interfaceController: CPInterfaceController,
                         didPop template: CPTemplate,
                         animated: Bool) {

        if template is CPListTemplate {
            CarConnect.closeListCallback()
            listTemplateRef = nil
        } else if template is CPInformationTemplate {
            CarConnect.closeDetailCallback()
            detailTemplateRef = nil
        }
    }

    // MARK: - Template-stack utilities ------------------------------------
    /**
     * Replaces the first existing template of the given type (above the root
     * placeholder) with `newTemplate`. Chooses the animation automatically:
     * - If a replacement happened → brings the existing template of the given type to 
     *   the top of the stack.
     * - If no existing template found → push *with* animation.
     */
    private func replaceTemplate<T: CPTemplate>(
        existingOfType _: T.Type,
        with newTemplate: T
    ) {
        guard let iface = interfaceController else { return }

        let stackDepth   = iface.templates.count        // root counts as 1
        let maxDepth     = 5                            // Apple-documented limit
        NSLog("🚘 CarPlay stack depth = %d / %d", stackDepth, maxDepth)

        // 1️⃣ If the desired template -type- already exists above the root…
        for (idx, tpl) in iface.templates.enumerated() where idx > 0 && tpl is T {

            // If it’s already on top → nothing to do
            if iface.topTemplate === tpl { return }

            // Otherwise just pop back to it (brings it to top)
        //runTemplateOp {
            iface.pop(to: tpl, animated: true) { [weak self] _, _ in
                self?.templateOpDidFinish()
            }
        //}
            return
        }

        // 2️⃣ No template of that type in the stack → normal first-time push
    //runTemplateOp {
        if iface.topTemplate === placeholderTemplateRef {
            // Root is the placeholder → swap it for the new screen
            placeholderTemplateRef = nil             // placeholder no longer visible
            iface.setRootTemplate(newTemplate,
                          animated: true) { [weak self] _, _ in
                self?.templateOpDidFinish()
            }
        } else {
            // Normal case: push on top of whatever is showing
            iface.pushTemplate(newTemplate,
                       animated: true) { [weak self] _, _ in
                self?.templateOpDidFinish()
            }
        }
    //}
    }

    // MARK: - Template-operation serialiser -------------------------------
    private var templateOpBusy = false
    private var templateOpQueue: [() -> Void] = []

    private func runTemplateOp(_ op: @escaping () -> Void) {
        if templateOpBusy {
            templateOpQueue.append(op)
            return
        }
        templateOpBusy = true
        op()
    }

    private func templateOpDidFinish() {
        templateOpBusy = false
        if !templateOpQueue.isEmpty {
            let next = templateOpQueue.removeFirst()
            // run on next run-loop tick (always main queue)
            DispatchQueue.main.async { self.runTemplateOp(next) }
        }
    }

    // MARK: - Helper to rebuild the single-row placeholder section ----------
    private func buildPlaceholderSection(message: String?) -> CPListSection {
        let row = CPListItem(text: message ?? "", detailText: nil)
        return CPListSection(items: [row])
    }
}


