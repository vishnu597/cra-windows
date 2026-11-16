import Foundation

/// Help ▸ Troubleshooting ▸ Copy Cra Info (Arc's Copy Arc Info): what a bug report starts with,
/// Cra's version, the engine's and the system's, one per line.
public enum CraInfo {
    /// "Cra 1.2.3 (456)"; just "Cra" for a build that carries no version (a local Windows build is
    /// 0.0.0).
    public static func appLine(version: String?, build: String? = nil) -> String {
        guard let version, !version.isEmpty, version != "0.0.0" else { return "Cra" }
        guard let build, !build.isEmpty, build != version else { return "Cra \(version)" }
        return "Cra \(version) (\(build))"
    }

    /// The Windows line, as Settings ▸ System ▸ About names it: "Windows 11 25H2 (build
    /// 26200.9457)". Windows 11 still says "Windows 10" in its ProductName, so the build decides:
    /// 22000 and later is 11.
    public static func windowsLine(build: Int, displayVersion: String?, revision: Int?) -> String {
        let name = build >= 22000 ? "Windows 11" : "Windows 10"
        let release = displayVersion.flatMap { $0.isEmpty ? nil : " " + $0 } ?? ""
        let number = revision.map { "\(build).\($0)" } ?? "\(build)"
        return "\(name)\(release) (build \(number))"
    }

    /// The text Copy Cra Info puts on the clipboard.
    public static func text(app: String, engine: String, system: String) -> String {
        [app, engine, system].joined(separator: "\n")
    }
}
