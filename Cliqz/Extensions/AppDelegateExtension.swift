//
//  AppDelegateExtension.swift
//  Client
//
//  Created by Tim Palade on 5/25/18.
//  Copyright © 2018 Cliqz. All rights reserved.
//

import UIKit
import NetworkExtension
import QuickLook

let InstallDateKey = "InstallDateKey"
#if GHOSTERY
let HasRunBeforeKey = "previous_version"
#endif
extension AppDelegate {
    func recordInstallDateIfNecessary() {
        guard let profile = self.profile else { return }
        if profile.prefs.stringForKey(LatestAppVersionProfileKey)?.components(separatedBy: ".").first == nil {
            // Clean install, record install date
            if UserDefaults.standard.value(forKey: InstallDateKey) == nil {
                //Avoid overrides
                LocalDataStore.set(value: Date().timeIntervalSince1970, forKey: InstallDateKey)
            }
        }
    }
    
    /*
     * Navigation appearance for QLPreviewController needs to be treated separately.
     * We leave titleTextAttributes unchanged, as we don't want to show the title yet. In future we might consider to redesign this part.
    */
    func customizeNavigationBarAppearaceForQLPreviewController() {
        let navigationAppearanceForQLPreview = UINavigationBar.appearance(whenContainedInInstancesOf: [QLPreviewController.self])
        navigationAppearanceForQLPreview.tintColor = UIColor.cliqzBlueSystem
    }
    
    func customizeNnavigationBarAppearace() {
        let navigationBarAppearace = UINavigationBar.appearance()
        #if PAID
        navigationBarAppearace.barTintColor = Lumen.Browser.toolBarColor(lumenTheme, .Normal)
        #else
        navigationBarAppearace.barTintColor = UIColor.cliqzBluePrimary
        #endif
        
        self.customizeNavigationBarAppearaceForQLPreviewController()
        
        navigationBarAppearace.isTranslucent = false
        navigationBarAppearace.tintColor = UIColor.white
        navigationBarAppearace.titleTextAttributes = [NSAttributedStringKey.foregroundColor:UIColor.white]
    }

	func showBrowser() {
		let navigationController = UINavigationController(rootViewController: browserViewController)
		rootViewController = navigationController
		self.window!.rootViewController = rootViewController
		navigationController.delegate = self
		navigationController.isNavigationBarHidden = true
		navigationController.edgesForExtendedLayout = UIRectEdge(rawValue: 0)
        
        SubscriptionController.shared.requestProducts()
	}

	func showAuthentication() {
        /* Commented out Authentication
		let registrationViewController = RegistrationViewController()
		registrationViewController.profile = self.profile
		registrationViewController.tabManager = self.tabManager
		let navigationController = UINavigationController(rootViewController: registrationViewController)
		self.rootViewController = navigationController
		self.window!.rootViewController = rootViewController
        */
	}
}
