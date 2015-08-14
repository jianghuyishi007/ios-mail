//
// Copyright 2015 ArcTouch, Inc.
// All rights reserved.
//
// This file, its contents, concepts, methods, behavior, and operation
// (collectively the "Software") are protected by trade secret, patent,
// and copyright laws. The use of the Software is governed by a license
// agreement. Disclosure of the Software to third parties, in any form,
// in whole or in part, is expressly prohibited except as authorized by
// the license agreement.
//

import UIKit

class MenuViewController: UIViewController {
    internal static let ObserverSwitchView:String = "Push_Switch_View"
    
    // MARK - Views Outlets
    
    @IBOutlet weak var displayNameLabel: UILabel!
    @IBOutlet weak var emailLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var headerView: UIView!
    
    // MARK: - Private constants
    
    private let inboxItems = [MenuItem.inbox, MenuItem.starred, MenuItem.drafts, MenuItem.sent, MenuItem.archive, MenuItem.trash, MenuItem.spam]
    private let otherItems = [MenuItem.contacts, MenuItem.settings, MenuItem.bugs, MenuItem.signout]
    private var fetchedLabels: NSFetchedResultsController?
    private var signingOut: Bool = false
    
    private let kMenuCellHeight: CGFloat = 44.0
    private let kMenuOptionsWidth: CGFloat = 300.0 //227.0
    private let kMenuOptionsWidthOffset: CGFloat = 80.0
    
    private let kSegueToMailbox: String = "toMailboxSegue"
    private let kSegueToSettings: String = "toSettingsSegue"
    private let kSegueToBugs: String = "toBugsSegue"
    private let kSegueToContacts: String = "toContactsSegue"
    
    private var kLastSegue: String = "toInbox"
    private var kLastMenuItem: MenuItem = MenuItem.inbox
    
    private let kMenuTableCellId = "menu_table_cell"
    private let kLabelTableCellId = "menu_label_cell"
    
    // private data
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    deinit{
        NSNotificationCenter.defaultCenter().removeObserver(self, name: MenuViewController.ObserverSwitchView, object: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let w = UIScreen.mainScreen().applicationFrame.width;
        
        setupFetchedResultsController()
        
        self.revealViewController().rearViewRevealWidth = w - kMenuOptionsWidthOffset
        
        tableView.dataSource = self
        tableView.delegate = self
        NSNotificationCenter.defaultCenter().addObserver(
            self,
            selector: "performLastSegue:",
            name: MenuViewController.ObserverSwitchView,
            object: nil)
        
        tableView.separatorInset = UIEdgeInsetsZero
        tableView.layoutMargins = UIEdgeInsetsZero
        
        sharedLabelsDataService.fetchLabels();
    }
    
    func performLastSegue(notification: NSNotification)
    {
        self.performSegueWithIdentifier(kLastSegue, sender: self)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        self.revealViewController().frontViewController.view.userInteractionEnabled = false
        self.revealViewController().view.addGestureRecognizer(self.revealViewController().panGestureRecognizer())
        
        updateEmailLabel()
        updateDisplayNameLabel()
        tableView.reloadData()
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        self.revealViewController().frontViewController.view.userInteractionEnabled = true
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        let navigationController = segue.destinationViewController as! UINavigationController
        
        if let firstViewController: UIViewController = navigationController.viewControllers.first as? UIViewController {
            if (firstViewController.isKindOfClass(MailboxViewController)) {
                let mailboxViewController: MailboxViewController = navigationController.viewControllers.first as! MailboxViewController
                if let indexPath = sender as? NSIndexPath {
                    let count = fetchedLabels?.fetchedObjects?.count
                    
                    kLastSegue = segue.identifier!
                    if indexPath.section == 0 {
                        self.kLastMenuItem = self.itemForIndexPath(indexPath)
                        switch(self.kLastMenuItem) {
                        case .inbox:
                            mailboxViewController.mailboxLocation = .inbox
                            mailboxViewController.setNavigationTitleText("INBOX")
                        case .starred:
                            mailboxViewController.mailboxLocation = .starred
                            mailboxViewController.setNavigationTitleText("STARRED")
                        case .drafts:
                            mailboxViewController.mailboxLocation = .draft
                            mailboxViewController.setNavigationTitleText("DRAFTS")
                        case .sent:
                            mailboxViewController.mailboxLocation = .outbox
                            mailboxViewController.setNavigationTitleText("SENT")
                        case .trash:
                            mailboxViewController.mailboxLocation = .trash
                            mailboxViewController.setNavigationTitleText("TRASH")
                        case .archive:
                            mailboxViewController.mailboxLocation = .archive
                            mailboxViewController.setNavigationTitleText("ARCHIVE")
                        case .spam:
                            mailboxViewController.mailboxLocation = .spam
                            mailboxViewController.setNavigationTitleText("SPAM")
                        default:
                            mailboxViewController.mailboxLocation = .inbox
                            mailboxViewController.setNavigationTitleText("INBOX")
                        }
                    } else if indexPath.section == 1 {
                        
                    } else if indexPath.section == 2 {
                        
                    } else {
                        
                    }
                }
            }
        }
    }
    
    
    // MARK: - Methods
    
    private func setupFetchedResultsController() {
        self.fetchedLabels = sharedLabelsDataService.fetchedResultsController()
        self.fetchedLabels?.delegate = self
        
        NSLog("\(__FUNCTION__) INFO: \(fetchedLabels?.sections)")
        
        if let fetchedResultsController = fetchedLabels {
            var error: NSError?
            if !fetchedResultsController.performFetch(&error) {
                NSLog("\(__FUNCTION__) error: \(error)")
            }
        }
    }
    
    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return UIStatusBarStyle.LightContent
    }
    
