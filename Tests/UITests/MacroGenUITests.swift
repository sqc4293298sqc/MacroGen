import XCTest

final class MacroGenUITests: XCTestCase {
    func testOpen3DModeling() {
        let app = XCUIApplication()
        app.launch()

        let enter = app.buttons["进入程序"]
        XCTAssertTrue(enter.waitForExistence(timeout: 20), "Welcome button missing")

        let know = app.buttons["知道了"]
        if know.waitForExistence(timeout: 3) {
            know.tap()
        }
        enter.tap()

        let tile = app.staticTexts["3D绘图建模"]
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "3D tile missing")
        tile.tap()

        sleep(8)
        XCTAssertEqual(app.state, .runningForeground, "App crashed after opening 3D modeling")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
