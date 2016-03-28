//
//  ComposeViewModelImpl.swift
//  ProtonMail
//
//  Created by Yanfeng Zhang on 8/15/15.
//  Copyright (c) 2015 ArcTouch. All rights reserved.
//

import Foundation


public class ComposeViewModelImpl : ComposeViewModel {
    
    init(msg: Message?, action : ComposeMessageAction!) {
        super.init()
        
        if msg == nil || msg?.location == MessageLocation.draft {
            self.message = msg
        }
        else
        {
            if msg?.managedObjectContext == nil {
                self.message = nil
            } else {
                self.message = msg?.copyMessage(action == ComposeMessageAction.Forward)
                self.message?.action = action.rawValue
                if action == ComposeMessageAction.Reply || action == ComposeMessageAction.ReplyAll {
                    if let title = self.message?.title {
                        if !title.hasRe() {
                            self.message?.title = "Re: \(title)"
                        }
                    }
                } else if action == ComposeMessageAction.Forward {
                    if let title = self.message?.title {
                        if !title.hasFwd() {
                            self.message?.title = "Fwd: \(title)"
                        }
                    }
                }
            }
            //PMLog.D(message!);
        }
        
        self.messageAction = action
        self.updateContacts(msg?.location)
    }
    
    override func uploadAtt(att: Attachment!) {
        sharedMessageDataService.uploadAttachment(att)
        self.updateDraft()
    }
    
    override func deleteAtt(att: Attachment!) {
        sharedMessageDataService.deleteAttachment(message?.messageID ?? "", att: att)
        self.updateDraft()
    }
  
    override func getAttachments() -> [Attachment]? {
        return self.message?.attachments.allObjects as? [Attachment]
    }
    
    override func updateAddressID(address_id: String) {
        self.message?.addressID = address_id
        self.updateDraft()
    }
    
    override func getAddresses() -> Array<Address> {
        return sharedUserDataService.userAddresses
    }
    
    override func getDefaultAddress() -> Address? {
        if self.message == nil {
            if let addr = sharedUserDataService.userAddresses.getDefaultAddress() {
                return addr
            }
        }
        return self.message?.defaultAddress
    }
    
    override func hasAttachment() -> Bool {
        return true;
    }
    
    private func updateContacts(oldLocation : MessageLocation?)
    {
        if message != nil {
            switch messageAction!
            {
            case .NewDraft, .Forward:
                break;
            case .OpenDraft:
                let userAddress = sharedUserDataService.userAddresses
                let toContacts = self.toContacts(self.message!.recipientList)
                for cont in toContacts {
                    if !cont.isDuplicatedWithContacts(self.toSelectedContacts) {
                        self.toSelectedContacts.append(cont)
                    }
                }
                
                let ccContacts = self.toContacts(self.message!.ccList)
                for cont in ccContacts {
                    if  !cont.isDuplicatedWithContacts(self.ccSelectedContacts) {
                        self.ccSelectedContacts.append(cont)
                    }
                }
                let bccContacts = self.toContacts(self.message!.bccList)
                for cont in bccContacts {
                    if !cont.isDuplicatedWithContacts(self.bccSelectedContacts) {
                        self.bccSelectedContacts.append(cont)
                    }
                }
            case .Reply:
                if oldLocation == .outbox {
                    let toContacts = self.toContacts(self.message!.recipientList)
                    for cont in toContacts {
                        self.toSelectedContacts.append(cont)
                    }
                } else {
                    let sender = ContactVO(id: "", name: self.message!.senderName, email: self.message!.sender)
                    self.toSelectedContacts.append(sender)
                }
            case .ReplyAll:
                if oldLocation == .outbox {
                    let toContacts = self.toContacts(self.message!.recipientList)
                    for cont in toContacts {
                        self.toSelectedContacts.append(cont)
                    }
                    let senderContacts = self.toContacts(self.message!.ccList)
                    for cont in senderContacts {
                        self.ccSelectedContacts.append(cont)
                    }
                } else {
                    let userAddress = sharedUserDataService.userAddresses
                    let sender = ContactVO(id: "", name: self.message!.senderName, email: self.message!.sender)
                    
                    if  !sender.isDuplicated(userAddress) {
                        self.toSelectedContacts.append(sender)
                    }
                    let toContacts = self.toContacts(self.message!.recipientList)
                    for cont in toContacts {
                        if  !cont.isDuplicated(userAddress) && !cont.isDuplicatedWithContacts(self.toSelectedContacts) {
                            self.toSelectedContacts.append(cont)
                        }
                    }
                    if self.toSelectedContacts.count <= 0 {
                        self.toSelectedContacts.append(sender)
                    }
                    let senderContacts = self.toContacts(self.message!.ccList)
                    for cont in senderContacts {
                        if  !cont.isDuplicated(userAddress) && !cont.isDuplicatedWithContacts(self.toSelectedContacts) {
                            self.ccSelectedContacts.append(cont)
                        }
                    }
                }
            default:
                break;
            }
        }
    }
    
    public override func sendMessage() {
        
        self.updateDraft()
        sharedMessageDataService.send(self.message?.messageID)  { task, response, error in
            
        }
    }
    