    func handleSignOut() {
        let alertController = UIAlertController(title: NSLocalizedString("Confirm"), message: nil, preferredStyle: .ActionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Sign Out"), style: .Destructive, handler: { (action) -> Void in
            self.signingOut = true
            sharedUserDataService.signOut(true)
            userCachedStatus.signOut()
        }))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel"), style: .Cancel, handler: nil))
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    func itemForIndexPath(indexPath: NSIndexPath) -> MenuItem {
        return inboxItems[indexPath.row]
    }
    
    func updateDisplayNameLabel() {
        let displayName = sharedUserDataService.displayName
        
        if !displayName.isEmpty {
            displayNameLabel.text = displayName
            return
        }
        
        displayNameLabel.text = emailLabel.text
    }
    
    func updateEmailLabel() {
        if let username = sharedUserDataService.username {
            if !username.isEmpty {
                emailLabel.text = "\(username)@protonmail.ch"
                return
            }
        }
        emailLabel.text = ""
    }
}

extension MenuViewController: UITableViewDelegate {
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 3
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return kMenuCellHeight
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        
        if indexPath.section == 0 {
            //inbox
            self.performSegueWithIdentifier(kSegueToMailbox, sender: indexPath);
        } else if (indexPath.section == 1) {
            //others
            let item = otherItems[indexPath.row]
            if item == .signout {
                tableView.deselectRowAtIndexPath(indexPath, animated: true)
                self.handleSignOut()
            } else if item == .settings {
                self.performSegueWithIdentifier(kSegueToSettings, sender: indexPath);
            } else if item == .bugs {
                self.performSegueWithIdentifier(kSegueToBugs, sender: indexPath);
            } else if item == .contacts {
                self.performSegueWithIdentifier(kSegueToContacts, sender: indexPath);
            }
        } else if (indexPath.section == 2) {
            //labels
        }
    }
}

extension MenuViewController: UITableViewDataSource {
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return inboxItems.count
        } else if (section == 1) {
            return otherItems.count
        } else if (section == 2) {
            //fetchedLabels?.fetchedObjects?.count
            let count = fetchedLabels?.numberOfRowsInSection(0) ?? 0
            return count
        }
        return 0
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            var cell = tableView.dequeueReusableCellWithIdentifier(kMenuTableCellId, forIndexPath: indexPath) as! MenuTableViewCell
            cell.configCell(inboxItems[indexPath.row])
            cell.configUnreadCount()
            return cell
        } else if indexPath.section == 1 {
            var cell = tableView.dequeueReusableCellWithIdentifier(kMenuTableCellId, forIndexPath: indexPath) as! MenuTableViewCell
            cell.configCell(otherItems[indexPath.row])
            cell.configUnreadCount()
            return cell
        } else if indexPath.section == 2 {
            let data = fetchedLabels?.objectAtIndexPath(NSIndexPath(forRow: indexPath.row, inSection: 0)) as! Label;
            
            var cell = tableView.dequeueReusableCellWithIdentifier(kLabelTableCellId, forIndexPath: indexPath) as! MenuLabelViewCell
            cell.configCell(data)
            cell.configUnreadCount()
            
            return cell
        } else {
            var cell: MenuTableViewCell = tableView.dequeueReusableCellWithIdentifier(kMenuTableCellId, forIndexPath: indexPath) as! MenuTableViewCell
            return cell
        }
    }
    
    func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 1.0
    }
}


extension MenuViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        if !signingOut {
            tableView.endUpdates()
        }
    }
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        if !signingOut {
            tableView.beginUpdates()
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        if !signingOut {
            switch(type) {
            case .Delete:
                tableView.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Fade)
            case .Insert:
                tableView.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Fade)
            default:
                return
            }
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        if !signingOut {
            switch(type) {
            case .Delete:
                if let indexPath = indexPath {
                    tableView.deleteRowsAtIndexPaths([NSIndexPath(forRow: indexPath.row, inSection: 2)], withRowAnimation: UITableViewRowAnimation.Fade)
                }
            case .Insert:
                if let newIndexPath = newIndexPath {
                    tableView.insertRowsAtIndexPaths([NSIndexPath(forRow: newIndexPath.row, inSection: 2)], withRowAnimation: UITableViewRowAnimation.Fade)
                }
            case .Update:
                if let indexPath = indexPath {
                    let index = NSIndexPath(forRow: indexPath.row, inSection: 2)
                    if let cell = tableView.cellForRowAtIndexPath(index) as? MenuLabelViewCell {
                        if let label = fetchedLabels?.objectAtIndexPath(index) as? Label {
                            cell.configCell(label);
                            cell.configUnreadCount()
                        }
                    }
                    
                }
            default:
                return
            }
        }
    }
}
