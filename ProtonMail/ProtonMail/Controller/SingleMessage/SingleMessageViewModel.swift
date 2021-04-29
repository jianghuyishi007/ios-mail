//
//  SingleMessageViewModel.swift
//  ProtonMail
//
//
//  Copyright (c) 2021 Proton Technologies AG
//
//  This file is part of ProtonMail.
//
//  ProtonMail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonMail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonMail.  If not, see <https://www.gnu.org/licenses/>.

import PMUIFoundations

class SingleMessageViewModel {

    var message: Message {
        didSet {
            propagateMessageData()
        }
    }
    let shouldAutoLoadRemoteImage: Bool

    var isExpanded = false {
        didSet { isExpanded ? createExpandedHeaderViewModel() : createNonExpandedHeaderViewModel() }
    }

    var nonExapndedHeaderViewModel: NonExpandedHeaderViewModel? {
        didSet {
            guard let viewModel = nonExapndedHeaderViewModel else { return }
            embedNonExpandedHeader?(viewModel)
            expandedHeaderViewModel = nil
        }
    }

    var expandedHeaderViewModel: ExpandedHeaderViewModel? {
        didSet {
            guard let viewModel = expandedHeaderViewModel else { return }
            embedExpandedHeader?(viewModel)
            nonExapndedHeaderViewModel = nil
        }
    }

    let messageBodyViewModel: NewMessageBodyViewModel
    let attachmentViewModel: AttachmentViewModel
    let bannerViewModel: BannerViewModel
    private(set) lazy var userActivity: NSUserActivity = .messageDetailsActivity(messageId: message.messageID)

    private let messageService: MessageDataService
    let user: UserManager
    let labelId: String
    private let messageObserver: MessageObserver
    let linkOpener: LinkOpener

    var refreshView: (() -> Void)?
    var updateErrorBanner: ((NSError?) -> Void)?
    var embedExpandedHeader: ((ExpandedHeaderViewModel) -> Void)?
    var embedNonExpandedHeader: ((NonExpandedHeaderViewModel) -> Void)?

    init(labelId: String, message: Message, user: UserManager, linkOpenerCache: LinkOpenerCacheProtocol) {
        self.labelId = labelId
        self.message = message
        self.messageService = user.messageService
        self.user = user
        self.linkOpener = linkOpenerCache.browser
        self.shouldAutoLoadRemoteImage = user.autoLoadRemoteImages
        self.messageBodyViewModel = NewMessageBodyViewModel(
            message: message,
            messageService: user.messageService,
            userManager: user,
            shouldAutoLoadRemoteImages: user.userinfo.showImages.contains(.remote),
            shouldAutoLoadEmbeddedImages: user.userinfo.showImages.contains(.embedded)
        )
        self.nonExapndedHeaderViewModel = NonExpandedHeaderViewModel(
            labelId: labelId,
            message: message,
            user: user
        )
        self.bannerViewModel = BannerViewModel(
            shouldAutoLoadRemoteContent: user.userinfo.showImages.contains(.remote),
            expirationTime: message.expirationTime,
            shouldAutoLoadEmbeddedImage: user.userinfo.showImages.contains(.embedded)
        )
        let attachments: [AttachmentInfo] = message.attachments.compactMap { $0 as? Attachment }
            .map(AttachmentNormal.init) + (message.tempAtts ?? [])

        self.attachmentViewModel = AttachmentViewModel(attachments: attachments)
        self.messageObserver = MessageObserver(messageId: message.messageID, messageService: messageService)
    }

    var messageTitle: NSAttributedString {
        message.title.apply(style: .titleAttributes)
    }

    func viewDidLoad() {
        messageObserver.observe { [weak self] in
            self?.message = $0
        }
        downloadDetails()
    }

    func propagateMessageData() {
        refreshView?()
        // messageBodyViewModel.messageHasChanged(message: message)
        nonExapndedHeaderViewModel?.messageHasChanged(message: message)
        expandedHeaderViewModel?.messageHasChanged(message: message)
        attachmentViewModel.messageHasChanged(message: message)
    }

    func starTapped() {
        messageService.label(messages: [message], label: Message.Location.starred.rawValue, apply: !message.starred)
    }

    func markReadIfNeeded() {
        guard message.unRead else { return }
        messageService.mark(messages: [message], labelID: labelId, unRead: false)
    }

    func downloadDetails() {
        let shouldLoadBody = message.body.isEmpty
        messageService.fetchMessageDetailForMessage(message, labelID: labelId) { [weak self] _, _, _, error in
            guard let self = self else { return }
            self.updateErrorBanner?(error)
            if error != nil && !self.message.isDetailDownloaded {
                self.messageBodyViewModel.messageHasChanged(message: self.message, isError: true)
            } else if shouldLoadBody {
                self.messageBodyViewModel.messageHasChanged(message: self.message)
            }
        }
    }

