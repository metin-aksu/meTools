import Foundation

enum UpdateCheckResult {
    case upToDate(current: String)
    case updateAvailable(latest: String, current: String, url: URL)
    case failed
}

/// Compares the running version against the latest GitHub release tag.
enum UpdateChecker {
    static let releasesPage = URL(string: "https://github.com/metin-aksu/meTools/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/metin-aksu/meTools/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func check(completion: @escaping (UpdateCheckResult) -> Void) {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                completion(.failed)
                return
            }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let url = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage

            if isNewer(latest, than: currentVersion) {
                completion(.updateAvailable(latest: latest, current: currentVersion, url: url))
            } else {
                completion(.upToDate(current: currentVersion))
            }
        }.resume()
    }

    /// Numeric compare of dotted versions: "1.10" > "1.9".
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
