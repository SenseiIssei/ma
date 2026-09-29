import Foundation

/// The reel-free way into a social app: its website, opened in Safari where
/// Ma Filter hides Reels, Shorts and feeds. No iPhone app may change what
/// another app shows, so this is as close to "Instagram without Reels" as
/// iOS allows.
enum ReelFreeWeb {
    /// `x-safari-https` makes iOS open Safari even when the site has a
    /// universal link that would otherwise jump back into the blocked app.
    static func url(forAppName name: String?) -> URL? {
        guard let name = name?.lowercased() else { return nil }
        let target: String?
        if name.contains("instagram") {
            target = "www.instagram.com/"
        } else if name.contains("youtube") {
            target = "m.youtube.com/"
        } else if name == "x" || name.contains("twitter") {
            target = "x.com/home"
        } else if name.contains("linkedin") {
            target = "www.linkedin.com/messaging/"
        } else if name.contains("facebook") {
            target = "m.facebook.com/"
        } else {
            target = nil
        }
        return target.flatMap { URL(string: "x-safari-https://" + $0) }
    }
}