    override func collectDraft(title: String, body: String, expir:NSTimeInterval, pwd:String, pwdHit:String) {
        PMLog.D(self.toSelectedContacts)
        PMLog.D(self.ccSelectedContacts)
        PMLog.D(self.bccSelectedContacts)
        
        if message == nil {
            self.message = MessageHelper.messageWithLocation(MessageLocation.draft,
                recipientList: toJsonString(self.toSelectedContacts),
                bccList: toJsonString(self.bccSelectedContacts),
                ccList: toJsonString(self.ccSelectedContacts),
                title: title,
                encryptionPassword: "",
                passwordHint: "",
                expirationTimeInterval: expir,
                body: body,
                attachments: nil,
                inManagedObjectContext: sharedCoreDataService.mainManagedObjectContext!)
        } else {
            self.message?.recipientList = toJsonString(self.toSelectedContacts)
            self.message?.ccList = toJsonString(self.ccSelectedContacts)
            self.message?.bccList = toJsonString(self.bccSelectedContacts)
            self.message?.title = title
            self.message?.time = NSDate()
            self.message?.password = pwd
            self.message?.passwordHint = pwdHit
            self.message?.expirationOffset = Int32(expir)
            MessageHelper.updateMessage(self.message!, expirationTimeInterval: expir, body: body, attachments: nil)
            if let error = message!.managedObjectContext?.saveUpstreamIfNeeded() {
                NSLog("\(__FUNCTION__) error: \(error)")
            }
        }
        
        PMLog.D(message!);
        
    }
    
    public override func updateDraft() {
        sharedMessageDataService.saveDraft(self.message);
    }
    
    override public func deleteDraft() {
        if let tmpLocation = self.message?.location {
            lastUpdatedStore.ReadMailboxMessage(tmpLocation)
        }
        sharedMessageDataService.deleteDraft(self.message);
    }
    
    public override func markAsRead() {
        if message != nil {
            message?.isRead = true;
            if let error = message!.managedObjectContext?.saveUpstreamIfNeeded() {
                NSLog("\(__FUNCTION__) error: \(error)")
            }
        }
    }
    
    override public func getHtmlBody() -> String {
        let signature = !sharedUserDataService.signature.isEmpty ? "\n\n\(sharedUserDataService.signature)" : ""
        
        let mobileSignature = sharedUserDataService.showMobileSignature ? "<br><br> \(sharedUserDataService.mobileSignature)" : ""
        
        let defaultSignature = sharedUserDataService.showDefaultSignature ? signature : ""
        
        let htmlString = "<div><br></div><div><br></div>\(defaultSignature) \(mobileSignature)<div><br></div>";
        switch messageAction!
        {
        case .OpenDraft:
            let body = message!.decryptBodyIfNeeded(nil) ?? ""
            return body
        case .Reply, .ReplyAll:
            // composeView.subject.text = "Re: " + viewModel.getSubject()
            let replyMessage = NSLocalizedString("Reply message")
            var body = message!.decryptBodyIfNeeded(nil) ?? ""
            
            body = body.stringByStrippingStyleHTML()
            body = body.stringByStrippingBodyStyle()
            body = body.stringByPurifyHTML()
            
            let time = message!.orginalTime?.formattedWith("'On' EE, MMM d, yyyy 'at' h:mm a") ?? ""
            let replyHeader = time + ", " + message!.senderName + " <'\(message!.sender)'>"
            let sp = "<div>\(replyHeader) wrote:</div><blockquote class=\"protonmail_quote\" type=\"cite\"> "
            return "\(htmlString) \(sp) \(body)</blockquote>"
        case .Forward:
            //composeView.subject.text = "Fwd: \(message.title)"
            let time = message!.orginalTime?.formattedWith("'On' EE, MMM d, yyyy 'at' h:mm a") ?? ""
            var forwardHeader = "<br><br><br>---------- Forwarded message ----------<br>From: \(message!.senderName)<br>Date: \(time)<br>Subject: \(message!.title)<br>"
            if message!.recipientList != "" {
                forwardHeader += "To: \(message!.recipientList.formatJsonContact())<br>"
            }
            
            if message!.ccList != "" {
                forwardHeader += "CC: \(message!.ccList.formatJsonContact())<br>"
            }
            forwardHeader += "<br><br><br>"
            var body = message!.decryptBodyIfNeeded(nil) ?? ""
            
            body = body.stringByStrippingStyleHTML()
            body = body.stringByStrippingBodyStyle()
            body = body.stringByPurifyHTML()
            
            let sp = "<div>\(forwardHeader) wrote:</div><blockquote class=\"protonmail_quote\" type=\"cite\"> "
            return "<br><br><br>\(defaultSignature) \(mobileSignature) \(sp) \(body)"
        case .NewDraft:
            return htmlString
        default:
            return htmlString
        }

    }
    
}

extension ComposeViewModelImpl {
    func toJsonString(contacts : [ContactVO]) -> String {
        
        var out : [[String : String]] = [[String : String]]();
        for contact in contacts {
            let to : [String : String] = ["Name" : contact.name ?? "", "Address" : contact.email ?? ""]
            out.append(to)
        }
        
        let bytes : NSData = NSJSONSerialization.dataWithJSONObject(out, options: NSJSONWritingOptions.allZeros, error: nil)!
        let strJson : String = NSString(data: bytes, encoding: NSUTF8StringEncoding)! as String
        
        return strJson
    }
    func toContacts(json : String) -> [ContactVO] {
        
        var out : [ContactVO] = [ContactVO]();
        let recipients : [[String : String]] = json.parseJson()!
        for dict:[String : String] in recipients {
            out.append(ContactVO(id: "", name: dict["Name"], email: dict["Address"]))
        }
        return out
    }
}



