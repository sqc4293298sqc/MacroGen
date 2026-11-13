import Foundation

/// 版本号统一出口：以后只改 project.yml 的 MARKETING_VERSION，界面和标题自动跟着变
enum AppInfo {
    /// 例如 "2.6.1"
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }

    /// 例如 " v2.6.1"，取不到版本号时为空串
    static var versionTag: String {
        version.isEmpty ? "" : " v\(version)"
    }

    /// 标题用：宏程序生成器 v2.6.1
    static var appTitle: String {
        "宏程序生成器" + versionTag
    }
}
