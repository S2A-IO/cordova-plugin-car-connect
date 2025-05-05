/**
 * SceneDelegate.swift – Implements the delegate for showing the screens.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */
import UIKit
import CarPlay

@available(iOS 14.0, *)
class SceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: UIWindow) {
        CarConnectService.shared.scene(scene,
                                       didConnect: interfaceController,
                                       to: window)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: UIWindow) {
        CarConnectService.shared.sceneDidDisconnect(scene)
    }
}
