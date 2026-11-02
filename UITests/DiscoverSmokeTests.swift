import XCTest

/// Faehrt die Hauptwege gegen ci/mock_server.py ab und legt Bildschirmfotos ab.
/// Die Fotos sind das Ergebnis: Sie zeigen Layout und Liquid Glass ohne iPhone.
final class DiscoverSmokeTests: XCTestCase {
    private let app = XCUIApplication()
    private let shots = URL(fileURLWithPath: "/tmp/discover-shots")

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        app.launchArguments = ["-serverURL", "http://127.0.0.1:8765", "-profileId", "test"]
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(2)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: shots.appendingPathComponent(name + ".png"))
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 20), "Tab fehlt: \(name)")
        b.tap()
    }

    func testHauptwege() {
        tab("Home")
        sleep(5)   // Testserver rechnet die Cover langsam
        shot("01-home")
        app.swipeUp()
        shot("02-home-gescrollt")

        tab("Suchen")
        shot("03-suche")
        let feld = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        if feld.waitForExistence(timeout: 5) {
            feld.tap()
            feld.typeText("Song")
            sleep(2)
            shot("03b-kuenstler-streifen")
            app.keyboards.buttons["search"].firstMatch.tap()
            shot("04-suche-ergebnis")
        }

        tab("Bibliothek")
        shot("05-bibliothek")
        app.swipeUp()
        shot("06-bibliothek-gescrollt")
        app.swipeDown()

        let liste = app.staticTexts["Playlist 2"].firstMatch
        if liste.waitForExistence(timeout: 8) {
            liste.tap()
            shot("07-playlist")
            let song = app.staticTexts["Song 2"].firstMatch
            if song.waitForExistence(timeout: 8) {
                song.tap()
                shot("08-minispieler")
                app.staticTexts["Song 2"].firstMatch.tap()
                shot("09-player")
            }
        }
    }

    /// Der schnelle Lauf: nur Song starten und die Modus-Knoepfe pruefen.
    func testWiedergabe() {
        tab("Bibliothek")
        let liste = app.staticTexts["Playlist 2"].firstMatch
        XCTAssertTrue(liste.waitForExistence(timeout: 20))
        liste.tap()
        let song = app.staticTexts["Song 2"].firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        song.tap()
        shot("20-spielt")
        app.staticTexts["Song 2"].firstMatch.tap()
        shot("21-player")
        let mix = app.buttons["player.shuffle"].firstMatch
        XCTAssertTrue(mix.waitForExistence(timeout: 5))
        mix.tap()
        shot("22-shuffle-an")
        mix.tap()
        let wdh = app.buttons["player.repeat"].firstMatch
        for (i, soll) in ["Weiter abspielen", "Song wiederholen", "Wiederholen aus"].enumerated() {
            wdh.tap()
            sleep(1)
            XCTAssertEqual(wdh.value as? String, soll)
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: shots.appendingPathComponent("23-wiederholen-\(i + 1).png"))
        }
    }

    /// Song ohne Ton und ohne Nachfolger: Der Player darf nicht behaupten, er spiele.
    func testToterSong() {
        tab("Suchen")
        let feld = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(feld.waitForExistence(timeout: 10))
        feld.tap()
        feld.typeText("Tot")
        app.keyboards.buttons["search"].firstMatch.tap()
        let song = app.staticTexts["Toter Song"].firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        song.tap()
        sleep(8)
        shot("30-toter-song")
        app.staticTexts["Toter Song"].firstMatch.tap()
        let play = app.buttons["player.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.value as? String, "angehalten")
        shot("31-toter-song-player")
    }

    /// Lokaler Song ohne Spotify-Verweise: Künstler und Album gehen trotzdem auf.
    func testMenueZiele() {
        tab("Suchen")
        let feld = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(feld.waitForExistence(timeout: 10))
        feld.tap()
        feld.typeText("Lokal")
        app.keyboards.buttons["search"].firstMatch.tap()
        let song = app.staticTexts["Lokaler Song"].firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 10))

        song.press(forDuration: 1.2)
        shot("40-song-menue")
        app.buttons["Gehe zu"].firstMatch.tap()
        app.buttons["Künstler"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Kuenstler 2"].firstMatch.waitForExistence(timeout: 10))
        shot("41-kuenstler-lokal")
        app.swipeDown(velocity: .fast)
        sleep(1)

        XCTAssertTrue(song.waitForExistence(timeout: 10))
        song.press(forDuration: 1.2)
        app.buttons["Gehe zu"].firstMatch.tap()
        app.buttons["Album"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Song 1"].firstMatch.waitForExistence(timeout: 10))
        shot("42-album-lokal")
    }

    /// Hörbücher liefern keine Folgen: Die Seite erklärt das und führt zu Spotify.
    func testHoerbuch() {
        tab("Suchen")
        let feld = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(feld.waitForExistence(timeout: 10))
        feld.tap()
        feld.typeText("Buch")
        app.keyboards.buttons["search"].firstMatch.tap()
        let karte = app.staticTexts["Testbuch"].firstMatch
        XCTAssertTrue(karte.waitForExistence(timeout: 10))
        karte.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Auf Spotify öffnen"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Testbuch"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["0 Folgen"].exists)
        shot("43-hoerbuch")
    }

    func testRadio() {
        tab("Radio")
        shot("10-radio")
    }
}
