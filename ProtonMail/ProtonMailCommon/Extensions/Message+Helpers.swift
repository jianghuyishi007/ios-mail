//
//  Message+Helpers.swift
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
//  along with ProtonMail. If not, see <https://www.gnu.org/licenses/>.

import PMUIFoundations

extension Message {

    var spam: SpamType? {
        if flag.contains(.dmarcFailed) {
            return .dmarcFailed
        }
        let isSpam = getLableIDs().contains(Message.Location.spam.rawValue)
        return flag.contains(.autoPhishing) && (!flag.contains(.hamManual) || isSpam) ? .autoPhishing : nil
    }

    var getUnsubscribeMethods: UnsubscribeMethods? {
        guard let unsubscribeMethods = unsubscribeMethods,
              let data = unsubscribeMethods.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UnsubscribeMethods?.self, from: data)
    }

    func recipients(userContacts: [ContactVO]) -> [String] {
        let allMessageRecipients = toList.toContacts() + ccList.toContacts() + bccList.toContacts()

        return allEmails.map { email in
            if let emailFromContacts = userContacts.first(where: { $0.email == email }),
               !emailFromContacts.name.isEmpty {
                return emailFromContacts.name
            }
            if let messageRecipient = allMessageRecipients.first(where: { $0.email == email }),
               !messageRecipient.name.isEmpty {
                return messageRecipient.name
            }
            return email
        }
    }

    var tagViewModels: [TagViewModel] {
        orderedLabels.map { label in
            TagViewModel(
                title: label.name.apply(style: FontManager.OverlineSemiBoldTextInverted),
                icon: nil,
                color: UIColor(hexString: label.color, alpha: 1.0)
            )
        }
    }

    func senderContact(userContacts: [ContactVO]) -> ContactVO? {
        guard let sender = sender?.toContact() else { return nil }
        return userContacts.first(where: { $0.email == sender.email }) ?? sender
    }

    var messageTime: String {
        guard let time = time, let displayString = NSDate.stringForDisplay(from: time) else { return .empty }
        return displayString
    }

    var isCustomFolder: Bool {
        customFolder != nil
    }

    var customFolder: Label? {
        let predicate = NSPredicate(format: "labelID MATCHES %@", "(?!^\\d+$)^.+$")
        let allLabels = labels.filtered(using: predicate)
        return allLabels.compactMap { $0 as? Label }.first(where: { $0.type == 3 })
    }

    var messageLocation: Message.Location? {
        labels
            .compactMap { $0 as? Label }
            .map(\.labelID)
            .compactMap(Message.Location.init)
            .first(where: { $0 != .allmail && $0 != .starred })
    }

    var createTags: [TagViewModel] {
        [createTagFromExpirationDate].compactMap { $0 } + tagViewModels
    }

    var createTagFromExpirationDate: TagViewModel? {
        guard let expirationTime = expirationTime else { return nil }

        return TagViewModel(
            title: expirationTime.countExpirationTime.apply(style: FontManager.OverlineRegularInteractionStrong),
            icon: Asset.mailHourglass.image,
            color: UIColorManager.InteractionWeak
        )
    }

    func initial(replacingEmails: [Email]) -> String {
        let senderName = self.senderName(labelId: "", replacingEmails: replacingEmails)
        return senderName.isEmpty ? "?" : senderName.shortName()
    }

    func sender(replacingEmails: [Email]) -> String {
        let senderName = self.senderName(labelId: "", replacingEmails: replacingEmails)
        return senderName.isEmpty ? "(\(String(format: LocalString._mailbox_no_recipient)))" : senderName
    }

    func isLabelLocation(labelId: String) -> Bool {
        labels
            .compactMap { $0 as? Label }
            .filter { !$0.exclusive }
            .map(\.labelID)
            .filter { Message.Location(rawValue: $0) == nil }
            .contains(labelId)
    }

    func senderName(labelId: String, replacingEmails: [Email]) -> String {
        if labelId == Message.Location.sent.rawValue || draft {
            return allEmailAddresses(replacingEmails)
        } else {
            return displaySender(replacingEmails)
        }
    }

    private var orderedLabels: [Label] {
        let predicate = NSPredicate(format: "labelID MATCHES %@", "(?!^\\d+$)^.+$")
        let allLabels = labels.filtered(using: predicate)
        return allLabels
            .compactMap { $0 as? Label }
            .filter { $0.type == 1 }
            .sorted(by: { $0.order.intValue < $1.order.intValue })
    }

}
