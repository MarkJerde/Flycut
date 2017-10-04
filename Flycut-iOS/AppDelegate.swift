//
//  AppDelegate.swift
//  Flycut-iOS
//
//  Created by Mark Jerde on 7/12/17.
//
//

import UIKit
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

	var window: UIWindow?

	var myViewController: ViewController!

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		let appDelegate = UIApplication.shared.delegate as! AppDelegate
		let viewController = self.window?.rootViewController as! ViewController

		appDelegate.myViewController = viewController

		let center = UNUserNotificationCenter.current()
		center.requestAuthorization(options:[]) { (granted, error) in
			// Enable or disable features based on authorization.
		}
		application.registerForRemoteNotifications()

		return true
	}

	/*func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject], fetchCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
	}*/
	func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		print("Thanks for the remote notification!")
	}

	func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {

		let deviceTokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
		print(deviceTokenString)


	}

	func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {

		print("i am not available in simulator \(error)")

	}

	func applicationWillResignActive(_ application: UIApplication) {
		// Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
		// Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
		myViewController.saveEngine();
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		// Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
		// If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
		myViewController.saveEngine();
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		// Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		// Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
		myViewController.checkForClippingAddedToClipboard()
	}

	func applicationWillTerminate(_ application: UIApplication) {
		// Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
		myViewController.saveEngine();
	}


}

