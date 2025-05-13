/**
 * PhoneSceneDelegate.swift – Implements the delegate for showing the screens on the phone.
 *
 * Copyright © 2025 RIKSOF. MIT License.
 */
import UIKit
import Cordova

@available(iOS 14.0, *)
class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let winScene = scene as? UIWindowScene else { return }

        let w = UIWindow(windowScene: winScene)
        w.rootViewController = CDVViewController()   // Cordova’s main VC
        window = w
        w.makeKeyAndVisible()
    }
}
