//
//  AttachmentListViewController.swift
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

import PassKit
import ProtonCore_UIFoundations
import QuickLook
import UIKit

class AttachmentListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    let viewModel: AttachmentListViewModel
    let tableView: UITableView = UITableView(frame: .zero)
    let bannerContainer: UIView = UIView()
    private var bannerHeightConstraint: NSLayoutConstraint?
    private var isInternetBannerPresented = false
    private var previewer: QuickViewViewController?
    private var lastClickAttachmentID: String?

    // Used in Quick Look dataSource
    private var tempClearFileURL: URL?
    private var currentNetworkStatus: NetworkStatus = .NotReachable

    init(viewModel: AttachmentListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        view = UIView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.register(AttachmentListTableViewCell.self)
        tableView.rowHeight = 72.0

        var titleToAdd = "\(viewModel.normalAttachments.count) "
        titleToAdd += viewModel.attachmentCount > 1 ?
            LocalString._attachments_list_title :
            LocalString._one_attachment_list_title
        title = titleToAdd

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged(_:)),
                                               name: NSNotification.Name.reachabilityChanged,
                                               object: nil)

        self.bindDownloadEvent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.previewer = nil
        self.lastClickAttachmentID = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.updateInterface(reachability: sharedInternetReachability)
    }

    private func bindDownloadEvent() {
        viewModel.attachmentDownloaded = { [weak self] attachmentID, clearFileURL in
            DispatchQueue.main.async {
                guard let self = self,
                      let (attachment, index) = self.viewModel.getAttachment(id: attachmentID) else { return }
                if self.lastClickAttachmentID == attachmentID {
                    self.tempClearFileURL = clearFileURL
                    if self.isPKPass(attachment: attachment) {
                        self.openPKPassView()
                    } else {
                        let type = attachment.mimeType
                        self.openQuickLook(mimeType: .init(rawValue: type))
                    }
                }
                self.tableView.reloadRows(at: [index], with: .automatic)
            }
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.normalAttachments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AttachmentListTableViewCell.CellID, for: indexPath)
        if let cellToConfig = cell as? AttachmentListTableViewCell {
            let attachment = viewModel.normalAttachments[indexPath.row]

            let byteCountFormatter = ByteCountFormatter()
            let sizeString = "\(byteCountFormatter.string(fromByteCount: Int64(attachment.size)))"

            let isDownloading = viewModel.isAttachmentDownloading(id: attachment.att?.attachmentID ?? "")
            cellToConfig.configure(mimeType: attachment.mimeType,
                                   fileName: attachment.fileName,
                                   fileSize: sizeString,
                                   isDownloading: isDownloading)

            if currentNetworkStatus == .NotReachable && !attachment.isDownloaded {
                cellToConfig.selectionStyle = .none
            } else {
                cellToConfig.selectionStyle = .default
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        viewModel.isEmpty(section: viewModel.attachmentSections[section]) ? 0 : 52
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let cell = tableView.cellForRow(at: indexPath)
        if cell?.selectionStyle == UITableViewCell.SelectionStyle.none {
            return nil
        } else {
            return indexPath
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let sectionItem = viewModel.attachmentSections[indexPath.section]
        var attachment: AttachmentInfo
        switch sectionItem {
        case .inline:
            attachment = viewModel.inlineAttachments[indexPath.row]
        case .normal:
            attachment = viewModel.normalAttachments[indexPath.row]
        }

        self.lastClickAttachmentID = attachment.id
        viewModel.open(attachmentInfo: attachment,
                       showPreviewer: { [weak self] in
            guard let self = self else { return }
            if self.isPKPass(attachment: attachment) { return }
            self.openQuickLook(mimeType: .unknownFile)
        }, failed: { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let errorClosure = { [weak self] (error: NSError) in
                    let alert = error.localizedDescription.alertController()
                    alert.addOKAction()
                    self?.present(alert, animated: true, completion: nil)
                }
                if let previewer = self.previewer {
                    previewer.dismiss(animated: true) { errorClosure(error) }
                } else {
                    errorClosure(error)
                }
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
            }
        })
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
}

private extension AttachmentListViewController {
    private func setUpSubviews() {
        bannerContainer.backgroundColor = ColorProvider.BackgroundNorm
        tableView.backgroundColor = ColorProvider.BackgroundNorm

        let stackView = UIStackView(arrangedSubviews: [bannerContainer, tableView])
        stackView.distribution = .fill
        stackView.axis = .vertical

        view.addSubview(stackView)

        let bannerHeightConstraint = bannerContainer.heightAnchor.constraint(equalToConstant: 0)
        bannerHeightConstraint.isActive = true

        [
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ].activate()
        self.bannerHeightConstraint = bannerHeightConstraint
    }

    func isPKPass(attachment: AttachmentInfo) -> Bool {
        let fileName = attachment.fileName.clear
        let type = attachment.mimeType
        return type == "application/vnd.apple.pkpass" ||
            fileName.contains(check: ".pkpass") == true
    }

    func openQuickLook(mimeType: MIMEType) {
        if self.tempClearFileURL != nil, let previewer = self.previewer {
            previewer.reloadData()
            let delayTypes: [MIMEType] = [.video]
            previewer.removeLoadingView(needDelay: delayTypes.contains(mimeType))
        } else {
            let previewQL = QuickViewViewController()
            previewQL.dataSource = self
            previewQL.delegate = self
            self.present(previewQL, animated: true, completion: nil)
            self.previewer = previewQL
        }
    }

    func openPKPassView() {
        if let url = self.tempClearFileURL,
           let pkFile = try? Data(contentsOf: url),
            let pass = try? PKPass(data: pkFile),
            let viewController = PKAddPassesViewController(pass: pass),
            // as of iOS 12.0 SDK, PKAddPassesViewController will not be initialized on iPads without any warning 🤯
            (viewController as UIViewController?) != nil {
            self.present(viewController, animated: true, completion: nil)
        }
    }
}

// MARK: - Handle Network status changed
private extension AttachmentListViewController {
    private func showInternetConnectionBanner() {
        guard isInternetBannerPresented == false else { return }
        let banner = MailBannerView()
        bannerContainer.addSubview(banner)

        banner.label.attributedText = LocalString._banner_no_internet_connection
            .apply(style: FontManager.body3RegularTextInverted)

        [
            banner.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            banner.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor),
            banner.topAnchor.constraint(equalTo: bannerContainer.topAnchor)
        ].activate()

        bannerHeightConstraint?.isActive = false

        view.layoutIfNeeded()

        isInternetBannerPresented = true
    }

    private func hideInternetConnectionBanner() {
        guard isInternetBannerPresented else { return }
        UIView.animate(withDuration: 0.25,
                       animations: { [weak self] in
                        self?.bannerHeightConstraint?.isActive = true
                       },
                       completion: { [weak self] _ in
                        self?.bannerContainer.subviews.forEach { $0.removeFromSuperview() }
                        self?.isInternetBannerPresented = false
                       })
    }

    private func updateInterface(reachability: Reachability) {
        let netStatus = reachability.currentReachabilityStatus()
        currentNetworkStatus = netStatus
        switch netStatus {
        case .NotReachable:
            showInternetConnectionBanner()
        case .ReachableViaWWAN:
            hideInternetConnectionBanner()
        case .ReachableViaWiFi:
            hideInternetConnectionBanner()
        default:
            break
        }
        tableView.reloadData()
    }

    @objc
    private func reachabilityChanged(_ note: Notification) {
        if let currentReachability = note.object as? Reachability {
            self.updateInterface(reachability: currentReachability)
        }
    }
}

extension AttachmentListViewController: QLPreviewControllerDataSource, QLPreviewControllerDelegate {

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return self.tempClearFileURL != nil ? 1 : 0
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        if let url = self.tempClearFileURL {
            return url as QLPreviewItem
        } else {
            fatalError("Should not reach here")
        }
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        guard let url = self.tempClearFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
        self.tempClearFileURL = nil
        self.lastClickAttachmentID = nil
    }
}
