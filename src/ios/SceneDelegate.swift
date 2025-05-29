/**
 * SceneDelegate.swift – Implements the delegate for showing the screens.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */
import UIKit
import CarPlay

@available(iOS 14.0, *)
class SceneDelegate: UIResponder {

    private var interfaceController: CPInterfaceController?
}

/* --------------------------------------------------------------------
 *  MARK: - CPTemplateApplicationSceneDelegate
 * ------------------------------------------------------------------ */
@available(iOS 14.0, *)
extension SceneDelegate: CPTemplateApplicationSceneDelegate {

    /// CarPlay scene connected (non-navigation apps).
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {

        self.interfaceController = interfaceController
        CarConnectService.shared.scene(templateApplicationScene,
                                       didConnect: interfaceController)
    }
}

extension SceneDelegate {
    /// CarPlay scene disconnected.
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {

        CarConnectService.shared.sceneDidDisconnect(templateApplicationScene)
        self.interfaceController = nil
    }
}