    func createExpandedHeaderViewModel() {
        expandedHeaderViewModel = ExpandedHeaderViewModel(labelId: labelId, message: message, user: user)
    }

    func createNonExpandedHeaderViewModel() {
        nonExapndedHeaderViewModel = NonExpandedHeaderViewModel(labelId: labelId, message: message, user: user)
    }

    func getActionTypes() -> [MailboxViewModel.ActionTypes] {
        var actions: [MailboxViewModel.ActionTypes] = []
        let isHavingMoreThanOneContact = (message.toList.toContacts() + message.ccList.toContacts()).count > 1
        actions.append(isHavingMoreThanOneContact ? .replyAll : .reply)
        actions.append(.readUnread)
        let deleteLocation = [
            Message.Location.draft.rawValue,
            Message.Location.spam.rawValue,
            Message.Location.trash.rawValue
        ]
        actions.append(deleteLocation.contains(labelId) ? .delete : .trash)
        actions.append(.more)
        return actions
    }

    func handleActionBarAction(_ action: MailboxViewModel.ActionTypes) {
        switch action {
        case .delete:
            messageService.delete(messages: [message], label: labelId)
        case .readUnread:
            messageService.mark(messages: [message], labelID: labelId, unRead: !message.unRead)
        case .trash:
            messageService.move(messages: [message],
                                from: [labelId],
                                to: Message.Location.trash.rawValue,
                                queue: true)
        default:
            return
        }
    }

    func handleActionSheetAction(_ action: MessageViewActionSheetAction,
                                 completion: @escaping () -> Void) {
        switch action {
        case .markUnread:
            messageService.mark(messages: [message], labelID: labelId, unRead: true)
        case .trash:
            messageService.move(messages: [message],
                                from: [labelId],
                                to: Message.Location.trash.rawValue,
                                queue: true)
        case .archive:
            messageService.move(messages: [message],
                                from: [labelId],
                                to: Message.Location.archive.rawValue,
                                queue: true)
        case .spam:
            messageService.move(messages: [message],
                                from: [labelId],
                                to: Message.Location.spam.rawValue,
                                queue: true)
        case .delete:
            messageService.delete(messages: [message], label: labelId)
        case .reportPhishing:
            BugDataService(api: self.user.apiService).reportPhishing(messageID: message.messageID,
                                                                     messageBody: messageBodyViewModel.body
                                                                        ?? LocalString._error_no_object) { _ in
                self.messageService.move(messages: [self.message],
                                         from: [self.labelId],
                                         to: Message.Location.spam.rawValue,
                                         queue: true)
                completion()
            }
            return
        case .inbox, .spamMoveToInbox:
            messageService.move(messages: [message],
                                from: [labelId],
                                to: Message.Location.inbox.rawValue,
                                queue: true)
        default:
            break
        }
        completion()
    }

    func getMessageHeaderUrl() -> URL? {
        let message = messageBodyViewModel.message
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let time = formatter.string(from: message.time ?? Date())
        let title = message.title.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let filename = "headers-" + time + "-" + title.joined(separator: "-")
        guard let header = message.header else {
            assert(false, "No header in message")
            return nil
        }
        return try? self.writeToTemporaryUrl(header, filename: filename)
    }

    func getMessageBodyUrl() -> URL? {
        let message = messageBodyViewModel.message
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let time = formatter.string(from: message.time ?? Date())
        let title = message.title.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let filename = "body-" + time + "-" + title.joined(separator: "-")
        guard let body = try? messageService.decryptBodyIfNeeded(message: message) else {
            return nil
        }
        return try? self.writeToTemporaryUrl(body, filename: filename)
    }

    private func writeToTemporaryUrl(_ content: String, filename: String) throws -> URL {
        let tempFileUri = FileManager.default.temporaryDirectoryUrl
            .appendingPathComponent(filename, isDirectory: false).appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: tempFileUri)
        try content.write(to: tempFileUri, atomically: true, encoding: .utf8)
        return tempFileUri
    }
}

private extension MessageDataService {

    func fetchMessage(messageId: String) -> Message? {
        fetchMessages(withIDs: .init(array: [messageId]), in: CoreDataService.shared.mainContext).first
    }

}

private extension Dictionary where Key == NSAttributedString.Key, Value == Any {

    static var titleAttributes: [Key: Value] {
        let font = UIFont.systemFont(ofSize: 20, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.17
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.alignment = .center

        return [
            .kern: 0.35,
            .font: font,
            .foregroundColor: UIColorManager.TextNorm,
            .paragraphStyle: paragraphStyle
        ]
    }

}
