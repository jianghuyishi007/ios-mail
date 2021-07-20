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

public class EncryptedSearchService {
    //instance of Singleton
    static let shared = EncryptedSearchService()
    
    //set initializer to private - Singleton
    private init(){
        let users: UsersManager = sharedServices.get()
        user = users.firstUser!
        //TODO is the firstUser correct? Should we select user by ID?
        
        messageService = user.messageService
        
        searchIndex = EncryptedSearchIndexService.shared.createSearchIndex()!
        EncryptedSearchIndexService.shared.createSearchIndexTable()
        
        //self.conversationStateService = user.conversationStateService
    }
    
    internal var user: UserManager!
    internal var messageService: MessageDataService
    var totalMessages: Int = 0
    
    internal var searchIndex: Connection
    //private let conversationStateService: ConversationStateService
    
    /*var viewMode: ViewMode {
        //TODO check what I actually need from here
        let singleMessageOnlyLabels: [Message.Location] = [.draft, .sent]
        if let location = Message.Location.init(rawValue: labelID),
           singleMessageOnlyLabels.contains(location),
           self.conversationStateService.viewMode == .conversation {
            return .singleMessage
        }
        return self.conversationStateService.viewMode
    }*/
}

extension EncryptedSearchService {
    //function to build the search index needed for encrypted search
    func buildSearchIndex() -> Bool {
        //Run code in the background
        DispatchQueue.global(qos: .userInitiated).async {
            let mailBoxID: String = "5"
            var messageIDs: NSMutableArray = []
            var messages: NSMutableArray = []   //Array containing all messages of a user
            var completeMessages: NSMutableArray = []

            //1. download all messages locally
            NSLog("Downloading messages locally...")
            self.fetchMessages(mailBoxID){ids in
                messageIDs = ids
                print("# of message ids: ", messageIDs.count)

                NSLog("Downloading message objects...")
                //2. download message objects
                self.getMessageObjects(messageIDs){
                    msgs in
                    messages = msgs
                    print("# of message objects: ", messages.count)
                    
                    /*for m in messages {
                        if (m as! Message).isDetailDownloaded {
                            print("Message details already downloaded for message: ", (m as! Message).messageID)
                            //print("Body: ", (m as! Message).body)
                        } else {
                            print("Message details NOT already downloaded for message: ", (m as! Message).messageID)
                        }
                    }*/
                    
                    NSLog("Downloading message details...") //if needed
                    //3. downloads message details
                    //self.getMessageDetails(messages, messagesToProcess: messages.count){
                    self.getMessageDetailsIfNotAvailable(messages, messagesToProcess: messages.count){
                        compMsgs in
                        completeMessages = compMsgs
                        
                        print("complete messages: ", completeMessages.count)
                        
                        NSLog("Decrypting messages...")
                        //4. decrypt messages (using the user's PGP key)
                        self.decryptBodyAndExtractData(completeMessages)
                    }
                }
            }

            /*

            print("Finished!")*/
            //TODOs:
            //3. extract keywords from message
            //4. encrypt search index (using local symmetric key)
            //5. store the keywords index in a local DB(sqlite3)
        }
        DispatchQueue.main.async {
            // TODO task has completed
            // Update UI -> progress bar?
        }
        return false
    }
    
    func fetchMessages(_ mailBoxID: String, completionHandler: @escaping (NSMutableArray) -> Void) -> Void {
        self.messageService.fetchMessages(byLabel: mailBoxID, time: 0, forceClean: false, isUnread: false) { _, result, error in
            if error == nil {
                //NSLog("Messages: %@", result!)
                //print("response: %@", result!)
                var messageIDs:NSMutableArray = []
                messageIDs = self.getMessageIDs(result)
                completionHandler(messageIDs)
            } else {
                NSLog(error as! String)
            }
            //NSLog("All messages downloaded")
        }
    }
    
    func getMessageIDs(_ response: [String:Any]?) -> NSMutableArray {
        self.totalMessages = response!["Total"] as! Int
        print("Total messages found: ", self.totalMessages)
        let messages:NSArray = response!["Messages"] as! NSArray
        
        let messageIDs:NSMutableArray = []
        for message in messages{
            //messageIDs.adding(message["ID"])
            if let msg = message as? Dictionary<String, AnyObject> {
                //print(msg["ID"]!)
                messageIDs.add(msg["ID"]!)
            }
            
            //print(message)
            //break
        }
        //print("Message IDs:")
        //print(messageIDs)
        
        return messageIDs
    }
    
    func getMessageObjects(_ messageIDs: NSArray, completionHandler: @escaping (NSMutableArray) -> Void) -> Void {
        //print("Iterate through messages:")
        let messages: NSMutableArray = []
        var processedMessages: Int = 0
        for msgID in messageIDs {
            self.getMessage(msgID as! String) {
                m in
                messages.add(m!)
                processedMessages += 1
                print("message: ", processedMessages)
                
                if processedMessages == messageIDs.count {
                    completionHandler(messages)
                }
            }
            
            //print("Message contains body?: ", message!.isDetailDownloaded)
            //print("Message body: ", message!.body)
            //break
        }
        
        //do I have to call it here as well?
        if processedMessages == messageIDs.count {
            completionHandler(messages)
        }
    }
    
