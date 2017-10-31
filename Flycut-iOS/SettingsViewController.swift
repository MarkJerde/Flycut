//
//  SettingsView.swift
//  Flycut
//
//  Created by Mark Jerde on 10/24/17.
//
//

import Foundation

class SettingsViewController: IASKAppSettingsViewController {
	required init?(coder aDecoder: NSCoder) {
		super.init(style: .grouped)
		super.showCreditsFooter = false
	}
}
