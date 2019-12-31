//
//  SignInViewController.swift
//  ProtonMail
//
//
//  The MIT License
//
//  Copyright (c) 2018 Proton Technologies AG
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


import UIKit
import MBProgressHUD
import DeviceCheck
import PromiseKit

class AccountConnectViewController: ProtonMailViewController, ViewModelProtocol, CoordinatedNew {
    private var viewModel : SigninViewModel!
    private var coordinator : AccountConnectCoordinator?
    
    func set(viewModel: SigninViewModel) {
        self.viewModel = viewModel
    }
    func set(coordinator: AccountConnectCoordinator) {
        self.coordinator = coordinator
    }
    func getCoordinator() -> CoordinatorNew? {
        return self.coordinator
    }

    private let animationDuration: TimeInterval = 0.5
    private let keyboardPadding: CGFloat        = 12
    private let buttonDisabledAlpha: CGFloat    = 0.5
    
    private let kDecryptMailboxSegue            = "mailboxSegue"
    private let kSignUpKeySegue                 = "sign_in_to_sign_up_segue"
    private let kSegueTo2FACodeSegue            = "2fa_code_segue"
    
    private var isShowpwd      = false
    
    //define
    private let hidePriority : UILayoutPriority = UILayoutPriority(rawValue: 1.0)
    private let showPriority: UILayoutPriority  = UILayoutPriority(rawValue: 750.0)
    
    //views
    @IBOutlet weak var usernameView: UIView!
    @IBOutlet weak var passwordView: UIView!
    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    
    @IBOutlet weak var signInButton: UIButton!
    @IBOutlet weak var signInTitle: UILabel!
    @IBOutlet weak var forgotPwdButton: UIButton!
    
    // Constraints
    @IBOutlet weak var scrollBottomPaddingConstraint: NSLayoutConstraint!
    @IBOutlet weak var loginMidlineConstraint: NSLayoutConstraint!
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = LocalString._connect_account
        
        let cancelButton = UIBarButtonItem(title: LocalString._general_cancel_button, style: .plain, target: self, action: #selector(cancelAction))
        self.navigationItem.leftBarButtonItem = cancelButton

        setupTextFields()
        setupButtons()
    }
    
    @objc internal func dismiss() {
//        if self.presentingViewController != nil {
//            self.dismiss(animated: true, completion: nil)
//        } else {
//            let _ = self.navigationController?.popViewController(animated: true)
//        }
        
        self.navigationController?.popToRootViewController(animated: true)
    }
    
    @objc func cancelAction(_ sender: UIBarButtonItem) {
        let alertController = UIAlertController(title: LocalString._general_confirmation_title,
                                                message: nil, preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: LocalString._composer_save_draft_action,
                                                style: .default, handler: { (action) -> Void in
                                                    
        }))
        
        alertController.addAction(UIAlertAction(title: LocalString._general_cancel_button,
                                                style: .cancel, handler: { (action) -> Void in

        }))
        
        alertController.addAction(UIAlertAction(title: LocalString._composer_discard_draft_action,
                                                style: .destructive, handler: { (action) -> Void in
                                                    self.dismiss()
        }))
        
        alertController.popoverPresentationController?.barButtonItem = sender
        alertController.popoverPresentationController?.sourceRect = self.view.frame
        present(alertController, animated: true, completion: nil)
    }

    override var shouldAutorotate : Bool {
        return false
    }

    @IBAction func showPasswordAction(_ sender: UIButton) {
        isShowpwd = !isShowpwd
        sender.isSelected = isShowpwd
        
        if isShowpwd {
            self.passwordTextField.isSecureTextEntry = false
        } else {
            self.passwordTextField.isSecureTextEntry = true
        }
    }
        
    override func didMove(toParent parent: UIViewController?) {
        
//        if (!(parent?.isEqual(self.parent) ?? false)) {
//        }
//
//        if SignInViewController.isComeBackFromMailbox {
//            showLoginViews()
//            SignInManager.shared.clean()
//        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addKeyboardObserver(self)
        
        let uName = (usernameTextField.text ?? "").trim()
        let pwd = (passwordTextField.text ?? "")
        
        updateSignInButton(usernameText: uName, passwordText: pwd)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if UIDevice.current.isLargeScreen() {
            usernameTextField.becomeFirstResponder()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeKeyboardObserver(self)
    }
    
    override var preferredStatusBarStyle : UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == kSegueTo2FACodeSegue {
            let popup = segue.destination as! TwoFACodeViewController
            popup.delegate = self
            popup.mode = .twoFactorCode
            self.setPresentationStyleForSelfController(self, presentingController: popup)
        }
    }
    
    // MARK: - Private methods

