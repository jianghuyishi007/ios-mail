//
//  SignupHumanVerificationRobot.swift
//  ProtonCore-TestingToolkit - Created on 19.04.2021.
//
//  Copyright (c) 2021 Proton Technologies AG
//
//  This file is part of Proton Technologies AG and ProtonCore.
//
//  ProtonCore is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonCore is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonCore.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import XCTest
import pmtest
import ProtonCore_CoreTranslation

private let titleName = CoreString._hv_title
private let hCaptchaButtonCheckName = "hCaptcha checkbox. Select in order to trigger the challenge, or to bypass it if you have an accessibility cookie."
private let closeButtonAccessibilityId = "closeButton"
private let captchaSelectedControlLabel = CoreString._hv_captha_method_name
private let smsSelectedControlLabel = CoreString._hv_sms_method_name
private let emailSelectedControlLabel = CoreString._hv_email_method_name
private let emailTextField = "EmailVerifyViewController.emailTextFieldView.textField"
private let sendCodeButtonLabel = CoreString._hv_email_verification_button
private let verifyCodeTextField = "VerifyCodeViewController.verifyCodeTextFieldView.textField"
private let verifyCodeButtonLabel = CoreString._hv_verification_verify_button

public final class SignupHumanVerificationRobot: CoreElements {
    public enum HVOrSummaryRobot {
        case humanVerification(SignupHumanVerificationRobot)
        case summary(AccountSummaryRobot)

        public func proceed<T: CoreElements>(email: String, code: String, to: T.Type) -> T {
            switch self {
            case .humanVerification(let hvRobot):
                return hvRobot
                    .verify.humanVerificationScreenIsShown()
                    .performEmailVerification(email: email, code: code, to: CompleteRobot.self)
                    .verify.completeScreenIsShown(robot: T.self)
            case .summary(let summaryRobot):
                return summaryRobot
                    .accountSummaryElementsDisplayed(robot: T.self)
            }
        }
    }
    
    public let verify = Verify()
    
    public final class Verify: CoreElements {
        @discardableResult
        public func humanVerificationScreenIsShown() -> SignupHumanVerificationRobot {
            staticText(titleName).wait(time: 15).checkExists()
            return SignupHumanVerificationRobot()
        }
        
        public func isHumanVerificationRequired() -> HVOrSummaryRobot {
            let staticText = XCUIApplication().staticTexts[titleName]
            Wait(time: 10.0).forElement(staticText)
            return staticText.exists ? .humanVerification(SignupHumanVerificationRobot()) : .summary(AccountSummaryRobot())
        }
    }
    
    public func switchToEmailHVMethod() -> SignupHumanVerificationRobot {
        button(emailSelectedControlLabel).tap()
        return self
    }
    
    public func insertEmail(_ email: String) -> SignupHumanVerificationRobot {
        textField(emailTextField).tap().typeText(email)
        return self
    }
    
    public func sendCodeButton() -> SignupHumanVerificationRobot {
        button(sendCodeButtonLabel).tap()
        return self
    }
    
    public func fillInCode(_ code: String) -> SignupHumanVerificationRobot {
        textField(verifyCodeTextField).tap().typeText(code)
        return self
    }
    
    public func verifyCodeButton<Robot: CoreElements>(to: Robot.Type) -> Robot {
        button(verifyCodeButtonLabel).tap()
        return Robot()
    }
    
    public func performEmailVerification<Robot: CoreElements>(
        email: String, code: String, to: Robot.Type
    ) -> Robot {
        self
            .switchToEmailHVMethod()
            .insertEmail(email)
            .sendCodeButton()
            .fillInCode(code)
            .verifyCodeButton(to: Robot.self)
    }

    public func humanVerificationCaptchaTap<Robot: CoreElements>(to: Robot.Type) -> Robot {
        let element = XCUIApplication().webViews["RecaptchaViewController.webView"].webViews.switches[hCaptchaButtonCheckName]
        Wait().forElement(element)
        element.tap()
        return Robot()
    }
    
    public func closeButton() -> RecoveryRobot {
        button(closeButtonAccessibilityId).tap()
        return RecoveryRobot()
    }
}
