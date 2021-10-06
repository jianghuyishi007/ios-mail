//
//  EncryptedSearchService.swift
//  ProtonMail
//
//  Created by Ralph Ankele on 05.07.21.
//  Copyright © 2021 ProtonMail. All rights reserved.
//

import Foundation
import CoreData
import SwiftSoup
import SQLite
import Crypto
import CryptoKit
import Network
import Groot
import BackgroundTasks

extension Array {
    func chunks(_ chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
}

open class IndexSingleMessageAsyncOperation: Operation {
    public enum State: String {
        case ready = "Ready"
        case executing = "Executing"
        case finished = "Finished"
        fileprivate var keyPath: String { return "is" + self.rawValue }
    }
    private var stateStore: State = .ready
    private let stateQueue = DispatchQueue(label: "Async State Queue", attributes: .concurrent)
    public var state: State {
        get {
            stateQueue.sync {
                return stateStore
            }
        }
        set {
            let oldValue = state
            willChangeValue(forKey: state.keyPath)
            willChangeValue(forKey: newValue.keyPath)
            stateQueue.sync(flags: .barrier) {
                stateStore = newValue
            }
            didChangeValue(forKey: state.keyPath)
            didChangeValue(forKey: oldValue.keyPath)
        }
    }
    public let messageID: String
    
    init(_ messageID: String) {
        self.messageID = messageID
    }
    
    public override var isAsynchronous: Bool {
        return true
    }
    
    public override var isExecuting: Bool {
        return state == .executing
    }
    
    public override var isFinished: Bool {
        return state == .finished
    }
    
    public override func start() {
        if self.isCancelled {
            state = .finished
        } else {
            state = .ready
            main()
        }
    }
    
    public override func main() {
        if self.isCancelled {
            state = .finished
        } else {
            state = .executing
        }
        
        //print("processing message: \(self.messageID)")
        EncryptedSearchService.shared.getMessage(self.messageID) { message in
            //print("Message fetched: \(message!.messageID), details: \(message!.isDetailDownloaded)")
            EncryptedSearchService.shared.getMessageDetailsForSingleMessage(for: message!) { messageWithDetails in
                //print("Message detailes downloaded: \(messageWithDetails!.isDetailDownloaded)")
                EncryptedSearchService.shared.decryptAndExtractDataSingleMessage(for: messageWithDetails!) {
                    //print("Message \(self.messageID) sucessfully processed!")
                    EncryptedSearchService.shared.processedMessages += 1    //increase count of processed messages
                    self.state = .finished
                    
                    #if !APP_EXTENSION
                        //Update UI progress bar
                        EncryptedSearchService.shared.updateUIWithProgressBarStatus()
                    #endif
                }
            }
        }
    }
    
    public func finish() {
        state = .finished
    }
}

public class EncryptedSearchService {
    //instance of Singleton
    static let shared = EncryptedSearchService()
    
    //set initializer to private - Singleton
    private init(){
        let users: UsersManager = sharedServices.get()
        if users.firstUser != nil {
            user = users.firstUser //should return the currently active user
            messageService = user.messageService
        }
        
        self.timeFormatter.allowedUnits = [.hour, .minute, .second]
        self.timeFormatter.unitsStyle = .abbreviated
        
        self.internetStatusProvider = InternetConnectionStatusProvider()
        self.internetStatusProvider?.getConnectionStatuses(currentStatus: { status in
            if status.isConnected {
                print("Internet connection is active!")
            }
        })
        
        //enable temperature monitoring
        self.registerForTermalStateChangeNotifications()
    }
    
    internal var user: UserManager!
    internal var messageService: MessageDataService? = nil
    var totalMessages: Int = 0
    var limitPerRequest: Int = 1
    var lastMessageTimeIndexed: Int = 0     //stores the time of the last indexed message in case of an interrupt, or to fetch more than the limit of messages per request
    var processedMessages: Int = 0
    internal var prevProcessedMessages: Int = 0 //used to calculate estimated time for indexing
    internal var viewModel: SettingsEncryptedSearchViewModel? = nil
    
    internal var searchIndex: Connection? = nil
    internal var cipherForSearchIndex: EncryptedsearchAESGCMCipher? = nil
    internal var lastSearchQuery: String = ""
    internal var cacheSearchResults: EncryptedsearchResultList? = nil
    internal var indexSearchResults: EncryptedsearchResultList? = nil
    internal var searchState: EncryptedsearchSearchState? = nil
    internal var indexBuildingInProgress: Bool = false
    internal var indexingStartTime: Double = 0
    internal var eventsWhileIndexing: [MessageAction]? = []
    internal lazy var indexBuildingTimer: Timer? = nil
    
    lazy var messageIndexingQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Message Indexing Queue"
        //queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    internal lazy var internetStatusProvider: InternetConnectionStatusProvider? = nil
    
    internal var pauseIndexingDueToNetworkConnectivityIssues: Bool = false
    internal var pauseIndexingDueToOverheating: Bool = false
    internal var pauseIndexingDueToBackgroundTaskRunningOutOfTime = false
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    let timeFormatter = DateComponentsFormatter()
    
    internal var timingsBuildIndex: NSMutableArray = []
    internal var timingsMessageFetching: NSMutableArray = []
    internal var timingsMessageDetailsFetching: NSMutableArray = []
    internal var timingsDecryptMessages: NSMutableArray = []
    internal var timingsExtractData: NSMutableArray = []
    internal var timingsCreateEncryptedContent: NSMutableArray = []
    internal var timingsWriteToDatabase: NSMutableArray = []
    
    internal var timingsParseBody: NSMutableArray = []
    internal var timingsRemoveElements: NSMutableArray = []
    internal var timingsParseCleanedContent: NSMutableArray = []
    
    internal var startBackgroundTask: Double = 0.0
    internal var backgroundTaskCounter: Int = 0
}

extension EncryptedSearchService {
    //function to build the search index needed for encrypted search
    func buildSearchIndex(_ viewModel: SettingsEncryptedSearchViewModel) -> Void {
        let networkStatus: NetworkStatus = self.internetStatusProvider!.currentStatus
        if !networkStatus.isConnected {
            print("Error when building the search index - no internet connection.")
            self.pauseIndexingDueToNetworkConnectivityIssues = true
            return
        }
        if !viewModel.downloadViaMobileData && !(networkStatus == NetworkStatus.ReachableViaWiFi) {
            print("Indexing with mobile data not enabled")
            self.pauseIndexingDueToNetworkConnectivityIssues = true
            return
        }
        
        #if !APP_EXTENSION
            //enable background processing
            self.registerBackgroundTask()
            if #available(iOS 13, *) {
                self.scheduleNewAppRefreshTask()
                self.scheduleIndexBuildingInBackground()
            }
        #endif
        
        //add a notification when app is put in background
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
        
        self.indexBuildingInProgress = true
        self.viewModel = viewModel
        self.updateCurrentUserIfNeeded()    //check that we have the correct user selected
        
        //check if search index db exists - and if not create it
        EncryptedSearchIndexService.shared.createSearchIndexDBIfNotExisting(for: self.user.userInfo.userId)
        
        //set up timer to estimate time for index building every 2 seconds
        self.indexBuildingTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(self.updateRemainingIndexingTime), userInfo: nil, repeats: true)
        
