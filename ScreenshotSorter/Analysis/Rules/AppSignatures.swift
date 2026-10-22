import Foundation

/// How to recognise an app from the text visible on screen.
///
/// UI chrome (tab bars, composers, nav titles) is far more reliable than the
/// app's name appearing somewhere in the content, so chrome patterns carry most weight.
struct AppSignature: Sendable {
    /// Stable free-text id, also used as a tag and search filter (e.g. "instagram")
    let appID: String
    let displayName: String
    /// Curated category this app maps to, if any
    let category: ScreenshotCategory?
    /// Mentions of the app name anywhere (weak on their own)
    var names: [String] = []
    /// Detected URL hosts
    var hosts: [String] = []
    /// Distinctive phrases / chrome patterns with weights
    var phrases: [String: Double] = [:]
    var chrome: [RulePattern] = []
}

enum AppSignatures {
    static let all: [AppSignature] = messaging + social + productivity + entertainment + utility

    static let messaging: [AppSignature] = [
        AppSignature(appID: "imessage", displayName: "Messages", category: .messages,
                     names: ["imessage"],
                     phrases: ["delivered": 0.3, "read": 0.05],
                     chrome: [.zone(.bottomBar, anyOf: ["imessage", "text message", "text message sms", "rcs message"], weight: 0.92)]),
        AppSignature(appID: "whatsapp", displayName: "WhatsApp", category: .messages,
                     names: ["whatsapp"],
                     // Telegram says "last seen recently", WhatsApp "last seen today at …"
                     phrases: ["end-to-end encrypted": 0.5, "typing": 0.1, "online": 0.1, "last seen": 0.3,
                               "last seen today": 0.7, "last seen yesterday": 0.7, "tap here for group info": 0.8],
                     chrome: [.zoneAllOf(.bottomBar, ["chats", "calls"], weight: 0.75),
                              .zoneAllOf(.bottomBar, ["updates", "communities"], weight: 0.9)]),
        AppSignature(appID: "telegram", displayName: "Telegram", category: .messages,
                     names: ["telegram"],
                     phrases: ["subscribers": 0.2, "last seen recently": 0.85, "last seen within a week": 0.85,
                               "saved messages": 0.6],
                     chrome: [.zoneAllOf(.bottomBar, ["contacts", "chats", "settings"], weight: 0.85),
                              // A channel with a message composer (YouTube channels have subscribers, not a composer)
                              .allOf(["subscribers", "message"], weight: 0.6)]),
        AppSignature(appID: "signal", displayName: "Signal", category: .messages,
                     names: ["signal"],
                     phrases: ["safety number": 0.85, "disappearing messages": 0.6, "signal message": 0.9]),
        AppSignature(appID: "discord", displayName: "Discord", category: .messages,
                     names: ["discord"],
                     phrases: ["direct messages": 0.45, "nitro": 0.5, "server boost": 0.85, "add friend": 0.15,
                               "voice channel": 0.7, "text channels": 0.8]),
        AppSignature(appID: "slack", displayName: "Slack", category: .messages,
                     names: ["slack"],
                     phrases: ["huddle": 0.7, "threads": 0.1, "replies": 0.05, "unreads": 0.6],
                     chrome: [.zoneAllOf(.bottomBar, ["home", "dms", "activity"], weight: 0.92)]),
        AppSignature(appID: "gmail", displayName: "Gmail", category: .email,
                     names: ["gmail"],
                     phrases: ["promotions": 0.4, "primary": 0.15, "compose": 0.3, "search in mail": 0.85],
                     chrome: [.zoneAllOf(.bottomBar, ["mail", "meet"], weight: 0.85)]),
        AppSignature(appID: "mail", displayName: "Mail", category: .email,
                     phrases: ["all inboxes": 0.85, "mailboxes": 0.8, "sent from my iphone": 0.6, "reply all": 0.4]),
        AppSignature(appID: "outlook", displayName: "Outlook", category: .email,
                     names: ["outlook"],
                     phrases: ["focused": 0.2, "other": 0.02],
                     chrome: [.zoneAllOf(.topBar, ["focused", "other"], weight: 0.7)])
    ]