//    func showLoginViews() {
//        UIView.animate(withDuration: 1.0, animations: { () -> Void in
//            self.usernameView.alpha      = 1.0
//            self.passwordView.alpha      = 1.0
//            self.signInButton.alpha      = 1.0
//        }, completion: { finished in
//
//        })
//    }
    
    func dismissKeyboard() {
        usernameTextField.resignFirstResponder()
        passwordTextField.resignFirstResponder()
    }
    
    internal func setupTextFields() {
        signInTitle.text = LocalString._login_to_pm_act
        usernameTextField.attributedPlaceholder = NSAttributedString(string: LocalString._username,
                                                                     attributes:[NSAttributedString.Key.foregroundColor : UIColor(hexColorCode: "#cecaca")])
        passwordTextField.attributedPlaceholder = NSAttributedString(string: LocalString._password,
                                                                     attributes:[NSAttributedString.Key.foregroundColor : UIColor(hexColorCode: "#cecaca")])
    }
    
    func setupButtons() {
        signInButton.layer.borderColor      = UIColor.ProtonMail.Login_Button_Border_Color.cgColor
        signInButton.alpha                  = buttonDisabledAlpha
        
        signInButton.setTitle(LocalString._general_login, for: .normal)
        forgotPwdButton.setTitle(LocalString._forgot_password, for: .normal)        
    }
    
    func updateSignInButton(usernameText: String, passwordText: String) {
        signInButton.isEnabled = !usernameText.isEmpty && !passwordText.isEmpty
        
        UIView.animate(withDuration: animationDuration, animations: { () -> Void in
            if self.signInButton.alpha != 0.0 {
                self.signInButton.alpha = self.signInButton.isEnabled ? 1.0 : self.buttonDisabledAlpha
            }
        })
    }
    
    // MARK: - Actions
    @IBAction func signInAction(_ sender: UIButton) {
        dismissKeyboard()
        self.signIn(username: self.usernameTextField.text ?? "",
                    password: self.passwordTextField.text ?? "",
                    cachedTwoCode: nil) // FIXME
    }
    
    @IBAction func fogorPasswordAction(_ sender: AnyObject) {
        dismissKeyboard()

        let alertStr = LocalString._please_use_the_web_application_to_reset_your_password
        let alertController = alertStr.alertController()
        alertController.addOKAction()
        self.present(alertController, animated: true, completion: nil)
    }
    
    enum TokenError : Error {
        case unsupport
        case empty
        case error
    }
    
    func generateToken() -> Promise<String> {
        if #available(iOS 11.0, *) {
            let currentDevice = DCDevice.current
            if currentDevice.isSupported {
                let deferred = Promise<String>.pending()
                currentDevice.generateToken(completionHandler: { (data, error) in
                    if let tokenData = data {
                        deferred.resolver.fulfill(tokenData.base64EncodedString())
                    } else if let error = error {
                        deferred.resolver.reject(error)
                    } else {
                        deferred.resolver.reject(TokenError.empty)
                    }
                })
                return deferred.promise
            }
        }
        
        #if Enterprise
        return Promise<String>.value("EnterpriseBuildInternalTestOnly".encodeBase64())
        #else
        return Promise<String>.init(error: TokenError.unsupport)
        #endif
    }
    
    @IBAction func signUpAction(_ sender: UIButton) {
        dismissKeyboard()
        firstly {
            generateToken()
        }.done { (token) in
            self.performSegue(withIdentifier: self.kSignUpKeySegue, sender: token)
        }.catch { (error) in
            let alert = LocalString._mobile_signups_are_disabled_pls_later_pm_com.alertController()
            alert.addOKAction()
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction func tapAction(_ sender: UITapGestureRecognizer) {
        dismissKeyboard()
    }
    
    internal func signIn(username: String, password: String, cachedTwoCode: String?) {
        MBProgressHUD.showAdded(to: self.view, animated: true)
        SignInViewController.isComeBackFromMailbox = false
        self.viewModel.signIn(username: username, password: password, cachedTwoCode: cachedTwoCode) { (result) in
            switch result {
            case .ask2fa:
                MBProgressHUD.hide(for: self.view, animated: true)
                self.performSegue(withIdentifier: self.kSegueTo2FACodeSegue, sender: self)
            case .error(let error):
                PMLog.D("error: \(error)")
                MBProgressHUD.hide(for: self.view, animated: true)
                if !error.code.forceUpgrade {
                    let alertController = error.alertController()
                    alertController.addOKAction()
                    self.present(alertController, animated: true, completion: nil)
                }
            case .ok:
                MBProgressHUD.hide(for: self.view, animated: true)
                self.dismiss()
            case .mbpwd:
                self.performSegue(withIdentifier: self.kDecryptMailboxSegue, sender: self)
            }
        }
    }
}

extension AccountConnectViewController : TwoFACodeViewControllerDelegate {
    func ConfirmedCode(_ code: String, pwd : String) {
        NotificationCenter.default.addKeyboardObserver(self)
        self.signIn(username: usernameTextField.text ?? "",
                    password: passwordTextField.text ?? "",
                    cachedTwoCode: code)
    }

    func Cancel2FA() {
        //TODO:: fix me
//        sharedUserDataService.twoFactorStatus = 0
//        sharedUserDataService.authResponse = nil
        NotificationCenter.default.addKeyboardObserver(self)
    }
}

// MARK: - NSNotificationCenterKeyboardObserverProtocol
extension AccountConnectViewController: NSNotificationCenterKeyboardObserverProtocol {
    func keyboardWillHideNotification(_ notification: Notification) {
        let keyboardInfo = notification.keyboardInfo
        scrollBottomPaddingConstraint.constant = 0.0
        UIView.animate(withDuration: keyboardInfo.duration, delay: 0, options: keyboardInfo.animationOption, animations: { () -> Void in
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
    
    func keyboardWillShowNotification(_ notification: Notification) {
        let keyboardInfo = notification.keyboardInfo
        let info: NSDictionary = notification.userInfo! as NSDictionary
        if let keyboardSize = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            scrollBottomPaddingConstraint.constant = keyboardSize.height
        }
        UIView.animate(withDuration: keyboardInfo.duration, delay: 0, options: keyboardInfo.animationOption, animations: { () -> Void in
            self.view.layoutIfNeeded()
        }, completion: nil)
    }
}

// MARK: - UITextFieldDelegate
extension AccountConnectViewController: UITextFieldDelegate {
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        updateSignInButton(usernameText: "", passwordText: "")
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let text = textField.text! as NSString
        let changedText = text.replacingCharacters(in: range, with: string)
        
        if textField == usernameTextField {
            updateSignInButton(usernameText: changedText, passwordText: passwordTextField.text!)
        } else if textField == passwordTextField {
            updateSignInButton(usernameText: usernameTextField.text!, passwordText: changedText)
        }
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == usernameTextField {
            passwordTextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        
        let uName = (usernameTextField.text ?? "").trim()
        let pwd = (passwordTextField.text ?? "")
        
        if !uName.isEmpty && !pwd.isEmpty {
            self.signIn(username: self.usernameTextField.text ?? "",
                        password: self.passwordTextField.text ?? "",
                        cachedTwoCode: nil) // FIXME
        }
        
        return true
    }
}
