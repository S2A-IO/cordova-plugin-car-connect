/**
 * SceneDelegate.swift – Implements the delegate for showing the screens.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */
import UIKit
import CarPlay

@available(iOS 14.0, *)
class SceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    /// CarPlay scene connected (non-navigation apps use this signature).
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController

        // Hand-off to your shared service to build / push templates.
        CarConnectService.shared.scene(templateApplicationScene,
                                       didConnect: interfaceController)
    }

    /// CarPlay scene disconnected.
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {

        CarConnectService.shared.sceneDidDisconnect(templateApplicationScene)
        self.interfaceController = nil
    }
}