    static let social: [AppSignature] = [
        AppSignature(appID: "instagram", displayName: "Instagram", category: .instagram,
                     names: ["instagram"],
                     hosts: ["instagram.com"],
                     phrases: ["liked by": 0.8, "view all comments": 0.75, "add a comment": 0.45, "suggested for you": 0.35,
                               "reels": 0.35, "original audio": 0.55, "your story": 0.6, "follow back": 0.4,
                               "edit profile": 0.3, "share profile": 0.55,
                               // Stories: the reply bar, and the ad button over a sponsored story
                               "send message": 0.7, "expand story": 0.8],
                     // The real UI reads "View all 2,391 comments", so the phrase above rarely matches as-is
                     chrome: [.allOf(["view all", "comments"], weight: 0.75),
                              .zone(.topBar, anyOf: ["instagram"], weight: 0.75),
                              // A profile header (TikTok's says "Following · Followers · Likes", no "posts")
                              .allOf(["posts", "followers", "following"], weight: 0.8),
                              .allOf(["sponsored", "shop now"], weight: 0.6),
                              .allOf(["sponsored", "learn more"], weight: 0.6),
                              .allOf(["sponsored", "sign up"], weight: 0.6),
                              .allOf(["sponsored", "book now"], weight: 0.6)]),
        AppSignature(appID: "tiktok", displayName: "TikTok", category: .tiktok,
                     names: ["tiktok"],
                     hosts: ["tiktok.com"],
                     phrases: ["original sound": 0.6, "add comment": 0.3, "find related content": 0.85,
                               "people posted about this place": 0.85, "posts featured this place": 0.85,
                               "people added": 0.5, "repost to followers": 0.7, "find similar": 0.4],
                     // X also says "For you · Following"; these combinations are TikTok's alone
                     chrome: [.zoneAllOf(.topBar, ["following", "for you"], weight: 0.4),
                              .zoneAllOf(.bottomBar, ["friends", "inbox", "profile"], weight: 0.9),
                              .allOf(["following", "for you", "inbox"], weight: 0.85),
                              .allOf(["following", "for you", "shop"], weight: 0.8),
                              .allOf(["following", "for you", "friends"], weight: 0.8),
                              .allOf(["following", "for you", "explore"], weight: 0.8),
                              .allOf(["following", "for you", "stem"], weight: 0.85),
                              .allOf(["following", "followers", "likes"], weight: 0.6)]),
        AppSignature(appID: "x", displayName: "X", category: .twitter,
                     names: ["twitter"],
                     hosts: ["x.com", "twitter.com"],
                     // "Repost" alone is also a LinkedIn button
                     phrases: ["post your reply": 0.9, "reposts": 0.3, "retweets": 0.6, "quote": 0.15,
                               "show more replies": 0.5, "views": 0.1, "community notes": 0.7],
                     chrome: [.zoneAllOf(.topBar, ["following", "for you"], weight: 0.35), .handleCount(min: 2, weight: 0.3)]),
        AppSignature(appID: "threads", displayName: "Threads", category: .twitter,
                     names: ["threads"],
                     hosts: ["threads.net"],
                     phrases: ["start a thread": 0.85]),
        AppSignature(appID: "facebook", displayName: "Facebook", category: .facebook,
                     names: ["facebook"],
                     hosts: ["facebook.com"],
                     phrases: ["what's on your mind": 0.9, "marketplace": 0.4, "write a comment": 0.5],
                     chrome: [.allOf(["like", "comment", "share"], weight: 0.5)]),
        AppSignature(appID: "linkedin", displayName: "LinkedIn", category: .linkedin,
                     names: ["linkedin"],
                     hosts: ["linkedin.com"],
                     phrases: ["connections": 0.3, "endorse": 0.6, "open to work": 0.8, "1st": 0.15, "2nd": 0.15,
                               "easy apply": 0.8, "promoted": 0.1],
                     chrome: [.zoneAllOf(.bottomBar, ["my network", "jobs"], weight: 0.92)]),
        AppSignature(appID: "reddit", displayName: "Reddit", category: .reddit,
                     names: ["reddit"],
                     hosts: ["reddit.com"],
                     phrases: ["upvote": 0.6, "join": 0.05, "communities": 0.2, "award": 0.15],
                     chrome: [.subredditCount(min: 1, weight: 0.75)]),
        AppSignature(appID: "youtube", displayName: "YouTube", category: .youtube,
                     names: ["youtube"],
                     hosts: ["youtube.com", "youtu.be"],
                     phrases: ["subscribe": 0.4, "subscribers": 0.4, "shorts": 0.3],
                     chrome: [.zoneAllOf(.bottomBar, ["shorts", "subscriptions"], weight: 0.95)]),
        AppSignature(appID: "pinterest", displayName: "Pinterest", category: nil,
                     names: ["pinterest"],
                     hosts: ["pinterest.com", "pin.it"],
                     phrases: ["more ideas": 0.5])
    ]

