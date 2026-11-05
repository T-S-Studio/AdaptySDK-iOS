//
//  StoreKit.Product+Purchase.swift
//  AdaptySDK
//
//  Created by Alexey Goncharov on 15.01.2025.
//

import StoreKit

#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension StoreKit.Product {
    func unfPurchase(
        options: Set<Product.PurchaseOption> = []
    ) async throws -> PurchaseResult {
        #if os(visionOS)
        if let scene = UIApplication.shared.activeScene {
            try await purchase(confirmIn: scene, options: options)
        } else {
            throw AdaptyError.cantMakePayments()
        }
        #elseif os(iOS) || os(tvOS)
        // appkit fork: from iOS 17 the purchase is ALWAYS anchored to a scene.
        // Upstream anchors it to the top view controller of the key window of a
        // `.foregroundActive` scene and otherwise falls back to the scene-less
        // `purchase(options:)`. A purchase started while the scene is only
        // `.foregroundInactive` (a system alert or sheet over the app, an iPhone
        // app in iPad compatibility mode) took that fallback, and on iOS 27
        // StoreKit then logs "Could not find a UI anchor" and throws before the
        // payment sheet appears (AdaptyError 1006). A scene in any state is a
        // valid anchor, so it is looked up in order of preference, and without
        // one the purchase is refused rather than started blind (the same rule
        // the visionOS branch above applies).
        // Upstream issue: https://github.com/adaptyteam/AdaptySDK-iOS/issues/183
        if #available(iOS 17.0, tvOS 17.0, *) {
            guard let scene = UIApplication.shared.purchaseConfirmationScene else {
                throw AdaptyError.cantMakePayments()
            }
            return try await purchase(confirmIn: scene, options: options)
        } else {
            return try await purchase(options: options)
        }
        #else
        try await purchase(options: options)
        #endif
    }
}

#if canImport(UIKit)
@MainActor
extension UIApplication {
    /// Returns the key `UIWindowScene` for the current application
    fileprivate var activeScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    /// The scene to confirm a purchase in (appkit fork): the active scene, else
    /// an inactive one in the foreground, else any connected window scene.
    var purchaseConfirmationScene: UIWindowScene? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// Returns the top-most presented view controller starting from the root of the key window.
    var topPresentedController: UIViewController? {
        activeScene?
            .windows
            .first(where: { $0.isKeyWindow })?
            .rootViewController?
            .topPresentedController()
    }
}

@MainActor
private extension UIViewController {
    /// Returns the top-most presented view controller from the current view controller.
    func topPresentedController() -> UIViewController {
        var topController: UIViewController = self

        while let presented = topController.presentedViewController {
            topController = presented
        }

        return topController.drillDownToChild()
    }

    /// Drills down into `UINavigationController` or `UITabBarController` to find the visible or selected child controller.
    private func drillDownToChild() -> UIViewController {
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.drillDownToChild() ?? navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.drillDownToChild() ?? tabBarController
        }

        return self
    }
}

#endif