    /*func getMessageDetails(_ messages: NSArray, messagesToProcess: Int, completionHandler: @escaping (NSMutableArray) -> Void) -> Void {
        let msg: NSMutableArray = []
        var processedMessageCount: Int = 0
        for m in messages {
            self.messageService.ForcefetchDetailForMessage(m as! Message){_,_,newMessage,error in
                //print("message")
                //print(newMessage!)
                //print("error")
                //print(error!)
                if error == nil {
                    print("Processing message: ", processedMessageCount)
                    msg.add(newMessage!)
                    processedMessageCount += 1
                }
                else {
                    NSLog("Error when fetching message details: %@", error!)
                }
                
                //check if last message
                //if index == messages.count-1 {
                if processedMessageCount == messagesToProcess {
                    completionHandler(msg)
                }
            }
        }
    }*/
    
    func getMessageDetailsIfNotAvailable(_ messages: NSArray, messagesToProcess: Int, completionHandler: @escaping (NSMutableArray) -> Void) -> Void {
        let msg: NSMutableArray = []
        var processedMessageCount: Int = 0
        for m in messages {
            if (m as! Message).isDetailDownloaded {
                msg.add(m)
                processedMessageCount += 1
            } else {
                self.messageService.fetchMessageDetailForMessage(m as! Message, labelID: "5") { _, response, _, error in
                    //print("Response: ", response!)
                    print("Fetching message details for message: ", (m as! Message).messageID)
                    
                    if error == nil {
                        //let abc:NSDictionary = response!["Message"] as! NSDictionary
                        //print("abc:", abc)
                        //TODO extract message id
                        let mID: String = (m as! Message).messageID
                        //call get message (from cache) -> now with details
                        //let newM:Message? = self.getMessage(mID)
                        self.getMessage(mID) { newM in
                            msg.add(newM!)
                            print("Message: (", mID, ") successfull added!")
                            processedMessageCount += 1  //increase message count if successfully added
                            
                            //if we are already finished with for loop, we have to check here to be able to return
                            if processedMessageCount == messagesToProcess {
                                completionHandler(msg)
                            }
                        }
                    }
                    else {
                        NSLog("Error: ", error!)
                    }
                    //print("Finish fetching message detail")
                }
            }
            print("Messages processed: ", processedMessageCount)
        }
        
        //check if all messages have been processed
        //do I have to check here as well?
        if processedMessageCount == messagesToProcess {
            completionHandler(msg)
        }
    }
    
    private func getMessage(_ messageID: String, completionHandler: @escaping (Message?) -> Void) -> Void {
        let fetchedResultsController = self.messageService.fetchedMessageControllerForID(messageID)
        
        if let fetchedResultsController = fetchedResultsController {
            do {
                try fetchedResultsController.performFetch()
            } catch let ex as NSError {
                PMLog.D(" error: \(ex)")
            }
        }
        
        if let context = fetchedResultsController?.managedObjectContext{
            if let message = Message.messageForMessageID(messageID, inManagedObjectContext: context) {
                //return message
                completionHandler(message)
            }
        }
        //return nil
        //completionHandler(nil)
    }
    
    func decryptBodyAndExtractData(_ messages: NSArray) {
        //2. decrypt messages (using the user's PGP key)
        //MessageDataService+Decrypt.swift:38
        //func decryptBodyIfNeeded(message: Message) throws -> String?
        for m in messages {
            //print("Message:")
            //print((m as! Message).body)
            
            var body: String? = ""
            do {
                body = try self.messageService.decryptBodyIfNeeded(message: m as! Message)
                print("Body of email (plaintext): ", body!)
            } catch {
                print("Unexpected error: \(error).")
            }
            
            var keyWordsPerEmail: String = ""
            keyWordsPerEmail = self.extractKeywordsFromBody(bodyOfEmail: body!)
            
            self.addMessageKewordsToSearchIndex(keyWordsPerEmail, m as! Message)
            //for debugging only
            break
        }
        
        //return keywords
    }
    
    func extractKeywordsFromBody(bodyOfEmail body: String, _ removeQuotes: Bool = true) -> String {
        var contentOfEmail: String = ""
        
        do {
            //let html = "<html><head><title>First parse</title></head>"
            //    + "<body><p>Parsed HTML into a doc.</p></body></html>"
            //parse HTML email as DOM tree
            let doc: Document = try SwiftSoup.parse(body)
            
            //remove style elements from DOM tree
            let styleElements: Elements = try doc.getElementsByTag("style")
            for s in styleElements {
                try s.remove()
            }
            
            //remove quoted text, unless the email is forwarded
            var content: String = ""
            if removeQuotes {
                let (noQuoteContent, _) = try locateBlockQuotes(doc)
                content = noQuoteContent
            } else {
                content = try doc.html()
            }
            
            let newBodyOfEmail: Document = try SwiftSoup.parse(content)
            contentOfEmail = try newBodyOfEmail.text().trim()
            //TODO replace multiple whitespaces with a single whitespace
            //i.e. in Kotlin -> .replace("\\s+", " ")
        } catch Exception.Error(_, let message) {
            print(message)
        } catch {
            print("error")
        }
        print("content of email cleaned: ", contentOfEmail)
        
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
    
    func addMessageKewordsToSearchIndex(_ keywordsPerEmail: String,_ message: Message) -> Void {
        //TODO hasBody, decryption failed, time, labelID, location, order
        let row: Int64? = EncryptedSearchIndexService.shared.addNewEntryToSearchIndex(messageID: message.messageID, time: 0, labelIDs: message.labels, isStarred: message.starred, unread: message.unRead, location: 0, order: 0, refreshBit: false, hasBody: true, decryptionFailed: false, encryptionIV: "", encryptedContent: "", encryptedContentFile: "")
        print("message inserted at row: ", row!)
    }

    //Encrypted Search
    func search() {
        //TODO implement
    }
}
