// Copyright (c) 2021 Proton Technologies AG
//
// This file is part of ProtonMail.
//
// ProtonMail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ProtonMail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ProtonMail. If not, see https://www.gnu.org/licenses/.

import ProtonCore_UIFoundations
import UIKit

@IBDesignable class ProgressBarButtonTableViewCell: UITableViewCell {
    static var CellID : String {
        return "\(self)"
    }
    
    typealias buttonActionBlock = () -> Void
    var callback: buttonActionBlock?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        //TODO some UI changes to progress view and button?
        self.pauseButton.setMode(mode: .solid)
        self.pauseButton.setTitle("Pause", for: UIControl.State.normal)
    }
    
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var estimatedTimeLabel: UILabel!
    @IBOutlet weak var currentProgressLabel: UILabel!
    @IBOutlet weak var pauseButton: ProtonButton!
    
    @IBAction func pauseButtonPressed(_ sender: UIButton) {
        callback?()
    }
    
    func configCell(_ titleLine: String, _ topLine: String, _ estimatedTime: Int, _ currentProgress: Int, _ textButtonNormal: String, _ textButtonPressed: String, complete: buttonActionBlock?) {
        
        var leftAttributes = FontManager.Default
        leftAttributes.addTextAlignment(.left)
        titleLabel.attributedText = NSMutableAttributedString(string: titleLine, attributes: leftAttributes)
        
        statusLabel.text = topLine
        estimatedTimeLabel.text = String(estimatedTime) + " minutes remaining..."
        currentProgressLabel.text = String(currentProgress) + "%"
        progressView.setProgress(Float(currentProgress)/100.0, animated: true)
        
        //implementation of pause button
        callback = complete
        
        self.layoutIfNeeded()
    }
    
}

extension ProgressBarButtonTableViewCell: IBDesignableLabeled {
    override func prepareForInterfaceBuilder() {
        self.labelAtInterfaceBuilder()
    }
}