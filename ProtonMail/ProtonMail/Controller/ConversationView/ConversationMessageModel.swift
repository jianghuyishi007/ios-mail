struct ConversationMessageModel {
    let messageLocation: Message.Location?
    let isCustomFolderLocation: Bool
    let initial: NSAttributedString?
    let isRead: Bool
    let sender: String
    let time: String
    let isForwarded: Bool
    let isReplied: Bool
    let isRepliedToAll: Bool
    let isStarred: Bool
    let hasAttachment: Bool
    let tags: [UIColor]
    let expirationTag: TagViewModel?
}
