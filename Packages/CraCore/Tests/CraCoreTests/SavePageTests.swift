import CraCore
import Testing

/// File ▸ Save Page As and Edit ▸ Find's selection commands, as Windows performs them.
struct SavePageTests {
    @Test func formatsMatchTheMacsPopUp() {
        #expect(SavePage.Format.allCases == [.singleFile, .htmlOnly])
        #expect(SavePage.Format.singleFile.typeName == "Web Page, Single File")
        #expect(SavePage.Format.htmlOnly.typeName == "Web Page, HTML Only")
        #expect(SavePage.Format.singleFile.fileExtension == "mhtml")
        #expect(SavePage.Format.htmlOnly.fileExtension == "html")
        #expect(SavePage.Format.singleFile.request.method == "Page.captureSnapshot")
        #expect(SavePage.Format.singleFile.request.params == #"{"format":"mhtml"}"#)
        #expect(SavePage.Format.htmlOnly.request.method == "Runtime.evaluate")
        #expect(SavePage.Format.htmlOnly.request.params.contains("document.documentElement.outerHTML"))
    }

    @Test func contentsComeFromEachReply() {
        #expect(SavePage.Format.singleFile.contents(fromReply: #"{"data":"MIME-Version: 1.0"}"#) == "MIME-Version: 1.0")
        #expect(SavePage.Format.htmlOnly.contents(fromReply: #"{"result":{"type":"string","value":"<!DOCTYPE html>\n<html></html>"}}"#)
            == "<!DOCTYPE html>\n<html></html>")
        // A failed call, or the other format's reply, saves nothing.
        #expect(SavePage.Format.singleFile.contents(fromReply: nil) == nil)
        #expect(SavePage.Format.singleFile.contents(fromReply: "not json") == nil)
        #expect(SavePage.Format.htmlOnly.contents(fromReply: #"{"data":"x"}"#) == nil)
    }

    @Test func suggestedNameIsAFileNameWindowsTakes() {
        #expect(SavePage.suggestedFileName(title: "Cra") == "Cra.mhtml")
        #expect(SavePage.suggestedFileName(title: "Cra", format: .htmlOnly) == "Cra.html")
        #expect(SavePage.suggestedFileName(title: "") == "Page.mhtml")
        #expect(SavePage.suggestedFileName(title: "   ") == "Page.mhtml")
        #expect(SavePage.suggestedFileName(title: "a/b:c\\d*e?f\"g<h>i|j") == "a-b-c-d-e-f-g-h-i-j.mhtml")
        #expect(SavePage.suggestedFileName(title: "Line\nbreak") == "Line-break.mhtml")
        #expect(SavePage.suggestedFileName(title: "Ends with dots...") == "Ends with dots.mhtml")
        #expect(SavePage.suggestedFileName(title: String(repeating: "x", count: 300)) == String(repeating: "x", count: 120) + ".mhtml")
    }

    @Test func typedExtensionDecidesTheFormat() {
        #expect(SavePage.format(forPath: #"C:\Users\a\Downloads\Cra.html"#, chosenType: .singleFile) == .htmlOnly)
        #expect(SavePage.format(forPath: #"C:\Users\a\Downloads\Cra.HTM"#, chosenType: .singleFile) == .htmlOnly)
        #expect(SavePage.format(forPath: "/tmp/Cra.mhtml", chosenType: .htmlOnly) == .singleFile)
        #expect(SavePage.format(forPath: "/tmp/Cra.mht", chosenType: .htmlOnly) == .singleFile)
        #expect(SavePage.format(forPath: "/tmp/Cra.txt", chosenType: .htmlOnly) == .htmlOnly)
        #expect(SavePage.format(forPath: "/tmp/Cra", chosenType: .singleFile) == .singleFile)
    }

    @Test func selectionBecomesTheSearch() {
        #expect(FindSelection.evaluateParams.contains("getSelection().toString()"))
        #expect(FindSelection.query(fromReply: #"{"result":{"type":"string","value":"  hello world \n"}}"#) == "hello world")
        #expect(FindSelection.query(fromReply: #"{"result":{"type":"string","value":" \n "}}"#) == nil)
        #expect(FindSelection.query(fromReply: nil) == nil)
        #expect(FindSelection.query(fromReply: "{}") == nil)
        // The field doesn't change for the same text, so the window searches itself.
        #expect(FindSelection.needsSearch(selection: "cra", barQuery: "cra"))
        #expect(!FindSelection.needsSearch(selection: "cra", barQuery: "arc"))
        #expect(FindSelection.jumpScript.contains("scrollIntoView({block:'center'})"))
    }

    @Test func windowsReachesThemFromTheCommandBar() {
        let windows = Dictionary(uniqueKeysWithValues: KeyBindingDefaults.windows.map { ($0.id, $0) })
        // No menu bar on Windows: Edit ▸ Find's commands join the command bar, without keys
        // (Ctrl+E and Ctrl+J are Open Extensions and Downloads).
        for id in ["useSelectionForFind", "jumpToSelection"] {
            #expect(windows[id]?.inCommandBar == true, "\(id)")
            #expect(windows[id]?.shortcuts == [], "\(id)")
        }
        #expect(KeyBindingDefaults.mac.first { $0.id == "useSelectionForFind" }?.inCommandBar == false)
        #expect(windows["savePageAs"]?.shortcuts == [KeyChord("s", [.control, .shift])])
        #expect(windows["savePageAs"]?.inCommandBar == true)
        let others = KeyBindingDefaults.windows.filter { $0.id != "savePageAs" }
        #expect(!others.contains { $0.shortcuts.contains(KeyChord("s", [.control, .shift])) })
    }
}
