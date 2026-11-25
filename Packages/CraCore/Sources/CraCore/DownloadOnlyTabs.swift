/// A tab whose page only ever downloaded: a typed or opened address that turned out to be a file.
/// Chrome closes such a tab once its download starts and keeps the download going. Cra kept it as
/// a blank tab whose page had no document, so keys went nowhere while it was in front, and the
/// next address typed on that site came back to it as an open tab and did nothing (PC test,
/// 25 Nov 2026). Its tab now goes as Chrome's does; the page itself stays out of sight until its
/// downloads end, because Chromium reports a download only to the page it came from.
public struct DownloadOnlyTabs<Page: Hashable> {
    /// The pages held for their downloads, with the downloads still running.
    public private(set) var held: [Page: Set<UInt32>] = [:]

    public init() {}

    public enum Step: Equatable {
        /// Nothing changes.
        case none
        /// The page only downloaded: hold it out of sight, and close its tab.
        case holdAndCloseTab
        /// The page only downloaded, and the download already ended (refused, or its Save As
        /// cancelled): the tab closes with its page, nothing to wait for.
        case closeTab
        /// The held page's last download ended: close the page.
        case closePage
    }

    /// A download's report from `page`. `first` says it is the first report of this download in the window.
    public mutating func report(_ download: UInt32, from page: Page, first: Bool, pageHasDocument: Bool, running: Bool) -> Step {
        if var downloads = held[page] {
            if running { downloads.insert(download) } else { downloads.remove(download) }
            held[page] = downloads
            guard downloads.isEmpty else { return .none }
            held[page] = nil
            return .closePage
        }
        guard first, !pageHasDocument else { return .none }
        guard running else { return .closeTab }
        held[page] = [download]
        return .holdAndCloseTab
    }

    /// The page went (it closed, or its window did).
    public mutating func forget(_ page: Page) { held[page] = nil }
}