        self.timingsBuildIndex.add(CFAbsoluteTimeGetCurrent())  //add start time
        self.getTotalMessages() {
            print("Total messages: ", self.totalMessages)

            //if search index already build, and there are no new messages we can return here
            //if EncryptedSearchIndexService.shared.checkIfSearchIndexExists(for: self.user.userInfo.userId) {
            //    print("Search index already exists for user!")
                //check if search index needs updating
                if EncryptedSearchIndexService.shared.getNumberOfEntriesInSearchIndex(for: self.user.userInfo.userId) == self.totalMessages {
                    print("Search index already contains all available messages.")
                    self.viewModel?.isEncryptedSearch = true
                    self.viewModel?.currentProgress.value = 100
                    self.viewModel?.estimatedTimeRemaining.value = 0
                    self.indexBuildingInProgress = false
                    if self.backgroundTask != .invalid {
                        //background processing not needed any longer - clean up
                        #if !APP_EXTENSION
                            //enable background processing
                            self.endBackgroundTask()
                        #endif
                    }
                    #if !APP_EXTENSION
                        if #available(iOS 13, *) {
                            //index building finished - we no longer need a background task
                            //self.cancelIndexBuildingInBackground()
                        }
                    #endif
                    return
                }
            //}
                
            //build search index completely new
            DispatchQueue.global(qos: .userInitiated).async {
                //If its an build from scratch, start indexing with time = 0
                self.downloadAndProcessPage(Message.Location.allmail.rawValue, 0) {
                    print("Finished building search index!")
                    self.timingsBuildIndex.add(CFAbsoluteTimeGetCurrent())  //add stop time
                    self.printTiming("Building the Index", for: self.timingsBuildIndex)
                    self.updateMemoryConsumption()
                    
                    self.viewModel?.isEncryptedSearch = true
                    self.viewModel?.currentProgress.value = 100
                    self.viewModel?.estimatedTimeRemaining.value = 0
                    self.indexBuildingInProgress = false
                    
                    if self.backgroundTask != .invalid {
                        //background processing not needed any longer - clean up
                        #if !APP_EXTENSION
                            self.endBackgroundTask()
                        #endif
                    }
                    #if !APP_EXTENSION
                        if #available(iOS 13, *) {
                            //index building finished - we no longer need a background task
                            self.cancelIndexBuildingInBackground()
                        }
                    #endif
                    
                    return
                }
            }
        }
    }
    
    func pauseAndResumeIndexing(completionHandler: @escaping () -> Void = {}) {
        if self.viewModel?.pauseIndexing == true {  //pause indexing
            print("Pause indexing!")
            self.messageIndexingQueue.cancelAllOperations()
            self.indexBuildingInProgress = false
        } else {    //resume indexing
            print("Resume indexing...")
            self.indexBuildingInProgress = true
            self.downloadAndProcessPage(Message.Location.allmail.rawValue, self.lastMessageTimeIndexed) {
                self.viewModel?.isEncryptedSearch = true
                self.viewModel?.currentProgress.value = 100
                self.viewModel?.estimatedTimeRemaining.value = 0
                self.indexBuildingInProgress = false
                completionHandler()
            }
        }
    }
    
    func pauseIndexingDueToNetworkSwitch(){
        let networkStatus: NetworkStatus = self.internetStatusProvider!.currentStatus
        if !networkStatus.isConnected {
            print("Error no internet connection.")
            return
        }

        //if indexing is currently in progress
        //and the slider is off
        //and we are using mobile data
        //then pause indexing
        if self.indexBuildingInProgress && !self.viewModel!.downloadViaMobileData && (networkStatus != NetworkStatus.ReachableViaWiFi) {
            print("Pause indexing when using mobile data")
            self.viewModel?.pauseIndexing = true
            self.pauseAndResumeIndexing()
        }
    }
    
    struct MessageAction {
        var action: NSFetchedResultsChangeType? = nil
        var message: Message? = nil
        var indexPath: IndexPath? = nil
        var newIndexPath: IndexPath? = nil
    }
    
    func updateSearchIndex(_ action: NSFetchedResultsChangeType, _ message: Message?, _ indexPath: IndexPath?, _ newIndexPath: IndexPath?) {
        if self.indexBuildingInProgress {
            let messageAction: MessageAction = MessageAction(action: action, message: message, indexPath: indexPath, newIndexPath: newIndexPath)
            self.eventsWhileIndexing!.append(messageAction)
        } else {
            //print("action type: \(action.rawValue)")
            switch action {
                case .delete:
                    print("Delete message from search index")
                    self.updateMessageMetadataInSearchIndex(message, action)    //delete just triggers a move to the bin folder
                case .insert:
                    print("Insert new message to search index")
                    self.insertSingleMessageToSearchIndex(message)
                case .move:
                    print("Move message in search index")
                    self.updateMessageMetadataInSearchIndex(message, action)    //move just triggers a change in the location of the message
                case .update:
                    print("Update message")
                    //self.updateMessageMetadataInSearchIndex(message, action)
                default:
                    return
            }
        }
    }
    
    func processEventsAfterIndexing(completionHandler: @escaping () -> Void) {
        if self.eventsWhileIndexing!.isEmpty {
            completionHandler()
        } else {
            let messageAction: MessageAction = self.eventsWhileIndexing!.removeFirst()
            self.updateSearchIndex(messageAction.action!, messageAction.message, messageAction.indexPath, messageAction.newIndexPath)
            self.processEventsAfterIndexing {
                print("Events remainding to process: \(self.eventsWhileIndexing!.count)")
            }
        }
    }
    
    func insertSingleMessageToSearchIndex(_ message: Message?) {
        //some simple error handling
        if message == nil {
            print("message nil!")
            return
        }
        
        //just insert a new message if the search index exists for the user - otherwise it needs to be build first
        if EncryptedSearchIndexService.shared.checkIfSearchIndexExists(for: self.user.userInfo.userId) {
            //get message details
            /*self.getMessageDetailsWithRecursion([message!]) { result in
                self.decryptBodyAndExtractData(result) {
                    print("Sucessfully inserted new message \(message!.messageID) in search index")
                    //TODO update some flags?
                }
            }*/
        }
    }
    
    func deleteMessageFromSearchIndex(_ message: Message?) {
        if message == nil {
            print("message nil!")
            return
        }
        
        //just delete a message if the search index exists for the user - otherwise it needs to be build first
        if EncryptedSearchIndexService.shared.checkIfSearchIndexExists(for: self.user.userInfo.userId) {
            EncryptedSearchIndexService.shared.removeEntryFromSearchIndex(user: self.user.userInfo.userId, message: message!.messageID)
        }
    }
    
    func deleteSearchIndex(){
        //just delete the search index if it exists
        if EncryptedSearchIndexService.shared.checkIfSearchIndexExists(for: self.user.userInfo.userId) {
            let result: Bool = EncryptedSearchIndexService.shared.deleteSearchIndex(for: self.user.userInfo.userId)
            self.totalMessages = -1
            self.processedMessages = 0
            self.lastMessageTimeIndexed = 0
            self.prevProcessedMessages = 0
            self.indexingStartTime = 0
            self.indexBuildingInProgress = false
            self.indexBuildingTimer?.invalidate()   //stop timer to estimate remaining time for indexing
            
            //cancel background tasks
            if #available(iOS 13.0, *) {
                self.cancelIndexBuildingInBackground()
                self.cancelBGAppRefreshTask()
            }
            
            //update viewmodel
            self.viewModel?.isEncryptedSearch = false
            self.viewModel?.currentProgress.value = 0
            self.viewModel?.estimatedTimeRemaining.value = 0
            
            //TODO do we want to do anything when deleting fails?
            if result {
                print("Search index for user \(self.user.userInfo.userId) sucessfully deleted!")
            }
        }
    }
    
    func updateMessageMetadataInSearchIndex(_ message: Message?, _ action: NSFetchedResultsChangeType) {
        if message == nil {
            print("message nil!")
            return
        }
        
        switch action {
        case .delete:
            print("DELETE: message location: \(message!.getLabelIDs()), labels: \(message!.labels)")
        case .move:
            print("MOVE: message location: \(message!.getLabelIDs()), labels: \(message!.labels)")
        case .update:
            print("UPDATE: message \(message!), labelid: \(message!.getLabelIDs()), labels: \(message!.labels)")
        default:
            return
        }
    }
    
    private func updateCurrentUserIfNeeded() -> Void {
        let users: UsersManager = sharedServices.get()
        self.user = users.firstUser
        self.messageService = self.user.messageService
    }
    
    private func printTiming(_ title: String, for array: NSMutableArray) -> Void {
        var timeElapsed: Double = 0
        
        for index in stride(from: 0, to: array.count, by: 2) {
            let start: Double = array[index] as! Double
            let stop : Double = array[index+1] as! Double
            timeElapsed += (stop-start)
        }
        
        print("Time for \(title): elapsed: \(timeElapsed)s")
    }
    
    // Checks the total number of messages on the backend
    func getTotalMessages(completionHandler: @escaping () -> Void) -> Void {
        self.messageService?.fetchMessages(byLabel: Message.Location.allmail.rawValue, time: 0, forceClean: false, isUnread: false) { _, response, error in
            if error == nil {
                self.totalMessages = response!["Total"] as! Int
                self.limitPerRequest = response!["Limit"] as! Int
            } else {
                NSLog("Error when parsing total # of messages: %@", error!)
            }
            completionHandler()
        }
    }

    func downloadAndProcessPage(_ mailboxID: String, _ time: Int, completionHandler: @escaping () -> Void) -> Void {
        let group = DispatchGroup()
        group.enter()
        self.messageService?.fetchMessages(byLabel: mailboxID, time: time, forceClean: false, isUnread: false) { _, result, error in
            if error == nil {
                let messagesBatch: NSMutableArray = self.getMessageIDs(result)
                print("Process page...")
                self.processPageOneByOne(forBatch: messagesBatch){
                    print("Page successfull processed!")
                    self.lastMessageTimeIndexed = self.getOldestMessageInMessageBatch(result)
                    group.leave()
                }
            } else {
                print("Error while fetching messages: \(String(describing: error))")
            }
        }
        
        //Wait to call completion handler until all message id's are here
        group.notify(queue: .main) {
            print("Processed messages: ", self.processedMessages)
            //if we processed all messages then return
            if self.processedMessages >= self.totalMessages {
                completionHandler()
            } else {
                if self.indexBuildingInProgress {
                    //call recursively
                    self.downloadAndProcessPage(mailboxID, self.lastMessageTimeIndexed) {
                        completionHandler()
                    }
                } else {
                    //index building stopped from outside - finish up current page and return
                    completionHandler()
                }
            }
        }
    }
    
    func processPageOneByOne(forBatch messageIDs: NSMutableArray, completionHandler: @escaping () -> Void) -> Void {
        //start a new thread to process the page
        DispatchQueue.global(qos: .userInitiated).async {
            for id in messageIDs {
                let op = IndexSingleMessageAsyncOperation(id as! String)
                self.messageIndexingQueue.addOperation(op)
            }
            self.messageIndexingQueue.waitUntilAllOperationsAreFinished()
            completionHandler()
        }
    }
    
    func getMessageIDs(_ response: [String:Any]?) -> NSMutableArray {
        let messages:NSArray = response!["Messages"] as! NSArray
        
        let messageIDs:NSMutableArray = []
        for message in messages {
            if let msg = message as? Dictionary<String, AnyObject> {
                messageIDs.add(msg["ID"]!)
            }
        }

        return messageIDs
    }

    func getOldestMessageInMessageBatch(_ response: [String:Any]?) -> Int {
        var time: Int = Int.max
        let messagesBatch: NSArray = response!["Messages"] as! NSArray

        for msg in messagesBatch {
            let m = msg as? Dictionary<String, AnyObject>
            let mInt = Int(truncating: m!["Time"]! as! NSNumber)
            if mInt < time {
                time = mInt
            }
        }

        return time
    }

    /*func getMessageObjects(_ messageIDs: NSArray, completionHandler: @escaping (NSMutableArray) -> Void) -> Void {
        let group = DispatchGroup()
        let messages: NSMutableArray = []

        for msgID in messageIDs {
            group.enter()

            //Do not block main queue to avoid deadlock
            DispatchQueue.global(qos: .default).async {
                self.getMessage(msgID as! String) {
                    m in
                    messages.add(m!)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            //print("Fetching message objects completed!")
            completionHandler(messages)
        }
    }*/
    
    /*func getMessageDetailsWithRecursion(_ messages: [Message], completionHandler: @escaping (NSMutableArray) -> Void){
        let messagesWithDetails: NSMutableArray = []
        
        print("number of messages left to fetch details: \(messages.count)")
        //stop recursion
        if messages.count == 0 {
            completionHandler(messagesWithDetails)
        } else {
            let m: Message = messages[0]//get the first message
            let group = DispatchGroup()
            
            group.enter()
            self.messageService?.fetchMessageDetailForMessage(m, labelID: Message.Location.allmail.rawValue) { _, _, _, error in
                if error == nil {
                    //let mID: String = m.messageID
                    self.getMessage(m.messageID) { newMessage in
                        //print("message: \(m.messageID), details: \(m.isDetailDownloaded)")
                        messagesWithDetails.add(newMessage!)
                        group.leave()
                    }
                } else {
                    print("Error when fetching message details: \(String(describing: error))")
                }
            }
            
            group.notify(queue: .main) {
                //remove already processed entry from messages array
                var remaindingMessages: [Message] = messages
                if let index = remaindingMessages.firstIndex(of: m) {
                    remaindingMessages.remove(at: index)
                }
                
                //Update UI progress bar
                DispatchQueue.main.async {
                    self.updateIndexBuildingProgress(processedMessages: self.processedMessages + (50 - remaindingMessages.count))
                    self.updateMemoryConsumption()
                }
                
                //call function recursively until entire message array has been processed
                self.getMessageDetailsWithRecursion(remaindingMessages) { mWithDetails in
                    mWithDetails.addObjects(from: messagesWithDetails as! [Any])
                    completionHandler(mWithDetails)
                }
            }
        }
    }*/
    
    func getMessageDetailsForSingleMessage(for message: Message, completionHandler: @escaping (Message?) -> Void) -> Void {
        if message.isDetailDownloaded {
            completionHandler(message)
        } else {
            self.messageService?.fetchMessageDetailForMessage(message, labelID: Message.Location.allmail.rawValue) { _, response, newM, error in
                if error == nil {
                    let messageWithDetails: Message? = self.parseMessageObjectFromResponse(for: (response?["Message"] as? [String:Any])!)
                    completionHandler(messageWithDetails)
                } else {
                    print("Error when fetching message details: \(String(describing: error))")
                }
            }
        }
    }
    
    private func parseMessageObjectFromResponse(for response: [String : Any]) -> Message? {
        var message: Message? = nil
        do {
            message = try GRTJSONSerialization.object(withEntityName: Message.Attributes.entityName, fromJSONDictionary: response, in: (self.messageService?.coreDataService.operationContext)!) as? Message
            message!.messageStatus = 1
            message!.isDetailDownloaded = true
        } catch {
            print("Error when parsing message object: \(error)")
        }
        return message
    }

    func getMessage(_ messageID: String, completionHandler: @escaping (Message?) -> Void) -> Void {
        let fetchedResultsController = self.messageService?.fetchedMessageControllerForID(messageID)
        
        if let fetchedResultsController = fetchedResultsController {
            do {
                try fetchedResultsController.performFetch()
            } catch let ex as NSError {
                PMLog.D(" error: \(ex)")
            }
        }
        
        if let context = fetchedResultsController?.managedObjectContext{
            if let message = Message.messageForMessageID(messageID, inManagedObjectContext: context) {
                completionHandler(message)
            }
        }
    }
    
    /*private func deleteMessageBatch(for messages: NSArray, completionHandler: @escaping () -> Void) -> Void {
        let group = DispatchGroup()
        for m in messages {
            group.enter()
            self.deleteMessage(for: m as! Message) {
                group.leave()
            }
        }
        
        group.notify(queue: .main){
            print("Finished deleting messages.")
            completionHandler()
        }
    }*/
    
    private func deleteMessage(for message: Message, completionHandler: @escaping () -> Void) -> Void {
        let cacheService = self.messageService?.cacheService
        /*cacheService.deleteMessage(messageID: messageID) {
            completionHandler()
        }*/
        //TODO where to take the message label from if there are more labels?
        if cacheService!.delete(message: message, label: Message.Location.allmail.rawValue) {
            completionHandler()
        } else {
            print("Error when deleting message \(message.messageID)")
            completionHandler()
        }
    }
    
    /*private func resetCoreDataContext() {
        //used by self.getMessage
        let context = self.messageService?.coreDataService.mainContext
        context?.reset()
        context?.parent?.reset()
        
        //used by self.messageService.fetchMessageDetailForMessage
        let rootContext = self.messageService?.coreDataService.rootSavingContext
        rootContext?.reset()
        rootContext?.parent?.reset()
        
        //used by self.messageService.fetchMessages
        let operationContext = self.messageService?.coreDataService.operationContext
        operationContext?.reset()
        operationContext?.parent?.reset()
    }*/
    
    /*func decryptBodyAndExtractData(_ messages: NSArray, completionHandler: @escaping () -> Void) {
        var processedMessagesCount: Int = 0
        for m in messages {
            var decryptionFailed: Bool = true

            self.timingsDecryptMessages.add(CFAbsoluteTimeGetCurrent())     // add start time
            var body: String? = ""
            do {
                //print("DECRYPT: message: \((m as! Message).isDetailDownloaded)")
                body = try self.messageService?.decryptBodyIfNeeded(message: m as! Message)
                decryptionFailed = false
            } catch {
                print("Error when decrypting messages: \(error).")
            }
            self.timingsDecryptMessages.add(CFAbsoluteTimeGetCurrent())     // add stop time

            self.timingsExtractData.add(CFAbsoluteTimeGetCurrent())     //add start time
            //let keyWordsPerEmail: String = self.extractKeywordsFromBody(bodyOfEmail: body!)
            let keyWordsPerEmail: String = EmailparserExtractData(body!, true)
            self.timingsExtractData.add(CFAbsoluteTimeGetCurrent())     //add stop time

            self.timingsCreateEncryptedContent.add(CFAbsoluteTimeGetCurrent()) //add start time
            let encryptedContent: EncryptedsearchEncryptedMessageContent? = self.createEncryptedContent(message: m as! Message, cleanedBody: keyWordsPerEmail)
            self.timingsCreateEncryptedContent.add(CFAbsoluteTimeGetCurrent()) //add stop time

            self.timingsWriteToDatabase.add(CFAbsoluteTimeGetCurrent()) //add start time
            self.addMessageKewordsToSearchIndex(m as! Message, encryptedContent, decryptionFailed)
            self.timingsWriteToDatabase.add(CFAbsoluteTimeGetCurrent()) //add stop time

            processedMessagesCount += 1
            print("Processed messages: ", processedMessagesCount)

            //Update UI progress bar
            //DispatchQueue.main.async {
                //self.updateIndexBuildingProgress(processedMessages: self.processedMessages + (50 - remaindingMessages.count))
            //    self.updateMemoryConsumption()
            //}
            
            if processedMessagesCount == messages.count {
                completionHandler()
            }
        }
    }*/
    
    func decryptAndExtractDataSingleMessage(for message: Message, completionHandler: @escaping () -> Void) -> Void {
        var body: String? = ""
        var decryptionFailed: Bool = true
        do {
            body = try self.messageService?.decryptBodyIfNeeded(message: message)
            decryptionFailed = false
        } catch {
            print("Error when decrypting messages: \(error).")
        }
        
        let emailContent: String = EmailparserExtractData(body!, true)
        let encryptedContent: EncryptedsearchEncryptedMessageContent? = self.createEncryptedContent(message: message, cleanedBody: emailContent)
        
        //add message to search index db
        self.addMessageKewordsToSearchIndex(message, encryptedContent, decryptionFailed)
        completionHandler()
    }
    
    func extractKeywordsFromBody(bodyOfEmail body: String, _ removeQuotes: Bool = true) -> String {
        var contentOfEmail: String = ""
        
        do {
            self.timingsParseBody.add(CFAbsoluteTimeGetCurrent()) //add start time
            //parse HTML email as DOM tree
            let doc: Document = try SwiftSoup.parse(body)
            self.timingsParseBody.add(CFAbsoluteTimeGetCurrent()) //add stop time
            
            self.timingsRemoveElements.add(CFAbsoluteTimeGetCurrent()) //add start time
            //remove style elements from DOM tree
            let styleElements: Elements = try doc.getElementsByTag("style")
            for s in styleElements {
                try s.remove()
            }
            
            //remove quoted text, unless the email is forwarded
            if removeQuotes {
                let (noQuoteContent, _) = try locateBlockQuotes(doc)
                self.timingsParseCleanedContent.add(CFAbsoluteTimeGetCurrent()) //add start time
                let newBodyOfEmail: Document = try SwiftSoup.parse(noQuoteContent)
                contentOfEmail = try newBodyOfEmail.text().preg_replace("\\s+", replaceto: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                self.timingsParseCleanedContent.add(CFAbsoluteTimeGetCurrent()) //add start time
            } else {
                contentOfEmail = try doc.text().preg_replace("\\s+", replaceto: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            self.timingsRemoveElements.add(CFAbsoluteTimeGetCurrent()) //add start time
        } catch Exception.Error(_, let message) {
            print(message)
        } catch {
            print("error")
        }

        return contentOfEmail
    }

    //Returns content before and after match in the source
    func split(_ source: String, _ match: String) -> (before: String, after: String) {
        if let range:Range<String.Index> = source.range(of: match) {
            let index: Int = source.distance(from: source.startIndex, to: range.lowerBound)
            let s1_index: String.Index = source.index(source.startIndex, offsetBy: index)
            let s1: String = String(source[..<s1_index])
            
            let s2_index: String.Index = source.index(s1_index, offsetBy: match.count)
            let s2: String = String(source[s2_index...])
            
            return (s1, s2)
        }
        //no match found
        return (source, "")
    }
    
    //TODO refactor
    func searchforContent(_ element: Element?, _ text: String) throws -> Elements {
        let abc: Document = (element?.ownerDocument())!
        let cde: Elements? = try abc.select(":matches(^$text$)")
        return cde!
    }
    
    func locateBlockQuotes(_ inputDocument: Element?) throws -> (String, String) {
        guard inputDocument != nil else { return ("", "") }
        
        let body: Elements? = try inputDocument?.select("body")
        
        var document: Element?
        if body!.first() != nil {
            document = body!.first()
        } else {
            document = inputDocument
        }
        
        var parentHTML: String? = ""
        if try document?.html() != nil {
            parentHTML = try document?.html()
        }
        var parentText: String? = ""
        if try document?.text() != nil {
            parentText = try document?.text()
        }
        
        var result:(String, String)? = nil
        
        func testBlockQuote(_ blockquote: Element) throws -> (String, String)? {
            let blockQuoteText: String = try blockquote.text()
            let (beforeText, afterText): (String, String) = split(parentText!, blockQuoteText)
            
            if (!(beforeText.trim().isEmpty) && (afterText.trim().isEmpty)) {
                let blockQuoteHTML: String = try blockquote.outerHtml()
                let (beforeHTML, _): (String, String) = split(parentHTML!, blockQuoteHTML)
                
                return (beforeHTML, blockQuoteHTML)
            }
            return nil
        }
        
        let blockQuoteSelectors: NSArray = [".protonmail_quote",
                                            ".gmail_quote",
                                            ".yahoo_quoted",
                                            ".gmail_extra",
                                            ".moz-cite-prefix",
                                            // '.WordSection1',
                                            "#isForwardContent",
                                            "#isReplyContent",
                                            "#mailcontent:not(table)",
                                            "#origbody",
                                            "#reply139content",
                                            "#oriMsgHtmlSeperator",
                                            "blockquote[type=\"cite\"]",
                                            "[name=\"quote\"]", // gmx
                                            ".zmail_extra", // zoho
        ]
        let blockQuoteSelector: String = blockQuoteSelectors.componentsJoined(by: ",")
        
        // Standard search with a composed query selector
        let blockQuotes: Elements? = try document?.select(blockQuoteSelector)
        try blockQuotes?.forEach({ blockquote in
            if (result == nil) {
                result = try testBlockQuote(blockquote)
            }
        })
        
        let blockQuoteTextSelectors: NSArray = ["-----Original Message-----"]
        // Second search based on text content with xpath
        if (result == nil) {
            try blockQuoteTextSelectors.forEach { text in
                if (result == nil) {
                    try searchforContent(document, text as! String).forEach { blockquote in
                        if (result == nil) {
                            result = try testBlockQuote(blockquote)
                        }
                    }
                }
            }
        }
        
        if result == nil {
            return (parentHTML!, "")
        }
        
        return result!
    }
    
    struct Sender: Codable {
        var Name: String = ""
        var Address: String = ""
    }
    
    func createEncryptedContent(message: Message, cleanedBody: String) -> EncryptedsearchEncryptedMessageContent? {
        //1. create decryptedMessageContent
        let decoder = JSONDecoder()
        let senderJsonData = Data(message.sender!.utf8)
        let toListJsonData: Data = message.toList.data(using: .utf8)!
        let ccListJsonData: Data = message.ccList.data(using: .utf8)!
        let bccListJsonData: Data = message.bccList.data(using: .utf8)!
        
        var decryptedMessageContent: EncryptedsearchDecryptedMessageContent? = EncryptedsearchDecryptedMessageContent()
        do {
            let senderStruct = try decoder.decode(Sender.self, from: senderJsonData)
            let toListStruct = try decoder.decode([Sender].self, from: toListJsonData)
            let ccListStruct = try decoder.decode([Sender].self, from: ccListJsonData)
            let bccListStruct = try decoder.decode([Sender].self, from: bccListJsonData)
            
            let sender: EncryptedsearchRecipient? = EncryptedsearchRecipient(senderStruct.Name, email: senderStruct.Address)
            let toList: EncryptedsearchRecipientList = EncryptedsearchRecipientList()
            toListStruct.forEach { s in
                let r: EncryptedsearchRecipient? = EncryptedsearchRecipient(s.Name, email: s.Address)
                toList.add(r)
            }
            let ccList: EncryptedsearchRecipientList = EncryptedsearchRecipientList()
            ccListStruct.forEach { s in
                let r: EncryptedsearchRecipient? = EncryptedsearchRecipient(s.Name, email: s.Address)
                ccList.add(r)
            }
            let bccList: EncryptedsearchRecipientList = EncryptedsearchRecipientList()
            bccListStruct.forEach { s in
                let r: EncryptedsearchRecipient? = EncryptedsearchRecipient(s.Name, email: s.Address)
                bccList.add(r)
            }
            
            decryptedMessageContent = EncryptedsearchNewDecryptedMessageContent(message.subject, sender, cleanedBody, toList, ccList, bccList)
        } catch {
            print(error)
        }
        
        //2. encrypt content via gomobile
        let cipher: EncryptedsearchAESGCMCipher = self.getCipher()
        var ESEncryptedMessageContent: EncryptedsearchEncryptedMessageContent? = nil
        
        do {
            ESEncryptedMessageContent = try cipher.encrypt(decryptedMessageContent)
        } catch {
            print(error)
        }
        
        return ESEncryptedMessageContent
    }

    private func getCipher() -> EncryptedsearchAESGCMCipher {
        if self.cipherForSearchIndex == nil {   //TODO we need to regenerate the cipher if there is a switch between users
            let key: Data? = self.retrieveSearchIndexKey()
        
            let cipher: EncryptedsearchAESGCMCipher = EncryptedsearchAESGCMCipher(key!)!
            self.cipherForSearchIndex = cipher
        }
        return self.cipherForSearchIndex!
    }
    
    private func generateSearchIndexKey(_ userID: String) -> Data? {
        let keylen: Int = 32
        var error: NSError?
        let bytes = CryptoRandomToken(keylen, &error)
        self.storeSearchIndexKey(bytes, userID: userID)
        return bytes
    }
    
    private func storeSearchIndexKey(_ key: Data?, userID: String) {
        var encData: Data? = nil
        
        /*if #available(iOS 13.0, *) {
            let key256 = CryptoKit.SymmetricKey(size: .bits256)
            encData = try! AES.GCM.seal(key!, using: key256).combined
        } else {
            // Fallback on earlier versions - do not encrypt key?
            encData = key
        }*/
        encData = key // disable encrypting key for testing purposes
        KeychainWrapper.keychain.set(encData!, forKey: "searchIndexKey_" + userID)
    }
    
    private func retrieveSearchIndexKey() -> Data? {
        let uid: String = self.user.userInfo.userId
        var key: Data? = KeychainWrapper.keychain.data(forKey: "searchIndexKey_" + uid)
        
        //Check if user already has an key
        if key != nil {
            var decryptedKey:Data? = nil
            /*if #available(iOS 13.0, *) {
                let box = try! AES.GCM.SealedBox(combined: key!)
                let key256 = CryptoKit.SymmetricKey(size: .bits256)
                decryptedKey = try! AES.GCM.open(box, using: key256)
            } else {
                // Fallback on earlier versions - do not decrypt key?
                decryptedKey = key
            }*/
            decryptedKey = key  //disable encrypting key for testing purposes
            
            return decryptedKey // if yes, return
        }
 
        // if no, generate a new key and then return
        key = self.generateSearchIndexKey(uid)
        return key
    }
    
    func addMessageKewordsToSearchIndex(_ message: Message, _ encryptedContent: EncryptedsearchEncryptedMessageContent?, _ decryptionFailed: Bool) -> Void {
        var hasBody: Bool = true
        if decryptionFailed {
            hasBody = false //TODO are there any other case where there is no body?
        }
        
        let location: Int = Int(Message.Location.allmail.rawValue)!
        let time: Int = Int((message.time)!.timeIntervalSince1970)
        let order: Int = Int(truncating: message.order)
        
        //let iv: String = String(decoding: (encryptedContent?.iv)!, as: UTF8.self)
        let iv: Data = (encryptedContent?.iv)!.base64EncodedData()
        //let ciphertext: String = String(decoding: (encryptedContent?.ciphertext)!, as: UTF8.self)
        let ciphertext:Data = (encryptedContent?.ciphertext)!.base64EncodedData()
        
        let _: Int64? = EncryptedSearchIndexService.shared.addNewEntryToSearchIndex(for: self.user.userInfo.userId, messageID: message.messageID, time: time, labelIDs: message.labels, isStarred: message.starred, unread: message.unRead, location: location, order: order, hasBody: hasBody, decryptionFailed: decryptionFailed, encryptionIV: iv, encryptedContent: ciphertext, encryptedContentFile: "")
        //print("message inserted at row: ", row!)
    }

    //Encrypted Search
    func search(_ query: String, page: Int, completion: (([Message.ObjectIDContainer]?, NSError?) -> Void)?) {
        let error: NSError? = nil
        
        print("encrypted search on client side!")
        print("Query: ", query)
        print("Page: ", page)
        
        if query == "" {
            completion!(nil, error) //There are no results for an empty search query
        }
        
        //if search query hasn't changed, but just the page, then just display results
        if query == self.lastSearchQuery {
            //TODO is searchedCount the same as searchresults.length?
            if self.searchState!.searchedCount == 0 {//self.searchResults!.length() == 0 {
                completion!(nil, error)
            } else {
                //TODO
                /*self.extractSearchResults(self.searchResults!, page) { messages in
                    completion!(messages, error)
                }*/
            }
        } else {    //If there is a new search query, then trigger new search
            let startSearch: Double = CFAbsoluteTimeGetCurrent()
            let searcher: EncryptedsearchSimpleSearcher = self.getSearcher(query)
            let cipher: EncryptedsearchAESGCMCipher = self.getCipher()
            let cache: EncryptedsearchCache? = self.getCache(cipher: cipher)
            self.searchState = EncryptedsearchSearchState()
            
            let numberOfResultsFoundByCachedSearch: Int = self.doCachedSearch(searcher: searcher, cache: cache!, searchState: &self.searchState, totalMessages: self.totalMessages)
            //print("Results found by cache search: ", numberOfResultsFoundByCachedSearch)
            
            //Check if there are enough results from the cached search
            let searchResultPageSize: Int = 15
            var numberOfResultsFoundByIndexSearch: Int = 0
            if !self.searchState!.isComplete && numberOfResultsFoundByCachedSearch <= searchResultPageSize {
                numberOfResultsFoundByIndexSearch = self.doIndexSearch(searcher: searcher, cipher: cipher, searchState: &self.searchState, resultsFoundInCache: numberOfResultsFoundByCachedSearch)
            }
            
            let endSearch: Double = CFAbsoluteTimeGetCurrent()
            print("Search finished. Time: \(endSearch-startSearch)")
            
            if numberOfResultsFoundByCachedSearch + numberOfResultsFoundByIndexSearch == 0 {
                completion!(nil, error)
            } else {
                self.extractSearchResults(self.cacheSearchResults!, page) { messagesCacheSearch in
                    if numberOfResultsFoundByIndexSearch > 0 {
                        self.extractSearchResults(self.indexSearchResults!, page) { messagesIndexSearch in
                            let combinedMessages: [Message] = messagesCacheSearch! + messagesIndexSearch!
                            let messages: [Message.ObjectIDContainer]? = combinedMessages.map(ObjectBox.init)
                            completion!(messages, error)
                        }
                    } else {
                        //no results from index search - so we only need to return results from cache search
                        let messages: [Message.ObjectIDContainer]? = messagesCacheSearch!.map(ObjectBox.init)
                        completion!(messages, error)
                    }
                }
            }
        }
    }

    func extractSearchResults(_ searchResults: EncryptedsearchResultList, _ page: Int, completionHandler: @escaping ([Message]?) -> Void) -> Void {
        let pageSize: Int = 50
        let numberOfPages: Int = Int(ceil(Double(searchResults.length()/pageSize)))
        if page > numberOfPages {
            completionHandler([])
        } else {
            let startIndex: Int = page * pageSize
            var endIndex: Int = startIndex + (pageSize-1)
            if page == numberOfPages {  //final page
                endIndex = startIndex + (searchResults.length() % pageSize)-1
            }
            
            var messages: [Message] = []
            let group = DispatchGroup()
            //for index in 0...(searchResults.length()-1) {
            for index in startIndex...endIndex {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let res: EncryptedsearchSearchResult? = searchResults.get(index)
                    let m: EncryptedsearchMessage? = res?.message
                    self.getMessage(m!.id_) { mnew in
                        messages.append(mnew!)
                        group.leave()
                    }
                }
            }

            //Wait to call completion handler until all search results are extracted
            group.notify(queue: .main) {
                print("Extracting search results completed!")
                completionHandler(messages)
            }
        }
    }
    
    func getSearcher(_ query: String) -> EncryptedsearchSimpleSearcher {
        let contextSize: CLong = 50 // The max size of the content showed in the preview
        let keywords: EncryptedsearchStringList? = createEncryptedSearchStringList(query)   //split query into individual keywords

        let searcher: EncryptedsearchSimpleSearcher = EncryptedsearchSimpleSearcher(keywords, contextSize: contextSize)!
        return searcher
    }
    
    func getCache(cipher: EncryptedsearchAESGCMCipher) -> EncryptedsearchCache {
        let dbParams: EncryptedsearchDBParams = EncryptedSearchIndexService.shared.getDBParams(self.user.userInfo.userId)
        let cache: EncryptedsearchCache? = EncryptedSearchCacheService.shared.buildCacheForUser(userId: self.user.userinfo.userId, dbParams: dbParams, cipher: cipher)
        return cache!
    }
    
    func createEncryptedSearchStringList(_ query: String) -> EncryptedsearchStringList {
        let result: EncryptedsearchStringList? = EncryptedsearchStringList()
        let searchQueryArray: [String] = query.components(separatedBy: " ")
        searchQueryArray.forEach { q in
            result?.add(q)
        }
        return result!
    }
    
    func doIndexSearch(searcher: EncryptedsearchSimpleSearcher, cipher: EncryptedsearchAESGCMCipher, searchState: inout EncryptedsearchSearchState?, resultsFoundInCache:Int) -> Int {
        let startIndexSearch: Double = CFAbsoluteTimeGetCurrent()
        let index: EncryptedsearchIndex = self.getIndex()
        do {
            try index.openDBConnection()
        } catch {
            print("Error when opening DB connection: \(error)")
        }
        print("Successfully opened connection to searchindex...")
        
        var batchCount: Int = 0
        let searchFetchPageSize: Int = 150
        var resultsFound: Int = resultsFoundInCache
        print("Start index search...")
        while !searchState!.isComplete && resultsFound < searchFetchPageSize {
            let startBatchSearch: Double = CFAbsoluteTimeGetCurrent()
            
            let searchBatchHeapPercent: Double = 0.1 // Percentage of heap that can be used to load messages from the index
            let searchMsgSize: Double = 14000 // An estimation of how many bytes take a search message in memory
            let batchSize: Int = Int((getTotalAvailableMemory() * searchBatchHeapPercent)/searchMsgSize)
            do {
                self.indexSearchResults = EncryptedsearchResultList()
                self.indexSearchResults = try index.searchNewBatch(fromDB: searcher, cipher: cipher, state: searchState, batchSize: batchSize)
                resultsFound += self.indexSearchResults!.length()
            } catch {
                print("Error while searching... ", error)
            }
            let endBatchSearch: Double = CFAbsoluteTimeGetCurrent()
            print("Batch \(batchCount) search. time: \(endBatchSearch-startBatchSearch), with batchsize: \(batchSize)")
            batchCount += 1
        }
        
        do {
            try index.closeDBConnection()
        } catch {
            print("Error while closing database Connection: \(error)")
        }
        
        let endIndexSearch: Double = CFAbsoluteTimeGetCurrent()
        print("Index search finished. Time: \(endIndexSearch-startIndexSearch)")
        
        return resultsFound
    }
    
    func doCachedSearch(searcher: EncryptedsearchSimpleSearcher, cache: EncryptedsearchCache, searchState: inout EncryptedsearchSearchState?, totalMessages: Int) -> Int {
        let searchCacheDecryptedMessages: Bool = true
        if searchCacheDecryptedMessages && !searchState!.cachedSearchDone && !searchState!.isComplete {
            self.cacheSearchResults = EncryptedsearchResultList()
            let startCacheSearch: Double = CFAbsoluteTimeGetCurrent()
            do {
                self.cacheSearchResults = try cache.search(searchState, searcher: searcher)
            } catch {
                print("Error while searching the cache: \(error)")
            }
            let endCacheSearch: Double = CFAbsoluteTimeGetCurrent()
            print("Cache search: \(endCacheSearch-startCacheSearch) seconds")
            return self.cacheSearchResults!.length()
        }
        return 0
    }
    
    func getIndex() -> EncryptedsearchIndex {
        let dbParams: EncryptedsearchDBParams = EncryptedSearchIndexService.shared.getDBParams(self.user.userInfo.userId)
        let index: EncryptedsearchIndex = EncryptedsearchIndex(dbParams)!
        return index
    }
    
    //Code from here: https://stackoverflow.com/a/64738201
    func getTotalAvailableMemory() -> Double {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let _ = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
        }
        let totalMb = Float(ProcessInfo.processInfo.physicalMemory)// / 1048576.0
        return Double(totalMb)
    }
    
    //Code from here: https://stackoverflow.com/a/64738201
    func getCurrentlyAvailableAppMemory() -> Double {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
        }
        let usedMb = Float(taskInfo.phys_footprint)// / 1048576.0
        let totalMb = Float(ProcessInfo.processInfo.physicalMemory)// / 1048576.0
        var availableMemory: Double = 0
        if result != KERN_SUCCESS {
            //print("Memory used: ? of \(totalMb) (in byte)")
            availableMemory = Double(totalMb)
        } else {
            //print("Memory used: \(usedMb) (in byte) of \(totalMb) (in byte)")
            availableMemory = Double(totalMb - usedMb)
        }
        return availableMemory
    }
    
    func updateIndexBuildingProgress(processedMessages: Int){
        //progress bar runs from 0 to 1 - normalize by totalMessages
        let updateStep: Float = Float(processedMessages)/Float(self.totalMessages)
        self.viewModel?.progressViewStatus.value = updateStep
    }
    
    @available(iOSApplicationExtension, unavailable, message: "This method is NS_EXTENSION_UNAVAILABLE")
    func updateUIWithProgressBarStatus(){
        DispatchQueue.main.async {
            switch UIApplication.shared.applicationState {
            case .active:
                self.updateIndexBuildingProgress(processedMessages: self.processedMessages)
                //EncryptedSearchService.shared.updateMemoryConsumption()
            case .background:
                //print("Indexing in background. Processed Messages: \(self.processedMessages)")
                print("Background time remaining = \(self.timeFormatter.string(from: UIApplication.shared.backgroundTimeRemaining)!)")
            case .inactive:
                break
            @unknown default:
                print("Unknown state. What to do?")
            }
        }
    }
    
    func updateMemoryConsumption() {
        let totalMemory: Double = self.getTotalAvailableMemory()
        let freeMemory: Double = self.getCurrentlyAvailableAppMemory()
        let freeDiskSpace: String = EncryptedSearchIndexService.shared.getFreeDiskSpace().asString
        let sizeOfIndex: String = EncryptedSearchIndexService.shared.getSizeOfSearchIndex(for: self.user.userInfo.userId)
        
        print("Total Memory: \(totalMemory/1048576.0) mb, free Memory: \(freeMemory/1048576.0) mb, free disk space: \(freeDiskSpace), size of index: \(sizeOfIndex)")
    }
    
    private func registerForTermalStateChangeNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(responseToHeat(_:)), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }
    
    @objc private func responseToHeat(_ notification: Notification){
        let termalState = ProcessInfo.processInfo.thermalState
        switch termalState {
        case .nominal:
            print("Thermal state nomial. No further action required")
            if self.pauseIndexingDueToOverheating {
                self.viewModel?.pauseIndexing = false
                self.pauseAndResumeIndexing()
                self.pauseIndexingDueToOverheating = false
            }
        case .fair:
            print("Thermal state fair. No further action required")
            if self.pauseIndexingDueToOverheating {
                self.viewModel?.pauseIndexing = false
                self.pauseAndResumeIndexing()
                self.pauseIndexingDueToOverheating = false
            }
        case .serious:
            print("Thermal state serious. Reduce CPU usage.")
        case .critical:
            print("Thermal state critical. Stop indexing!")
            self.pauseIndexingDueToOverheating = true
            self.viewModel?.pauseIndexing = true
            self.pauseAndResumeIndexing()
        @unknown default:
            print("Unknown temperature state. Do something?")
        }
    }
    
    @available(iOSApplicationExtension, unavailable, message: "This method is NS_EXTENSION_UNAVAILABLE")
    private func registerBackgroundTask() {
        self.backgroundTask = UIApplication.shared.beginBackgroundTask(){ [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    @available(iOSApplicationExtension, unavailable, message: "This method is NS_EXTENSION_UNAVAILABLE")
    private func endBackgroundTask() {
        print("Background task ended!")
        //TODO check if indexing has finished, otherwise we can inform the user about it
        //postUserNotification()
        //pause indexing before finishing up
        self.pauseIndexingDueToBackgroundTaskRunningOutOfTime = true
        self.viewModel?.pauseIndexing = true
        self.pauseAndResumeIndexing()
        UIApplication.shared.endBackgroundTask(self.backgroundTask)
        self.backgroundTask = .invalid
    }
    
    @available(iOS 13.0, *)
    @available(iOSApplicationExtension, unavailable, message: "This method is NS_EXTENSION_UNAVAILABLE")
    func registerIndexBuildingInBackground() {
        let registeredSuccessful = BGTaskScheduler.shared.register(forTaskWithIdentifier: "ch.protonmail.protonmail.encryptedsearch_indexbuilding", using: nil) { bgTask in
            self.buildIndexInBackgroundTask(task: bgTask as! BGProcessingTask)
        }
        if !registeredSuccessful {
            print("Error when registering background processing task!")
        }
    }
    
    @available(iOS 13.0, *)
    private func cancelIndexBuildingInBackground() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "ch.protonmail.protonmail.encryptedsearch_indexbuilding")
    }
    
    @available(iOS 13.0, *)
    private func scheduleIndexBuildingInBackground() {
        let request = BGProcessingTaskRequest(identifier: "ch.protonmail.protonmail.encryptedsearch_indexbuilding")
        request.requiresNetworkConnectivity = true  //we need network connectivity when building the index
        //request.requiresExternalPower = true    //we don't neccesarily need it - however we get more execution time if we enable it
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Error when scheduling index building background task: \(error)")
        }
    }
    
    @available(iOS 13.0, *)
    private func buildIndexInBackgroundTask(task: BGProcessingTask) {
        //Provide an expiration handler in case indexing is not finished in time
        task.expirationHandler = {
            //schedule a new background processing task if index building is not finished
            self.scheduleIndexBuildingInBackground()
            
            //stop background execution task
            let stopTime = CFAbsoluteTimeGetCurrent()
            let elapsedTime = self.startBackgroundTask - stopTime
            let text: String = "stop background task. time= " + String(elapsedTime)
            self.sendNotification(text: text)
            
            //pause indexing
            self.pauseIndexingDueToBackgroundTaskRunningOutOfTime = true
            self.viewModel?.pauseIndexing = true
            self.pauseAndResumeIndexing()
            
            //set task to be completed - so that the systems does not terminate the app
            task.setTaskCompleted(success: true)
        }
        
        //start background processing task
        self.backgroundTaskCounter += 1
        self.startBackgroundTask = CFAbsoluteTimeGetCurrent()
        let text = "start background task: " + String(self.backgroundTaskCounter)
        self.sendNotification(text: text)
        print("BGTASK: \(self.backgroundTaskCounter)")
        
        //resume indexing in background
        if self.pauseIndexingDueToBackgroundTaskRunningOutOfTime {
            self.pauseIndexingDueToBackgroundTaskRunningOutOfTime = false
            self.viewModel?.pauseIndexing = false
        }
        self.pauseAndResumeIndexing() {
            //if indexing is finshed during background task - set to complete
            task.setTaskCompleted(success: true)
        }
    }
    
    @available(iOS 13.0, *)
    @available(iOSApplicationExtension, unavailable, message: "This method is NS_EXTENSION_UNAVAILABLE")
    func registerBGAppRefreshTask() {
        let registeredSuccessful = BGTaskScheduler.shared.register(forTaskWithIdentifier: "ch.protonmail.protonmail.encryptedsearch_apprefresh", using: nil) { bgTask in
            self.appRefreshTask(task: bgTask as! BGAppRefreshTask)
        }
        if !registeredSuccessful {
            print("Error when registering background app refresh task!")
        }
    }
    
    @available(iOS 13.0, *)
    func cancelBGAppRefreshTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "ch.protonmail.protonmail.encryptedsearch_apprefresh")
    }
    
    @available(iOS 13.0, *)
    private func appRefreshTask(task: BGAppRefreshTask) {
        //Provide an expiration handler in case indexing is not finished in time
        task.expirationHandler = {
            //schedule a new background app refresh task
            self.scheduleNewAppRefreshTask()
            
            let currentDateTime = Date()
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            formatter.dateStyle = .long
            let text: String = "app refresh finished: " + formatter.string(from: currentDateTime)
            self.sendNotification(text: text)
            print("APP_REFRESH_finished: ", formatter.string(from: currentDateTime))
            
            //set task to be completed - so that the systems does not terminate the app
            task.setTaskCompleted(success: true)
        }
        
        //TODO sent notification, write time to file, print on console
        let currentDateTime = Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .long
        let text: String = "app refresh started: " + formatter.string(from: currentDateTime)
        self.sendNotification(text: text)
        print("APP_REFRESH_started: ", formatter.string(from: currentDateTime))
        
        //write time of app refresh to file
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename:String = "apprefresh_" + String(formatter.string(from: currentDateTime).filter { !" \n\t\r".contains($0) }) + ".txt"
        let url = path.appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Error when writing to file: \(error.localizedDescription)")
        }
        
        //set task to be completed
        task.setTaskCompleted(success: true)
    }

    @available(iOS 13.0, *)
    private func scheduleNewAppRefreshTask(){
        let request = BGAppRefreshTaskRequest(identifier: "ch.protonmail.protonmail.encryptedsearch_apprefresh")
        //request.earliestBeginDate = Date(timeIntervalSinceNow: 30)  //30 seconds
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Unable to sumit app refresh task: \(error.localizedDescription)")
        }
    }
    
    //only works in runtime, does not work at compile time
    // `true` when invoked inside the `Extension process`
    // `false` when invoked inside the `Main process`
    /*func isAppExtension() -> Bool {
        let bundleUrl: URL = Bundle.main.bundleURL
        let bundlePathExtension: String = bundleUrl.pathExtension
        return bundlePathExtension == "appex"
    }*/
    
    func estimateIndexingTime() -> (estimatedMinutes: Int, currentProgress: Int){
        var estimatedMinutes: Int = 0
        var currentProgress: Int = 0
        let currentTime: Double = CFAbsoluteTimeGetCurrent()
        let minute: Double = 60_000.0

        if self.totalMessages != 0 && currentTime != self.indexingStartTime && self.processedMessages != self.prevProcessedMessages {
            let remainingMessages: Double = Double(self.totalMessages - self.processedMessages)
            let timeDifference: Double = currentTime-self.indexingStartTime
            let processedMessageDifference: Double = Double(self.processedMessages-self.prevProcessedMessages)
            estimatedMinutes = Int(ceil(((timeDifference/processedMessageDifference)*remainingMessages)/minute))
            currentProgress = Int(ceil((Double(self.processedMessages)/Double(self.totalMessages))*100))
            self.prevProcessedMessages = self.processedMessages
        }
        return (estimatedMinutes, currentProgress)
    }
    
    @objc func updateRemainingIndexingTime() {
        if self.indexBuildingInProgress && self.processedMessages != self.prevProcessedMessages {
            DispatchQueue.global().async {
                let result = self.estimateIndexingTime()
                
                //update viewModel
                self.viewModel?.currentProgress.value = result.currentProgress
                self.viewModel?.estimatedTimeRemaining.value = result.estimatedMinutes
                print("Remaining indexing time: \(result.estimatedMinutes)")
                print("Current progress: \(result.currentProgress)")
            }
        }
    }
    
    func sendNotification(text: String){
        let content = UNMutableNotificationContent()
        content.title = "Background Processing Task"
        content.subtitle = text
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    @objc func appMovedToBackground(){
        print("App moved to background")
        if self.indexBuildingInProgress {
            self.sendNotification(text: "Index building is in progress... Please tap to resume index building in foreground.")
        }
    }
}
