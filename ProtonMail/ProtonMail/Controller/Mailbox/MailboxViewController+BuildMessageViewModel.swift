//
//  MailboxViewController+BuildMessageViewModel.swift
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


import UIKit
import PMUIFoundations

extension MailboxViewController {

    func buildNewMailboxMessageViewModel(message: Message) -> NewMailboxMessageViewModel {
        let labelId = viewModel.labelID
        let isSelected = self.viewModel.selectionContains(id: message.messageID)
        let initial = message.initial(replacingEmails: replacingEmails)
        let sender = message.sender(replacingEmails: replacingEmails)

        return NewMailboxMessageViewModel(
            location: Message.Location(rawValue: viewModel.labelID),
            isLabelLocation: message.isLabelLocation(labelId: labelId),
            messageLocation: message.messageLocation,
            isCustomFolderLocation: message.isCustomFolder,
            style: listEditing ? .selection(isSelected: isSelected) : .normal,
            initial: initial.apply(style: FontManager.body3RegularNorm),
            isRead: !message.unRead,
            sender: sender,
            time: message.messageTime,
            isForwarded: message.forwarded,
            isReply: message.replied,
            isReplyAll: message.repliedAll,
            topic: message.subject,
            isStarred: message.starred,
            hasAttachment: message.numAttachments.intValue > 0,
            tags: message.createTags
        )
    }

}