    static let productivity: [AppSignature] = [
        AppSignature(appID: "chatgpt", displayName: "ChatGPT", category: .aiChats,
                     names: ["chatgpt"], hosts: ["chatgpt.com", "openai.com"],
                     phrases: ["message chatgpt": 0.95, "chatgpt can make mistakes": 0.95]),
        AppSignature(appID: "claude", displayName: "Claude", category: .aiChats,
                     hosts: ["claude.ai"],
                     phrases: ["reply to claude": 0.95, "claude can make mistakes": 0.95]),
        AppSignature(appID: "gemini", displayName: "Gemini", category: .aiChats,
                     hosts: ["gemini.google.com"],
                     phrases: ["ask gemini": 0.9]),
        AppSignature(appID: "notes", displayName: "Notes", category: .notes,
                     phrases: ["new note": 0.5, "shared folder": 0.2]),
        AppSignature(appID: "github", displayName: "GitHub", category: .programming,
                     names: ["github"], hosts: ["github.com"],
                     phrases: ["pull requests": 0.6, "open issues": 0.5]),
        AppSignature(appID: "settings", displayName: "Settings", category: .settings,
                     chrome: [.zone(.topBar, anyOf: ["settings"], weight: 0.6)])
    ]

    static let entertainment: [AppSignature] = [
        AppSignature(appID: "spotify", displayName: "Spotify", category: .music,
                     names: ["spotify"], hosts: ["open.spotify.com"],
                     phrases: ["liked songs": 0.85],
                     chrome: [.zoneAllOf(.bottomBar, ["home", "search", "your library"], weight: 0.85)]),
        AppSignature(appID: "applemusic", displayName: "Apple Music", category: .music,
                     phrases: ["apple music": 0.8],
                     chrome: [.zoneAllOf(.bottomBar, ["listen now", "radio", "library"], weight: 0.9)]),
        AppSignature(appID: "netflix", displayName: "Netflix", category: .movies,
                     names: ["netflix"], hosts: ["netflix.com"]),
        AppSignature(appID: "letterboxd", displayName: "Letterboxd", category: .movies,
                     names: ["letterboxd"], hosts: ["letterboxd.com"])
    ]

    static let utility: [AppSignature] = [
        // Most Maps screenshots are place cards (a restaurant, a shop); routes are recognised by the directions rules
        AppSignature(appID: "maps", displayName: "Maps", category: .places,
                     names: ["google maps"],
                     phrases: ["directions": 0.3, "start": 0.05, "go": 0.02],
                     chrome: [.allOf(["directions", "min"], weight: 0.5)]),
        AppSignature(appID: "amazon", displayName: "Amazon", category: .stores,
                     names: ["amazon"], hosts: ["amazon.com"],
                     phrases: ["buy now": 0.4, "add to cart": 0.4, "prime": 0.2]),
        AppSignature(appID: "uber", displayName: "Uber", category: nil,
                     names: ["uber"],
                     phrases: ["your driver": 0.6, "uberx": 0.9]),
        AppSignature(appID: "doordash", displayName: "DoorDash", category: .food,
                     names: ["doordash"], hosts: ["doordash.com"]),
        AppSignature(appID: "wallet", displayName: "Wallet", category: .tickets,
                     phrases: ["apple wallet": 0.6, "apple cash": 0.5]),
        AppSignature(appID: "safari", displayName: "Safari", category: nil,
                     chrome: [.zone(.bottomBar, anyOf: [".com", "www"], weight: 0.35)])
    ]
}
