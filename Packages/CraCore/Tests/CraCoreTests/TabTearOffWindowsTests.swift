import CraCore
import Testing

/// A tab torn off on Windows opens its Blank Window where the Mac's would (#219), in pixels.
struct TabTearOffWindowsTests {
    let area = WindowFrame(x: 0, y: 0, width: 1920, height: 1040)

    @Test func centresOnTheDrop() {
        // Arc's drop in the open: 926 × 500 at (1100, 700) from the top left opened at (637, 450).
        let f = TabTearOff.frame(width: 926, height: 500, droppedAtX: 1100, y: 700, workArea: area, scale: 1)
        #expect(f == WindowFrame(x: 637, y: 450, width: 926, height: 500))
    }

    @Test func staysInsideTheWorkArea() {
        let f = TabTearOff.frame(width: 926, height: 500, droppedAtX: 10, y: 1030, workArea: area, scale: 1)
        #expect(f == WindowFrame(x: 20, y: 520, width: 926, height: 500))
        // At 150 % the inset is 30 pixels.
        let g = TabTearOff.frame(width: 926, height: 500, droppedAtX: 1910, y: 5, workArea: area, scale: 1.5)
        #expect(g == WindowFrame(x: 1920 - 30 - 926, y: 30, width: 926, height: 500))
    }

    @Test func shrinksToFit() {
        let f = TabTearOff.frame(width: 3000, height: 2000, droppedAtX: 900, y: 500, workArea: area, scale: 1)
        #expect(f == WindowFrame(x: 20, y: 20, width: 1880, height: 1000))
    }

    @Test func aSecondMonitorCounts() {
        let right = WindowFrame(x: 1920, y: 0, width: 1280, height: 984)
        let f = TabTearOff.frame(width: 926, height: 500, droppedAtX: 2500, y: 400, workArea: right, scale: 1)
        #expect(f == WindowFrame(x: 2037, y: 150, width: 926, height: 500))
    }

    @Test func onlyATabLetGoOverNoWindowTearsOff() {
        #expect(TabTearOff.tearsOff(isTab: true, incognito: false, dropAccepted: false, overAppWindow: false))
        #expect(!TabTearOff.tearsOff(isTab: true, incognito: false, dropAccepted: false, overAppWindow: true))
        #expect(!TabTearOff.tearsOff(isTab: true, incognito: true, dropAccepted: false, overAppWindow: false))
        #expect(!TabTearOff.tearsOff(isTab: false, incognito: false, dropAccepted: false, overAppWindow: false))
    }
}
