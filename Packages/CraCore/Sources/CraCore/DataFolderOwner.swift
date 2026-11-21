import Foundation

/// Whether this Cra owns its data folder: no other live process holds Chromium's profile lock in it
/// (`SingletonLock`, a symbolic link to "<host>-<pid>" that Chrome's process singleton makes, on CEF and on the
/// Chromium engine). Another Cra with a data folder of its own (a test copy with CRA_DATA_DIR, while the installed
/// Cra runs) doesn't count: launch migrations of this folder (extension copies, staged imports, removed
/// profiles) need only the folder to be free (GitHub #299's unpacked-extension-copy failed locally because any
/// running Cra counted).
public enum DataFolderOwner {
    /// `lockTarget`: where `SingletonLock` points, nil without one. `host`: this Mac's host name. `isAlive`: whether
    /// a process id runs. A lock from another host, or one this can't read, counts as held.
    public static func isFree(lockTarget: String?, host: String, me: Int32, isAlive: (Int32) -> Bool) -> Bool {
        guard let target = lockTarget else { return true }
        guard let dash = target.lastIndex(of: "-"), let pid = Int32(target[target.index(after: dash)...]), pid > 0 else {
            return false
        }
        let lockHost = String(target[..<dash])
        guard lockHost == host else { return false }
        return pid == me || !isAlive(pid)
    }

    /// Windows' Chromium holds `lockfile` in the data folder open for as long as it runs (its process
    /// singleton; the file goes when it closes). How opening it for writing went:
    public enum WindowsLockFile: Int32, Equatable, Sendable {
        /// No such file: no Chromium has the folder.
        case missing = 0
        /// It opened: left behind, held by no one.
        case opened = 1
        /// Another process has it open: a Cra runs on this folder.
        case sharingViolation = 2
        /// Anything else (no access): counts as held, as an unreadable `SingletonLock` does.
        case otherError = 3
    }

    /// Windows: the launch steps that change the folder (crash recovery, deleted profiles, staged
    /// sign-ins) run only when this is true. A second launch, handed to the Cra already running,
    /// leaves them to it.
    public static func isFree(windowsLockFile: WindowsLockFile) -> Bool {
        windowsLockFile == .missing || windowsLockFile == .opened
    }
}
