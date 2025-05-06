/**
 * SceneDelegate.swift – Implements the delegate for showing the screens.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */
import UIKit
import CarPlay

@available(iOS 14.0, *)
class SceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    /// Called when the CarPlay scene becomes active.
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {

        CarConnectService.shared.scene(templateApplicationScene,
                                       didConnect: interfaceController,
                                       to: window)
    }

    /// Called when the CarPlay scene disconnects.
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {

        CarConnectService.shared.sceneDidDisconnect(templateApplicationScene)
    }
}

