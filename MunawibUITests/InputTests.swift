import XCTest

/// Regression tests for "digits typed don't appear until the field loses focus".
/// Every assertion on a field's value happens WHILE the field is still focused (keyboard up),
/// and a screenshot is captured mid-typing.
final class InputTests: XCTestCase {
    var app: XCUIApplication!
    let shotsDir = ProcessInfo.processInfo.environment["SHOTS_DIR"]

    override func setUp() {
        continueAfterFailure = true
    }

    func launch(_ args: [String]) {
        app = XCUIApplication()
        app.launchArguments = args + ["-appLanguage", "ar", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA", "-AppleKeyboards", "(ar@sw=Arabic, en_US@sw=QWERTY)"]
        app.launch()
    }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let d = shotsDir { try? s.pngRepresentation.write(to: URL(fileURLWithPath: d).appendingPathComponent("\(name).png")) }
    }

    func field(_ id: String) -> XCUIElement {
        let f = app.textFields[id]
        if f.waitForExistence(timeout: 8) { return f }
        return app.secureTextFields[id]
    }

    /// Taps number-pad keys one at a time, accepting Latin or Arabic-Indic key labels.
    func tapDigits(_ digits: String) {
        let arabic: [Character: String] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤", "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        for d in digits {
            let latin = app.keys[String(d)].firstMatch
            if latin.waitForExistence(timeout: 2) { latin.tap() }
            else if let a = arabic[d], app.keys[a].firstMatch.exists { app.keys[a].firstMatch.tap() }
            else { XCTFail("no key for \(d)") }
        }
    }

    func assertLive(_ f: XCUIElement, _ expected: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.keyboards.firstMatch.exists, "keyboard should still be up for \(name)", file: file, line: line)
        XCTAssertEqual(f.value as? String, expected, "\(name) must show typed text while focused", file: file, line: line)
        shot(name)
    }

    func testLoginFieldsRenderWhileTyping() {
        launch(["-auth", "login"])
        let id = field("login.identifier")
        id.tap()
        id.typeText("5002")
        assertLive(id, "5002", "login_identifier_typed")
        let code = field("login.hospitalCode")
        XCTAssertTrue(code.waitForExistence(timeout: 3), "hospital code field appears for numeric identifier")
        code.tap()
        code.typeText("nr7k2q")
        assertLive(code, "NR7K2Q", "login_hospitalcode_typed")
        // Arabic-Indic digits are normalised to Latin, not dropped
        id.tap()
        id.typeText("٧")
        assertLive(id, "50027", "login_identifier_arabic_digit")
    }

    func testSignupNumberPad() {
        launch(["-auth", "signup", "-noprefill"])
        let hn = field("signup.hnNumber")
        hn.tap()
        tapDigits("4321")
        assertLive(hn, "4321", "signup_hn_numberpad")
    }

    func testSignupStep2NumberPad() {
        launch(["-auth", "signup2"])
        let n = field("signup.number")
        n.tap()
        tapDigits("5001")
        assertLive(n, "5001", "signup_admin_numberpad")
        let em = field("signup.email")
        em.tap()
        em.typeText("x")
        XCTAssertEqual(em.value as? String, "admin@alnoor.sax")
    }

    func testActivationCode() {
        launch(["-auth", "activate"])
        let c = field("activate.code")
        c.tap()
        c.typeText("ab12cd")
        assertLive(c, "AB12CD", "activate_code_typed")
    }

    func testEmployeeFormNumber() {
        launch(["-demo", "-screen", "employees"])
        let add = app.buttons["إضافة موظف"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let n = field("employee.number")
        n.tap()
        tapDigits("7788")
        assertLive(n, "7788", "employee_number_numberpad")
    }

}

/// English localization + in-app language switch.
final class LocalizationTests: XCTestCase {
    let shotsDir = ProcessInfo.processInfo.environment["SHOTS_DIR"]
    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let d = shotsDir { try? s.pngRepresentation.write(to: URL(fileURLWithPath: d).appendingPathComponent("\(name).png")) }
    }
    func launch(_ lang: String, _ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-appLanguage", lang, "-AppleLanguages", "(\(lang))"]
        app.launch(); return app
    }

    func testEnglishLoginScreen() {
        let app = launch("en", ["-auth", "login"])
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 10), "English sign-in button")
        XCTAssertTrue(app.buttons["Forgot password?"].exists)
        XCTAssertFalse(app.buttons["تسجيل الدخول"].exists, "no Arabic leftovers")
        shot("en_login")
    }

    func testArabicLoginScreen() {
        let app = launch("ar", ["-auth", "login"])
        XCTAssertTrue(app.buttons["تسجيل الدخول"].waitForExistence(timeout: 10))
        shot("ar_login")
    }

    func testSwitchLanguageOnLogin() {
        let app = launch("ar", ["-auth", "login"])
        let menu = app.buttons["languageMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let en = app.buttons["English"].firstMatch
        XCTAssertTrue(en.waitForExistence(timeout: 5))
        en.tap()
        XCTAssertTrue(app.buttons["Sign In"].waitForExistence(timeout: 5), "switch applies immediately")
        shot("switch_to_en")
    }

    func testEnglishScreens() {
        for (lang, screens) in [("en", ["home", "roster", "settings"]), ("ar", ["home", "roster", "settings"])] {
            for sc in screens {
                let app = launch(lang, ["-demo", "-hospitalInfo", "-screen", sc])
                sleep(3)
                if lang == "en" && sc == "settings" { XCTAssertTrue(app.staticTexts["Shift times"].waitForExistence(timeout: 5) || app.staticTexts["اللغة / Language"].exists) }
                shot("\(lang)_\(sc)")
                app.terminate()
            }
        }
    }
}
