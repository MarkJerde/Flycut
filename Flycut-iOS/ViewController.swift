//
//  ViewController.swift
//  Flycut-iOS
//
//  Created by Mark Jerde on 7/12/17.
//
//

import UIKit

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, FlycutStoreDelegate {

	let flycut:FlycutOperator = FlycutOperator()
	var activeUpdates:Int = 0
	var tableView:UITableView!
	var currentAnimation = UITableViewRowAnimation.none

	// Some buttons we will reuse.
	var deleteButton:MGSwipeButton? = nil
	var openURLButton:MGSwipeButton? = nil

	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.

		tableView = self.view.subviews.first as! UITableView
		tableView.delegate = self
		tableView.dataSource = self

		tableView.register(MGSwipeTableCell.self, forCellReuseIdentifier: "FlycutCell")

		deleteButton = MGSwipeButton(title: "Delete", backgroundColor: .red, callback: { (cell) -> Bool in
			let indexPath = self.tableView.indexPath(for: cell)
			if ( nil != indexPath ) {
				let previousAnimation = self.currentAnimation
				self.currentAnimation = UITableViewRowAnimation.left // Use .left to look better with swiping left to delete.
				self.flycut.setStackPositionTo( Int32((indexPath?.row)! ))
				self.flycut.clearItemAtStackPosition()
				self.currentAnimation = previousAnimation
			}

			return true;
		})

		openURLButton = MGSwipeButton(title: "Open", backgroundColor: .blue, callback: { (cell) -> Bool in
			let indexPath = self.tableView.indexPath(for: cell)
			if ( nil != indexPath ) {
				let url = URL(string: self.flycut.clippingString(withCount: Int32((indexPath?.row)!) )! )
				UIApplication.shared.open(url!, options: [:], completionHandler: nil)
				self.tableView.reloadRows(at: [indexPath!], with: UITableViewRowAnimation.none)
			}

			return true;
		})

		// Enable sync by default on iOS until we have a mechanism to adjust preferences on-device.
		UserDefaults.standard.set(NSNumber(value: true), forKey: "syncSettingsViaICloud")
		UserDefaults.standard.set(NSNumber(value: true), forKey: "syncClippingsViaICloud")

		flycut.setClippingsStoreDelegate(self);

		flycut.awake(fromNibDisplaying: 10, withDisplayLength: 140, withSave: #selector(savePreferences(toDict:)), forTarget: self) // The 10 isn't used in iOS right now and 140 characters seems to be enough to cover the width of the largest screen.

		NotificationCenter.default.addObserver(self, selector: #selector(self.checkForClippingAddedToClipboard), name: .UIPasteboardChanged, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(self.applicationWillTerminate), name: .UIApplicationWillTerminate, object: nil)
	}

	func savePreferences(toDict: NSMutableDictionary)
	{
	}

	func beginUpdates()
	{
		if ( !Thread.isMainThread )
		{
			DispatchQueue.main.sync { beginUpdates() }
			return
		}

		print("Begin updates")
		print("Num rows: \(tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0))")
		if ( 0 == activeUpdates )
		{
			tableView.beginUpdates()
		}
		activeUpdates += 1
	}

	func endUpdates()
	{
		if ( !Thread.isMainThread )
		{
			DispatchQueue.main.sync { endUpdates() }
			return
		}

		print("End updates");
		activeUpdates -= 1;
		if ( 0 == activeUpdates )
		{
			tableView.endUpdates()
		}
	}

	func insertClipping(at index: Int32) {
		if ( !Thread.isMainThread )
		{
			DispatchQueue.main.sync { insertClipping(at: index) }
			return
		}
		print("Insert row \(index)")
		tableView.insertRows(at: [IndexPath(row: Int(index), section: 0)], with: currentAnimation) // We will override the animation for now, because we are the ViewController and should guide the UX.
	}

	func deleteClipping(at index: Int32) {
		if ( !Thread.isMainThread )
		{
			DispatchQueue.main.sync { deleteClipping(at: index) }
			return
		}
		print("Delete row \(index)")
		tableView.deleteRows(at: [IndexPath(row: Int(index), section: 0)], with: currentAnimation) // We will override the animation for now, because we are the ViewController and should guide the UX.
	}

	func reloadClipping(at index: Int32) {
		if ( !Thread.isMainThread )
		{
			DispatchQueue.main.sync { reloadClipping(at: index) }
			return
		}
		print("Reloading row \(index)")
		tableView.reloadRows(at: [IndexPath(row: Int(index), section: 0)], with: currentAnimation) // We will override the animation for now, because we are the ViewController and should guide the UX.
	}

	func moveClipping(at index: Int32, to newIndex: Int32) {
		if ( !Thread.isMainThread )
		{
			DispatchQueue.main.sync { moveClipping(at: index, to: newIndex) }
			return
		}
		print("Moving row \(index) to \(newIndex)")
		tableView.moveRow(at: IndexPath(row: Int(index), section: 0), to: IndexPath(row: Int(newIndex), section: 0))
	}

	func checkForClippingAddedToClipboard()
	{
		let pasteboard = UIPasteboard.general.string
		if ( nil != pasteboard )
		{
			flycut.addClipping(pasteboard, ofType: "public.utf8-plain-text", fromApp: "iOS", withAppBundleURL: "iOS", target: nil, clippingAddedSelector: nil)

		}
	}

	func applicationWillTerminate()
	{
		saveEngine()
	}

	func saveEngine()
	{
		flycut.saveEngine()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		saveEngine()
		// Dispose of any resources that can be recreated.
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return Int(flycut.jcListCount())
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let item: MGSwipeTableCell = tableView.dequeueReusableCell(withIdentifier: "FlycutCell", for: indexPath) as! MGSwipeTableCell

		item.textLabel?.text = flycut.previousDisplayStrings(indexPath.row + 1, containing: nil).last as! String?
		let content = flycut.clippingString(withCount: Int32(indexPath.row) )

		//configure left buttons
		if URL(string: content!) != nil {
			if (content?.lowercased().hasPrefix("http"))! {
				if(!item.leftButtons.contains(openURLButton!))
				{
					item.leftButtons.append(openURLButton!)
					item.leftSwipeSettings.transition = .border
					item.leftExpansion.buttonIndex=0
				}
			}
			else {
				item.leftButtons.removeAll()
			}
		}
		else {
			item.leftButtons.removeAll()
		}

		//configure right buttons
		if ( 0 == item.rightButtons.count )
		{
			// Setup the right buttons only if they haven't been before.
			item.rightButtons.append(deleteButton!)
			item.rightSwipeSettings.transition = .border
			item.rightExpansion.buttonIndex = 0
		}

		return item
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if ( MGSwipeState.none == (tableView.cellForRow(at: indexPath) as! MGSwipeTableCell).swipeState ) {
			tableView.deselectRow(at: indexPath, animated: true) // deselect before getPaste since getPaste may reorder the list
			let content = flycut.getPasteFrom(Int32(indexPath.row))
			print("Select: \(indexPath.row) \(content) OK")
			UIPasteboard.general.string = content
		}
	}
}

