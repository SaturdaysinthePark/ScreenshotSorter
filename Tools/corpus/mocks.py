"""Renders mock app screens (chats, receipts, passes, feeds…) as iPhone-sized screenshots.

Real screenshots of these apps can't be captured in the simulator, so each mock reproduces the
app's visible chrome and typical content. Labels describe what a person would file it under,
not what the rules look for.

    python3 Tools/corpus/mocks.py build/corpus     # writes mock/*.png + mock_manifest.json
"""
import json
import pathlib
import sys

OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/corpus")
ASSETS = (OUT / "assets").resolve()

BASE_CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { width: 402px; height: 874px; overflow: hidden; font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;
       background: var(--bg); color: var(--fg); font-size: 16px; }
:root { --bg: #fff; --fg: #111; --muted: #8a8a8e; --line: #e5e5ea; --card: #f2f2f7; }
.dark { --bg: #000; --fg: #f5f5f7; --muted: #8d8d93; --line: #2c2c2e; --card: #1c1c1e; }
.status { height: 54px; display: flex; justify-content: space-between; align-items: center; padding: 14px 34px 0 42px; font-weight: 600; font-size: 17px; }
.status .icons { font-size: 13px; letter-spacing: 2px; }
.nav { display: flex; align-items: center; justify-content: space-between; padding: 6px 16px 10px; border-bottom: 1px solid var(--line); }
.nav .title { font-weight: 600; font-size: 17px; text-align: center; }
.nav .sub { font-size: 12px; color: var(--muted); text-align: center; }
.back { color: #0a84ff; font-size: 17px; }
.tabbar { position: absolute; bottom: 0; left: 0; right: 0; height: 84px; display: flex; justify-content: space-around; padding-top: 8px;
          border-top: 1px solid var(--line); background: var(--bg); font-size: 10px; color: var(--muted); }
.tabbar div { text-align: center; } .tabbar .on { color: #0a84ff; }
.tabbar i { display: block; font-style: normal; font-size: 22px; margin-bottom: 2px; }
.composer { position: absolute; bottom: 30px; left: 10px; right: 10px; height: 38px; border: 1px solid var(--line); border-radius: 19px;
            padding: 9px 14px; color: var(--muted); font-size: 16px; background: var(--bg); }
.content { padding: 12px 16px; }
.bubble { max-width: 74%; padding: 8px 13px; border-radius: 18px; margin: 4px 0; font-size: 16px; line-height: 1.3; clear: both; }
.in { float: left; background: var(--card); } .out { float: right; color: #fff; }
.meta { clear: both; text-align: center; font-size: 11px; color: var(--muted); padding: 8px 0; }
.small { font-size: 12px; color: var(--muted); }
.row { display: flex; justify-content: space-between; padding: 6px 0; }
.card { background: var(--card); border-radius: 14px; padding: 14px; margin: 10px 0; }
.hr { border-top: 1px dashed var(--muted); margin: 10px 0; }
h1 { font-size: 30px; font-weight: 700; margin: 4px 0 10px; } h2 { font-size: 20px; margin: 8px 0; } h3 { font-size: 17px; margin: 6px 0; }
img.code { display: block; margin: 16px auto; image-rendering: pixelated; }
.avatar { width: 36px; height: 36px; border-radius: 18px; background: linear-gradient(135deg,#ffb347,#ff5f6d); display:inline-block; vertical-align: middle; margin-right: 8px; }
"""


def status(time="9:41"):
    return f'<div class="status"><span>{time}</span><span class="icons">▮▮▮ ᯤ ▭</span></div>'


def page(body, dark=False, extra_css="", time="9:41"):
    cls = "dark" if dark else ""
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{BASE_CSS}{extra_css}</style></head><body class='{cls}'>{status(time)}{body}</body></html>"


def tabbar(items, on=0):
    cells = "".join(f'<div class="{"on" if i == on else ""}"><i>●</i>{t}</div>' for i, t in enumerate(items))
    return f'<div class="tabbar">{cells}</div>'


def chat(messages, out_color):
    html = []
    for m in messages:
        if m[0] == "meta":
            html.append(f'<div class="meta">{m[1]}</div>')
        else:
            style = f' style="background:{out_color}"' if m[0] == "out" else ""
            html.append(f'<div class="bubble {m[0]}"{style}>{m[1]}</div>')
    return "".join(html)


MOCKS = []


def mock(name, expect, html, allow=()):
    MOCKS.append({"name": name, "expect": list(expect), "allow": list(allow), "html": html})


# ---------------------------------------------------------------- messaging
imessage_threads = [
    ("Mom", [("meta", "iMessage<br>Today 8:14 AM"), ("in", "Did you get home ok?"), ("out", "Yes! Just walked in"),
             ("in", "Good. Call me tomorrow about Thanksgiving"), ("out", "Will do ❤️"), ("meta", "Delivered")]),
    ("Jordan", [("meta", "iMessage<br>Yesterday 10:02 PM"), ("in", "are we still doing tacos thursday"), ("out", "yesss 7pm?"),
                ("in", "perfect. I'll grab a table at La Taqueria"), ("out", "🌮🌮🌮"), ("meta", "Read 10:05 PM")]),
    ("Alex Kim", [("meta", "Text Message • SMS<br>Today 3:41 PM"), ("in", "Your package is at the front desk btw"),
                  ("out", "omg thank you!!"), ("in", "np. also the landlord says rent goes up in Jan 😬"), ("meta", "Delivered")]),
    ("Book Club", [("meta", "iMessage<br>Sun, Oct 12 at 6:30 PM"), ("in", "Priya: Who's hosting next month?"), ("in", "Dan: I can! Nov 9?"),
                   ("out", "Works for me. What are we reading"), ("in", "Priya: Tomorrow, and Tomorrow, and Tomorrow"), ("meta", "Delivered")]),
]
for i, (who, msgs) in enumerate(imessage_threads):
    body = (f'<div class="nav"><span class="back">‹ 3</span><div><div class="avatar"></div><div class="title">{who} ›</div></div><span class="back">▷</span></div>'
            f'<div class="content">{chat(msgs, "#0a84ff")}</div><div class="composer">iMessage</div>')
    mock(f"imessage-{i}", ["imessage"], page(body, dark=i % 2 == 1), allow=["food"] if i == 1 else [])

whatsapp_threads = [
    ("Rahul Sharma", "online", [("meta", "TODAY"), ("in", "Bhai, flight lands at 6:40"), ("out", "I'll pick you up at arrivals"),
                                ("in", "👍 terminal 2"), ("out", "Ok see you")]),
    ("Family ❤️", "Mum, Dad, Ana, You", [("meta", "Messages and calls are end-to-end encrypted. No one outside of this chat, not even WhatsApp, can read or listen to them."),
                                        ("in", "Ana: Photos from the weekend coming"), ("in", "Dad: Beautiful!!"), ("out", "Miss you all")]),
    ("Carla", "last seen today at 11:52", [("meta", "YESTERDAY"), ("in", "Can you send me the address?"), ("out", "Calle de Alcalá 42, 3B"),
                                           ("in", "Gracias!"), ("meta", "TODAY"), ("in", "Llego en 10 min")]),
    ("Football Sunday ⚽", "Leo, Marco, Sam, You", [("in", "Leo: Pitch booked 10am"), ("in", "Marco: I'm in"), ("out", "in, bringing the ball"),
                                                   ("in", "Sam: who has the bibs")]),
]
for i, (who, sub, msgs) in enumerate(whatsapp_threads):
    body = (f'<div class="nav" style="background:var(--card)"><span class="back" style="color:#25d366">‹</span><div><div class="title">{who}</div><div class="sub">{sub}</div></div><span>📹 📞</span></div>'
            f'<div class="content" style="background:#efe7de;height:700px">{chat(msgs, "#d9fdd3;color:#111")}</div><div class="composer">Message</div>')
    mock(f"whatsapp-{i}", ["whatsapp"], page(body, dark=False), allow=["sports"] if i == 3 else [])
mock("whatsapp-list", ["whatsapp"], page(
    '<div class="content"><h1>Chats</h1><div class="card small">🔍 Ask Meta AI or Search</div>'
    + "".join(f'<div class="row" style="border-bottom:1px solid var(--line);padding:12px 0"><div><div class="avatar"></div><b>{n}</b><div class="small" style="margin-left:44px">{m}</div></div><span class="small">{t}</span></div>'
              for n, m, t in [("Rahul Sharma", "✓✓ Ok see you", "10:21"), ("Family ❤️", "Ana: 📷 Photo", "09:02"), ("Carla", "Llego en 10 min", "Yesterday"), ("Work crew", "Tim: standup moved", "Yesterday")])
    + '</div>' + tabbar(["Updates", "Calls", "Communities", "Chats", "Settings"], on=3)))

signal_threads = [
    ("Taylor", [("meta", "Disappearing messages set to 1 week"), ("in", "Here's the door code: 4417#"), ("out", "Got it, thanks"), ("meta", "Signal message")]),
    ("Sam", [("meta", "Your safety number with Sam has changed. Tap to verify."), ("in", "New phone, same me"), ("out", "lol ok verified"), ("meta", "Signal message")]),
    ("Climbing crew", [("in", "Ava: Gym at 6?"), ("in", "Ben: yes, bouldering"), ("out", "I'll be there"), ("meta", "Signal message")]),
]
for i, (who, msgs) in enumerate(signal_threads):
    body = (f'<div class="nav"><span class="back">‹</span><div class="title">{who}</div><span>📞</span></div>'
            f'<div class="content">{chat(msgs, "#2c6bed")}</div><div class="composer">Signal message</div>')
    mock(f"signal-{i}", ["signal"], page(body, dark=i == 1), allow=["exercise", "sports"] if i == 2 else [])

telegram = [
    ("Durov's Channel", "1 024 518 subscribers", [("in", "We just rolled out Stories for channels. Try them today."), ("in", "Also: 4x faster uploads on desktop."), ("meta", "👁 1.2M  •  12:30")]),
    ("Mia", "last seen recently", [("in", "Did you watch the match?"), ("out", "Yes!! what a finish"), ("in", "Penalties 😭")]),
    ("Crypto Signals 🚀", "48 213 subscribers", [("in", "BTC breaking 70k resistance. Watch the 4h close."), ("in", "ETH/BTC ratio at yearly low"), ("meta", "👁 31K  •  09:14")]),
]
for i, (who, sub, msgs) in enumerate(telegram):
    body = (f'<div class="nav"><span class="back">‹ Chats</span><div><div class="title">{who}</div><div class="sub">{sub}</div></div><div class="avatar"></div></div>'
            f'<div class="content" style="background:#d4e5c9;height:700px">{chat(msgs, "#e1ffc7;color:#111")}</div><div class="composer">Message</div>')
    mock(f"telegram-{i}", ["telegram"], page(body), allow=["finance"] if i == 2 else (["sports"] if i == 1 else []))
mock("telegram-list", ["telegram"], page(
    '<div class="content"><div class="row"><span class="back">Edit</span><b>Chats</b><span>✎</span></div><div class="card small">Search</div>'
    + "".join(f'<div class="row" style="padding:11px 0;border-bottom:1px solid var(--line)"><div><div class="avatar"></div><b>{n}</b><div class="small" style="margin-left:44px">{m}</div></div><span class="small">{t}</span></div>'
              for n, m, t in [("Mia", "Penalties 😭", "21:40"), ("Saved Messages", "flight confirmation.pdf", "18:02"), ("Durov's Channel", "We just rolled out Stories…", "12:30")])
    + '</div>' + tabbar(["Contacts", "Calls", "Chats", "Settings"], on=2), dark=True))

discord = [
    ("# general", "Pixel Pals", [("in", "<b>neonfox</b> anyone up for valorant tonight?"), ("in", "<b>kaiju</b> after 9 yeah"), ("in", "<b>moss</b> I'll hop in voice channel 2"), ("in", "<b>neonfox</b> bet")]),
    ("# announcements", "Indie Dev Hub", [("in", "<b>mod-bot</b> 🎉 We hit level 3 server boost! New emoji slots unlocked."), ("in", "<b>ana</b> game jam starts Friday, theme drops at 6pm UTC"), ("in", "<b>ana</b> text channels for teams are open")]),
    ("Direct Messages", "", [("in", "<b>kaiju</b> sent you a friend request"), ("in", "<b>moss</b> gg last night"), ("in", "<b>Nitro</b> Your free trial ends in 3 days")]),
]
for i, (chan, server, msgs) in enumerate(discord):
    body = (f'<div class="nav" style="background:#313338;color:#fff"><span>☰</span><div><div class="title">{chan}</div><div class="sub">{server}</div></div><span>👥</span></div>'
            f'<div class="content" style="background:#313338;color:#dbdee1;height:700px">' + "".join(f'<p style="margin:12px 0">{m[1]}</p>' for m in msgs) + '</div>'
            f'<div class="composer" style="background:#383a40;color:#949ba4;border:none">Message {chan}</div>')
    mock(f"discord-{i}", ["discord"], page(body, dark=True), allow=["videoGames"] if i == 0 else [])

slack = [
    ("# design-team", [("Priya Nair", "10:02 AM", "Pushed the new onboarding flows to Figma, feedback welcome 🙏"), ("Tom Becker", "10:15 AM", "Looks great. Can we huddle at 11?"), ("Priya Nair", "10:16 AM", "Yep, starting a huddle")]),
    ("# eng-oncall", [("PagerDuty", "2:14 AM", "🔴 Triggered: API latency p99 > 2s (prod-us-east)"), ("Mike Chen", "2:16 AM", "ack, looking"), ("Mike Chen", "2:31 AM", "Rolled back deploy 4821, resolved. 3 replies")]),
]
for i, (chan, msgs) in enumerate(slack):
    body = (f'<div class="nav" style="background:#3f0e40;color:#fff"><span>‹</span><div class="title">{chan}</div><span>🎧</span></div><div class="content">'
            + "".join(f'<div style="margin:12px 0"><div class="avatar"></div><b>{n}</b> <span class="small">{t}</span><div style="margin-left:44px">{m}</div></div>' for n, t, m in msgs)
            + f'</div><div class="composer">Message {chan}</div>')
    mock(f"slack-{i}", ["slack"], page(body), allow=["programming", "errors"] if i == 1 else [])
mock("slack-home", ["slack"], page(
    '<div class="content" style="background:#3f0e40;color:#fff;height:120px"><h2>Acme Inc ⌄</h2><div class="card" style="background:#5a2a5b">Jump to or search…</div></div><div class="content">'
    '<h3>Unreads</h3><p># design-team · 4 new</p><h3>Threads</h3><p>Tom replied to you</p><h3>Channels</h3><p># general</p><p># random</p><p># eng-oncall</p>'
    '<h3>Direct messages</h3><p>Priya Nair</p><p>Mike Chen</p></div>' + tabbar(["Home", "DMs", "Activity", "More"])))

emails = [
    ("Mailboxes", "Inbox", "Dana Whitfield", "Q4 planning offsite — agenda attached",
     "Hi team,<br><br>Attached is the agenda for next Thursday's offsite at the Ferry Building. Please review sections 2 and 3 before we meet.<br><br>Thanks,<br>Dana<br><br>Sent from my iPhone"),
    ("Inbox", "All Inboxes", "Landlord — Peter Gomez", "Re: Lease renewal",
     "Hi Sam,<br><br>Following up on the renewal. The new monthly amount starting January 1 would be $2,450. Let me know if you'd like to sign for 12 or 18 months.<br><br>Best,<br>Peter"),
    ("Inbox", "Mailboxes", "Coach Ramirez", "Practice moved to Saturday",
     "Parents — due to field maintenance, Thursday practice moves to Saturday 9:00 AM at Lincoln Park field 3. Bring water and shin guards.<br><br>Reply All with questions."),
]
for i, (back, _, frm, subject, text) in enumerate(emails):
    body = (f'<div class="nav"><span class="back">‹ {back}</span><span></span><span class="back">⌃ ⌄</span></div><div class="content">'
            f'<div class="row"><div><div class="avatar"></div><b>{frm}</b><div class="small" style="margin-left:44px">To: Sam Rivera</div></div><span class="small">9:12 AM</span></div>'
            f'<h2>{subject}</h2><p style="line-height:1.5">{text}</p></div>'
            '<div class="tabbar"><div>🗑</div><div>📁</div><div>↩︎</div><div>✎</div></div>')
    mock(f"mail-{i}", ["email"], page(body, dark=i == 1), allow=["documents", "events", "homes", "finance", "sports"])
mock("mail-list", ["email"], page(
    '<div class="content"><span class="back">‹ Mailboxes</span><h1>Inbox</h1>'
    + "".join(f'<div style="padding:9px 0;border-bottom:1px solid var(--line)"><div class="row"><b>{a}</b><span class="small">{t}</span></div><div>{s}</div><div class="small">{p}</div></div>'
              for a, t, s, p in [("Apple", "9:30 AM", "Your receipt from Apple", "Apple ID: sam@icloud.com · iCloud+ 200GB"),
                                 ("Dana Whitfield", "8:02 AM", "Q4 planning offsite", "Attached is the agenda for next…"),
                                 ("United Airlines", "Yesterday", "Your trip to New York", "Confirmation ABC123 · Depart Nov 14"),
                                 ("Nextdoor", "Yesterday", "Lost cat on Elm St", "Has anyone seen…")])
    + '<p class="small" style="text-align:center;margin-top:20px">Updated Just Now</p></div>'))

gmail = [
    ("Primary", [("Google", "Security alert", "New sign-in on Mac", "10:41 AM"), ("Chase", "Your statement is ready", "Account ending 4417", "9:03 AM"),
                 ("Lena Park", "Photos from Big Sur", "Uploaded 42 photos to the shared album", "Oct 18"), ("DoorDash", "Your order is on the way", "Arriving 7:25–7:35 PM", "Oct 18")]),
    ("Promotions", [("Nike", "Members get 25% off", "Ends tonight. Shop running shoes", "11:20 AM"), ("Airbnb", "Your next getaway", "Homes in Tulum from $112", "8:01 AM"),
                    ("Spotify", "Premium Family, 3 months free", "Limited time", "Oct 17")]),
]
for i, (tab, rows) in enumerate(gmail):
    body = ('<div class="content"><div class="card" style="border-radius:28px">☰  Search in mail <span style="float:right" class="avatar"></span></div>'
            f'<div class="small" style="margin:6px 0">{tab}</div>'
            + "".join(f'<div style="padding:9px 0"><div class="row"><b>{a}</b><span class="small">{t}</span></div><div>{s}</div><div class="small">{p}</div></div>' for a, s, p, t in rows)
            + '</div><div style="position:absolute;right:18px;bottom:110px;background:#c2e7ff;padding:16px 20px;border-radius:16px">✎ Compose</div>'
            + tabbar(["Mail", "Meet"]))
    mock(f"gmail-{i}", ["gmail"], page(body, dark=i == 1), allow=["email"])
mock("gmail-open", ["gmail"], page(
    '<div class="nav"><span class="back">←</span><span></span><span>🗑 ✉︎ ⋮</span></div><div class="content"><h2>Your order is on the way <span class="small">Inbox</span></h2>'
    '<div class="row"><b>DoorDash</b><span class="small">Oct 18</span></div><p>Your Dasher Miguel is heading to you with your order from Burma Superstar.</p>'
    '<div class="card">Estimated arrival 7:25–7:35 PM<br>2 items · Total $38.40</div></div>'), allow=["email", "orders", "food", "receipts"])

# ---------------------------------------------------------------- social
insta_posts = [
    ("natgeo", "Kenya · Maasai Mara", "linear-gradient(160deg,#d9a441,#7a4b1c)", "3,412,880 likes", "natgeo A lioness surveys the plains at dawn. Photo by @amivitale #wildlife #kenya", ["animals"]),
    ("bonappetit", "Brooklyn, New York", "linear-gradient(160deg,#f5c27a,#b3541e)", "48,102 likes", "bonappetit The crispiest smashed potatoes you will ever make. Recipe at link in bio #recipes", ["food", "recipes", "cooking"]),
    ("sam.travels", "Positano, Italy", "linear-gradient(180deg,#7ec8e3,#f6d6a8)", "1,204 likes", "sam.travels not coming home 🍋☀️ #amalficoast", ["beaches", "landscapes", "flights"]),
    ("hypebeast", "", "linear-gradient(160deg,#ddd,#888)", "92,551 likes", "hypebeast The latest New Balance 990v6 drops this Saturday. Thoughts? #sneakers", ["shoes"]),
]
for i, (user, loc, art, likes, caption, extra) in enumerate(insta_posts):
    body = ('<div class="row" style="padding:4px 16px"><b style="font-family:cursive;font-size:24px">Instagram</b><span>♡  ✈︎</span></div>'
            f'<div class="row" style="padding:6px 12px;justify-content:flex-start"><div class="avatar"></div><div><b>{user}</b><div class="small">{loc}</div></div></div>'
            f'<div style="height:402px;background:{art}"></div><div class="content"><div>♡  💬  ✈︎ <span style="float:right">🔖</span></div>'
            f'<b>{likes}</b><p>{caption}</p><p class="small">View all 2,391 comments</p></div>' + tabbar(["⌂", "🔍", "⊕", "▶︎", "◯"]))
    mock(f"instagram-{i}", ["instagram"], page(body, dark=i == 3), allow=extra)
mock("instagram-profile", ["instagram"], page(
    '<div class="row content"><b>sam.travels ⌄</b><span>⊕ ☰</span></div><div class="row content" style="justify-content:space-around"><div class="avatar" style="width:80px;height:80px"></div>'
    '<div><b>214</b><div class="small">posts</div></div><div><b>1,890</b><div class="small">followers</div></div><div><b>402</b><div class="small">following</div></div></div>'
    '<div class="content"><b>Sam Rivera</b><p>📍 SF · coffee, film cameras, long walks</p><div class="row"><div class="card" style="flex:1;text-align:center;margin-right:6px">Edit profile</div><div class="card" style="flex:1;text-align:center">Share profile</div></div></div>'
    '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:2px">' + "".join(f'<div style="height:134px;background:hsl({h},55%,60%)"></div>' for h in range(0, 360, 40)) + '</div>'))

tiktoks = [
    ("@chefjoey", "15-minute garlic butter noodles 🍜 you NEED this #easyrecipe #fyp", "♬ original sound - chefjoey", "1.2M", ["food", "recipes", "cooking"]),
    ("@gymwithkat", "leg day finisher, 3 rounds 🔥 #workout #fitness", "♬ Pump It - Black Eyed Peas", "384K", ["exercise", "health"]),
    ("@catsofnyc", "he heard the treat bag from 3 rooms away #cat #funny", "♬ Oh No - Kreepa", "2.8M", ["animals", "memes"]),
]
for i, (user, cap, sound, likes, extra) in enumerate(tiktoks):
    body = (f'<div style="position:absolute;inset:0;background:linear-gradient(170deg,hsl({i*90+20},40%,35%),#111)"></div>'
            '<div style="position:absolute;top:60px;width:100%;text-align:center;color:#fff;font-weight:600">Following  |  <u>For You</u>  🔍</div>'
            f'<div style="position:absolute;right:12px;bottom:200px;color:#fff;text-align:center;line-height:2.2">♥<br>{likes}<br>💬<br>8,812<br>🔖<br>51.2K<br>↪︎<br>Share</div>'
            f'<div style="position:absolute;left:14px;bottom:110px;width:300px;color:#fff"><b>{user}</b><p>{cap}</p><p>{sound}</p></div>'
            + tabbar(["Home", "Friends", "+", "Inbox", "Profile"]).replace('class="tabbar"', 'class="tabbar" style="background:#000;color:#fff"'))
    mock(f"tiktok-{i}", ["tiktok"], page(body, dark=True), allow=extra)

tweets = [
    ("Nate Silver", "@NateSilver538", "Polls are a snapshot, not a forecast. People keep forgetting this every single cycle.", "1.2K", "4.8K", "31K", []),
    ("NASA", "@NASA", "Liftoff! Europa Clipper begins its 1.8-billion-mile journey to Jupiter's icy moon. 🚀", "9.4K", "41K", "212K", ["news"]),
    ("dril", "@dril", "i will not be apologizing for my posts. i will however be deleting my account and making a new one", "14K", "88K", "402K", ["memes"]),
    ("Swift Language", "@SwiftLang", "Swift 6.2 is here: approachable concurrency, InlineArray, and faster builds. Read the release notes →", "312", "1.9K", "6.1K", ["programming", "news"]),
]
for i, (name, handle, text, rp, rt, likes, extra) in enumerate(tweets):
    body = ('<div class="row content"><div class="avatar"></div><b style="font-size:26px">𝕏</b><span>⚙︎</span></div><div class="row content small" style="justify-content:space-around"><b style="color:var(--fg)">For you</b><span>Following</span></div>'
            f'<div class="content" style="border-top:1px solid var(--line)"><div class="avatar"></div><b>{name}</b> <span class="small">{handle} · 2h</span>'
            f'<p style="margin:6px 0 10px 44px;line-height:1.4">{text}</p><div class="row small" style="margin-left:44px">💬 {rp}  🔁 {rt}  ♡ {likes}  📊 2.1M  ↥</div></div>'
            f'<div class="content" style="border-top:1px solid var(--line)"><div class="avatar"></div><b>Tech Brew</b> <span class="small">@techbrew · 4h</span><p style="margin-left:44px">The best keyboards of 2026, ranked</p></div>'
            + tabbar(["⌂", "🔍", "◯", "🔔", "✉︎"]))
    mock(f"twitter-{i}", ["twitter"], page(body, dark=i % 2 == 0), allow=extra)

fb = [
    ("Marisol Ortega", "Just now · 🌎", "We closed on our first house!!! 🏡 Thank you to everyone who helped us move this weekend ❤️", "Like  Comment  Share", ["homes"]),
    ("Sunset Valley Neighbors", "Group · 3h", "Lost dog near Oak & 5th. Brown lab mix, answers to Biscuit. Please call 415-555-0199 if seen 🙏", "212 comments", ["animals"]),
]
for i, (who, when, text, foot, extra) in enumerate(fb):
    body = ('<div class="row content"><b style="color:#0866ff;font-size:28px">facebook</b><span>⊕ 🔍 💬</span></div><div class="row content small" style="justify-content:space-around"><span>⌂</span><span>▶︎</span><span>👥</span><span>🏪</span><span>🔔</span><span>☰</span></div>'
            f'<div class="content" style="border-top:6px solid var(--card)"><div class="avatar"></div><b>{who}</b><div class="small" style="margin-left:44px">{when}</div><p style="margin:10px 0">{text}</p>'
            f'<div style="height:260px;background:linear-gradient(150deg,#9ad0ec,#f2d398);border-radius:6px"></div><div class="row small">👍❤️ 1.4K  ·  {foot}</div><div class="row"><span>👍 Like</span><span>💬 Comment</span><span>↪︎ Share</span></div></div>')
    mock(f"facebook-{i}", ["facebook"], page(body), allow=extra)

li = [
    ("Priya Nair", "Design Lead at Acme · 1st", "I'm thrilled to share that I'm starting a new position as Head of Design at Northwind! 🎉 Grateful to my mentors…", ["documents"]),
    ("Daniel Okafor", "Engineering Manager · 2nd", "Hiring! We're looking for 3 senior iOS engineers (Swift, SwiftUI) to join our Lisbon team. Remote-friendly. DM me.", ["programming"]),
]
for i, (who, title, text, extra) in enumerate(li):
    body = ('<div class="row content"><div class="avatar"></div><div class="card" style="flex:1;margin:0 10px">🔍 Search</div><span>💬</span></div>'
            f'<div class="content" style="border-top:6px solid var(--card)"><div class="avatar"></div><b>{who}</b><div class="small" style="margin-left:44px">{title} · 1d · 🌐</div>'
            f'<p style="margin:10px 0;line-height:1.4">{text} <span class="small">…see more</span></p><div class="row small">👏❤️ 842 · 96 comments · 12 reposts</div>'
            '<div class="row"><span>👍 Like</span><span>💬 Comment</span><span>🔁 Repost</span><span>➤ Send</span></div></div>'
            + tabbar(["Home", "My Network", "Post", "Notifications", "Jobs"]))
    mock(f"linkedin-{i}", ["linkedin"], page(body), allow=extra)

reddit = [
    ("r/AskReddit", "u/throwaway_8812 · 5h", "What's a skill that took you 10 minutes to learn but you use every day?", "⬆ 24.1k ⬇   💬 9.8k   ↪︎ Share", []),
    ("r/MechanicalKeyboards", "u/clackclack · 2h", "Finally finished my first build — Tofu65 with lubed Gateron yellows", "⬆ 3.2k ⬇   💬 214", ["electronics"]),
]
for i, (sub, by, title, foot, extra) in enumerate(reddit):
    body = (f'<div class="row content"><span>☰</span><b style="color:#ff4500">reddit</b><span>🔍 ◯</span></div><div class="content" style="border-top:1px solid var(--line)">'
            f'<b>{sub}</b> <span class="small">· {by}</span><h2>{title}</h2><div style="height:220px;background:var(--card);border-radius:12px"></div><p class="small" style="margin-top:8px">{foot}</p></div>'
            + tabbar(["Home", "Communities", "Create", "Chat", "Inbox"]))
    mock(f"reddit-{i}", ["reddit"], page(body, dark=i == 0), allow=extra)

# ---------------------------------------------------------------- commerce / money
def receipt(store, lines, total, extra_top="", tail=""):
    rows = "".join(f'<div class="row"><span>{a}</span><span>{b}</span></div>' for a, b in lines)
    return (f'<div class="content" style="font-family:Menlo,monospace;font-size:15px"><h2 style="text-align:center">{store}</h2>{extra_top}<div class="hr"></div>{rows}'
            f'<div class="hr"></div><div class="row"><b>TOTAL</b><b>{total}</b></div>{tail}</div>')

mock("receipt-grocery", ["receipts"], page(receipt("TRADER JOE'S #212", [("BANANAS ORGANIC", "$0.99"), ("GREEK YOGURT", "$4.49"), ("SOURDOUGH LOAF", "$3.99"), ("OAT MILK", "$3.79"), ("SUBTOTAL", "$13.26"), ("TAX", "$0.00")], "$13.26",
                                           "<p class='small' style='text-align:center'>3 Embarcadero Ctr, San Francisco CA<br>10/18/2026 5:42 PM</p>", "<p>VISA ****4417  APPROVED<br>AUTH 08812C</p><p style='text-align:center'>THANK YOU FOR SHOPPING</p>")), allow=["food", "finance"])
mock("receipt-restaurant", ["receipts"], page(receipt("Nopa", [("Table 14  Guests 2", ""), ("Flatbread", "$18.00"), ("Pork Chop", "$36.00"), ("Glass Rioja", "$15.00"), ("Subtotal", "$69.00"), ("Tax 8.625%", "$5.95"), ("Tip 20%", "$13.80")], "$88.75",
                                              "<p class='small' style='text-align:center'>560 Divisadero St · Server: Alex</p>", "<p>Mastercard ****0021</p><p>Signature ____________</p>")), allow=["food", "drinks", "finance"])
mock("receipt-apple", ["receipts"], page('<div class="content"><h1></h1><h2>Receipt</h2><p class="small">APPLE ACCOUNT sam@icloud.com · ORDER ID MV7K2LQ9X · DOCUMENT NO. 182736455</p><div class="card">'
                                          '<div class="row"><span>iCloud+ with 200 GB (Monthly)</span><span>$2.99</span></div><div class="row"><span>Apple Music Individual</span><span>$10.99</span></div></div>'
                                          '<div class="row"><span>Subtotal</span><span>$13.98</span></div><div class="row"><span>Tax</span><span>$1.21</span></div><div class="row"><b>TOTAL</b><b>$15.19</b></div><p class="small">Billed to Visa •••• 4417</p></div>'),
     allow=["finance", "email", "music"])
mock("receipt-uber", ["receipts"], page('<div class="content"><h1>Thanks for riding, Sam</h1><p class="small">Oct 18, 2026 · 11:48 PM</p><h1>$24.61</h1><div class="card">'
                                         '<div class="row"><span>Trip fare</span><span>$17.40</span></div><div class="row"><span>Booking fee</span><span>$3.21</span></div><div class="row"><span>Tip</span><span>$4.00</span></div></div>'
                                         '<p>🟢 1455 Market St</p><p>⬛ 2200 Mission St</p><p class="small">UberX · 3.1 mi · 14 min · Payment: Apple Pay</p></div>'), allow=["finance", "directions", "vehicles"])
mock("receipt-venmo", ["receipts", "finance"], page('<div class="content" style="text-align:center"><div class="avatar" style="width:64px;height:64px"></div><h2>Paid Jordan Lee</h2><h1>$42.50</h1><p>🌮 tacos + drinks</p>'
                                                    '<p class="small">Oct 16, 2026, 9:12 PM · Transaction ID 3998124471</p><div class="card">Payment method: Venmo balance</div></div>'), allow=["food"])

orders = [
    ("Arriving Thursday", "Order #112-7741203-8830144", "Shipped · UPS 1Z999AA10123456784", "Sony WH-1000XM5 Wireless Headphones", "$398.00", ["electronics", "receipts"]),
    ("Out for delivery", "Order #W1928374", "Track package · USPS 9400 1000 0000 0000 0000 00", "Allbirds Tree Runners — Size 10", "$98.00", ["shoes", "receipts"]),
    ("Order confirmed", "Order #IK-55120934", "Estimated delivery Nov 3–6 · FedEx Freight", "KIVIK Sofa, Tibbleby beige/grey", "$899.00", ["furniture", "receipts"]),
    ("Delivered", "Order #8823-11", "Delivered today at 2:14 PM · Left at front door", "Instant Pot Duo 6qt", "$89.99", ["cooking", "receipts"]),
]
for i, (state, num, track, item, price, extra) in enumerate(orders):
    body = (f'<div class="nav"><span class="back">‹ Your Orders</span><span></span><span></span></div><div class="content"><h1>{state}</h1><p class="small">{num}</p>'
            f'<div class="card"><b>{item}</b><p>Qty 1 · {price}</p></div><div class="card">🚚 {track}<br><span class="small">Shipping to Sam Rivera, 2200 Mission St, San Francisco CA 94110</span></div>'
            '<div class="row"><span>●──────●──────○</span></div><div class="row small"><span>Ordered</span><span>Shipped</span><span>Delivered</span></div>'
            '<div class="card" style="text-align:center">Track package</div></div>')
    mock(f"order-{i}", ["orders"], page(body, dark=i == 2), allow=extra)

mock("finance-bank", ["finance"], page('<div class="content"><h2>Good morning, Sam</h2><div class="card"><div class="small">Total Checking (...4417)</div><h1>$3,482.17</h1><div class="small">Available balance</div></div>'
                                       '<div class="card"><div class="small">Sapphire Preferred (...0021)</div><h2>$1,204.66</h2><div class="small">Current balance · Payment due Nov 3</div></div>'
                                       '<h3>Recent transactions</h3>' + "".join(f'<div class="row"><span>{a}</span><span>{b}</span></div>' for a, b in [("Trader Joe's", "-$13.26"), ("Payroll ACME INC", "+$2,915.00"), ("PG&E Autopay", "-$84.12"), ("Zelle to Jordan Lee", "-$40.00")])
                                       + '</div>' + tabbar(["Accounts", "Pay & Transfer", "Plan & Track", "Offers", "Explore"])), allow=["receipts"])
mock("finance-stocks", ["finance"], page('<div class="content"><h1>Stocks</h1><p class="small">October 20</p>' + "".join(
    f'<div class="row" style="padding:10px 0;border-bottom:1px solid var(--line)"><div><b>{t}</b><div class="small">{n}</div></div><span>{p}</span><span style="background:{c};color:#fff;border-radius:6px;padding:2px 8px">{d}</span></div>'
    for t, n, p, d, c in [("AAPL", "Apple Inc.", "231.40", "+1.12%", "#34c759"), ("NVDA", "NVIDIA Corporation", "138.07", "-2.31%", "#ff3b30"), ("TSLA", "Tesla, Inc.", "220.89", "+0.48%", "#34c759"), ("VOO", "Vanguard S&P 500 ETF", "534.12", "+0.66%", "#34c759"), ("BTC-USD", "Bitcoin USD", "68,912.00", "+3.02%", "#34c759")])
    + '</div>', dark=True), allow=["news"])
mock("finance-budget", ["finance"], page('<div class="content"><h1>October budget</h1><div class="card"><div class="row"><b>Spent</b><b>$2,184 of $3,000</b></div><div style="height:10px;background:#34c759;width:72%;border-radius:5px"></div></div>'
                                         + "".join(f'<div class="row"><span>{a}</span><span>{b}</span></div>' for a, b in [("🏠 Rent", "$1,650"), ("🍔 Dining out", "$212"), ("🛒 Groceries", "$188"), ("🚗 Transport", "$74"), ("📺 Subscriptions", "$60")])
                                         + '<p class="small">You\'re on track to save $816 this month.</p></div>'))
mock("finance-crypto", ["finance"], page('<div class="content"><h2>Portfolio</h2><h1>$12,840.55</h1><p style="color:#34c759">+$402.18 (3.23%) today</p><div style="height:180px;background:linear-gradient(0deg,#0a84ff22,transparent);border-bottom:2px solid #0a84ff"></div>'
                                         '<div class="row"><span>Bitcoin BTC</span><span>0.142 BTC</span></div><div class="row"><span>Ethereum ETH</span><span>1.85 ETH</span></div><div class="row"><span>Solana SOL</span><span>22.4 SOL</span></div>'
                                         '<div class="row"><div class="card" style="flex:1;text-align:center">Buy</div><div class="card" style="flex:1;text-align:center;margin-left:8px">Sell</div></div></div>', dark=True))

# ---------------------------------------------------------------- travel / tickets / codes
mock("boarding-united", ["tickets", "flights"], page(
    '<div class="content" style="background:#002244;color:#fff;border-radius:20px;margin:10px;height:760px"><div class="row"><b>UNITED</b><span>Boarding Pass</span></div>'
    '<div class="row" style="font-size:44px;font-weight:700"><span>SFO</span><span>✈︎</span><span>JFK</span></div><div class="row small" style="color:#ccd"><span>San Francisco</span><span>New York</span></div>'
    '<div class="row"><div>FLIGHT<br><b>UA 837</b></div><div>GATE<br><b>F12</b></div><div>SEAT<br><b>12A</b></div><div>GROUP<br><b>2</b></div></div>'
    '<div class="row"><div>BOARDING<br><b>7:45 AM</b></div><div>DEPARTS<br><b>8:20 AM</b></div><div>DATE<br><b>Nov 14</b></div></div><p>Passenger: SAM RIVERA · Confirmation ABC123</p>'
    f'<img class="code" src="file://{ASSETS}/aztec-boarding.png" width="220" style="background:#fff;padding:10px"></div>'), allow=["codes"])
mock("boarding-pdf417", ["tickets", "flights"], page(
    '<div class="content"><h2>ANA · All Nippon Airways</h2><div class="card"><div class="row" style="font-size:36px;font-weight:700"><span>LAX</span><span>→</span><span>HND</span></div>'
    '<p>NH 105 · Seat 47J · Zone 3 · Boarding 10:05</p><p>Passenger CHEN/LI · PNR XYZ789</p></div>'
    f'<img class="code" src="file://{ASSETS}/pdf417-boarding.png" width="340"><p class="small" style="text-align:center">Gate closes 20 minutes before departure</p></div>'), allow=["codes"])
mock("ticket-concert", ["tickets"], page(
    '<div class="content" style="background:linear-gradient(160deg,#5b21b6,#db2777);color:#fff;border-radius:22px;margin:10px;height:760px"><p>TICKETMASTER</p><h1>Phoebe Bridgers</h1><p>Reunion Tour 2026</p>'
    '<p>Sat, Nov 14 · 8:00 PM<br>Madison Square Garden, New York, NY</p><div class="row"><div>SEC<br><b>114</b></div><div>ROW<br><b>8</b></div><div>SEAT<br><b>3</b></div></div>'
    f'<img class="code" src="file://{ASSETS}/pdf417-ticket.png" width="320" style="background:#fff;padding:8px"><p style="text-align:center">Add to Apple Wallet</p></div>'), allow=["events", "music", "codes"])
mock("ticket-train", ["tickets", "flights"], page(
    '<div class="content"><h2>Amtrak</h2><div class="card"><div class="row" style="font-size:30px;font-weight:700"><span>NYP</span><span>→</span><span>BOS</span></div><p>Northeast Regional 171 · Coach Car 5 · Seat 22</p>'
    '<p>Depart 9:03 AM · Arrive 1:15 PM · Thu, Nov 19</p><p>Passenger: Sam Rivera · Reservation 8F2A1C</p></div>'
    f'<img class="code" src="file://{ASSETS}/aztec-train.png" width="230"></div>'), allow=["codes"])
mock("flight-itinerary", ["flights"], page(
    '<div class="content"><h1>Trip to Tokyo</h1><p class="small">Confirmation XYZ789 · 2 travelers</p>'
    + "".join(f'<div class="card"><div class="row"><b>{a}</b><span>{b}</span></div><div class="small">{c}</div></div>' for a, b, c in [
        ("LAX → HND", "Thu, Dec 4", "NH 105 · Departs 11:40 AM · Arrives 5:05 PM (+1) · 11h 25m nonstop"),
        ("Hotel Gracery Shinjuku", "Dec 5 – Dec 12", "Check-in 3:00 PM · 7 nights · Superior Twin"),
        ("HND → LAX", "Fri, Dec 12", "NH 106 · Departs 7:10 PM · Arrives 1:05 PM · 9h 55m nonstop")]) + '</div>'))
mock("flight-status", ["flights"], page(
    '<div class="content"><h2>Flight UA 837</h2><h1 style="color:#ff9f0a">Delayed 35 min</h1><div class="card"><div class="row"><b>SFO</b><b>JFK</b></div><div class="row small"><span>Departs 8:55 AM · Terminal 3 · Gate F12</span></div>'
    '<div class="row small"><span>Arrives 5:24 PM · Terminal 7 · Baggage claim 4</span></div></div><p class="small">Aircraft Boeing 777-200 · Inbound flight on time</p></div>', dark=True))
mock("qr-wifi", ["codes"], page('<div class="content" style="text-align:center"><h2>Cafe Lumen</h2><p>Scan to join Wi-Fi</p>'
                                 f'<img class="code" src="file://{ASSETS}/qr-wifi.png" width="280"><p class="small">Network: Cafe Lumen Guest · Password: latte2024</p></div>'))
mock("qr-menu", ["codes"], page('<div class="content" style="text-align:center;background:#1e293b;color:#fff;height:820px"><h1>Scan for menu</h1><p>Table 12</p>'
                                 f'<img class="code" src="file://{ASSETS}/qr-url.png" width="300" style="background:#fff;padding:12px"><p>Order and pay from your phone</p></div>', dark=True), allow=["food"])
mock("qr-venmo", ["codes"], page('<div class="content" style="text-align:center"><div class="avatar" style="width:72px;height:72px"></div><h2>@sam-rivera</h2><p>Scan to pay Sam</p>'
                                             f'<img class="code" src="file://{ASSETS}/qr-venmo.png" width="280"><div class="card">Share my code</div></div>'), allow=["finance"])
mock("qr-contact", ["codes"], page('<div class="content" style="text-align:center"><h2>My card</h2>'
                                    f'<img class="code" src="file://{ASSETS}/qr-vcard.png" width="290"><p>Sam Rivera<br>+1 415 555 0133</p></div>'), allow=["people"])

# ---------------------------------------------------------------- system screens
mock("notifications-lock", ["notifications"], page(
    '<div style="position:absolute;inset:0;background:linear-gradient(160deg,#1e3a8a,#9333ea)"></div><div style="position:relative;color:#fff;text-align:center"><p style="font-size:20px;margin-top:20px">Monday, October 20</p>'
    '<p style="font-size:96px;font-weight:700">9:41</p></div><div class="content" style="position:relative;margin-top:180px">'
    + "".join(f'<div class="card" style="background:rgba(255,255,255,.75);color:#111"><div class="row small" style="color:#333"><b>{a}</b><span>{t}</span></div><b>{h}</b><div>{b}</div></div>' for a, t, h, b in [
        ("MESSAGES", "now", "Jordan", "omw! 5 min"), ("DOORDASH", "2m ago", "Your order is on the way", "Miguel is heading to you"), ("CALENDAR", "9:30 AM", "Design review", "10:00 AM · Room 4B"), ("WEATHER", "8:02 AM", "Rain starting soon", "Light rain in the next hour")])
    + '</div>', dark=True))
mock("notifications-center", ["notifications"], page(
    '<div style="position:absolute;inset:0;background:#111"></div><div class="content" style="position:relative;color:#fff"><h2>Notification Center</h2>'
    + "".join(f'<div class="card" style="background:#2c2c2e"><div class="row small"><b>{a}</b><span>{t}</span></div><b>{h}</b><div>{b}</div></div>' for a, t, h, b in [
        ("SLACK", "12m ago", "#eng-oncall", "Mike: Rolled back deploy 4821"), ("CHASE", "1h ago", "Purchase alert", "$13.26 at Trader Joe's"), ("INSTAGRAM", "2h ago", "sam.travels", "liked your photo"), ("SCREEN TIME", "Yesterday", "Weekly report", "Your screen time was down 12%")])
    + '</div>', dark=True))
mock("notifications-banner", ["notifications"], page(
    '<div class="content"><div class="card" style="box-shadow:0 8px 30px #0003"><div class="row small"><b>📦 AMAZON</b><span>now</span></div><b>Delivered: Sony WH-1000XM5</b><div>Your package was left at the front door.</div></div>'
    '<h1 style="margin-top:40px">Today</h1><p class="small">Notification summary</p><div class="card">You have 14 notifications from 6 apps</div></div>'), allow=["orders"])

errors = [
    ("error-alert", '<div style="position:absolute;inset:0;background:#0006"></div><div class="card" style="position:absolute;top:300px;left:50px;right:50px;text-align:center;background:#f2f2f2;color:#111">'
                    '<b>Cannot Connect to Server</b><p>The operation couldn\'t be completed. (NSURLErrorDomain error -1004.)</p><div class="hr"></div><b style="color:#0a84ff">OK</b></div>', False),
    ("error-404", '<div class="content" style="text-align:center;margin-top:120px"><h1 style="font-size:80px">404</h1><h2>Page not found</h2><p>The page you\'re looking for doesn\'t exist or has been moved.</p><div class="card">Go back home</div></div>', False),
    ("error-crash", '<div class="content" style="font-family:Menlo,monospace;font-size:12px;background:#1e1e1e;color:#f48771;height:820px"><p>Thread 1: Fatal error: Unexpectedly found nil while implicitly unwrapping an Optional value</p>'
                    '<p style="color:#ccc">0  libswiftCore.dylib  _assertionFailure(_:_:file:line:flags:) + 244<br>1  MyApp  ProfileViewController.viewDidLoad() + 412<br>2  UIKitCore  -[UIViewController loadViewIfRequired] + 936<br>3  UIKitCore  -[UIViewController view] + 28</p>'
                    '<p style="color:#ccc">Exception Type: EXC_BREAKPOINT (SIGTRAP)<br>Crashed Thread: 0</p></div>', True),
    ("error-app", '<div class="content" style="text-align:center;margin-top:160px"><h1>⚠️</h1><h2>Something went wrong</h2><p>We couldn\'t load your feed. Please check your connection and try again.</p><p class="small">Error code: 503 Service Unavailable</p><div class="card" style="color:#0a84ff">Try Again</div></div>', False),
]
for name, body, dark in errors:
    mock(name, ["errors"], page(body, dark=dark), allow=["programming"])

mock("notes-groceries", ["notes"], page('<div class="nav"><span class="back" style="color:#e0a800">‹ Notes</span><span></span><span style="color:#e0a800">⋯</span></div><div class="content"><h1>Groceries</h1>'
                                        + "".join(f'<p style="margin:8px 0">◯ {x}</p>' for x in ["eggs", "spinach", "parmesan", "lemons", "olive oil", "coffee beans", "paper towels"]) + '</div>'), allow=["food"])
mock("notes-ideas", ["notes"], page('<div class="nav"><span class="back" style="color:#e0a800">‹ Folders</span><span></span><span style="color:#e0a800">Done</span></div><div class="content"><h1>App ideas</h1><p class="small">October 12, 2026 at 11:02 PM</p>'
                                    '<p>• a plant watering tracker that uses the weather<br>• shared grocery list with price history<br>• screenshot sorter that actually reads the text 👀</p><h3>Name ideas</h3><p>Sprout, Leafy, Thirsty</p></div>', dark=True), allow=["plants"])
mock("notes-meeting", ["notes"], page('<div class="nav"><span class="back" style="color:#e0a800">‹ Notes</span><span></span><span style="color:#e0a800">⋯</span></div><div class="content"><h1>1:1 with Dana</h1><p class="small">Oct 20, 2026</p>'
                                      '<h3>Action items</h3><p>☑︎ send Q4 roadmap draft<br>☐ book offsite venue<br>☐ intro to Priya re: hiring</p><h3>Notes</h3><p>Dana wants weekly metrics in the Monday update. Revisit headcount in November.</p></div>'), allow=["documents"])

mock("doc-pdf", ["documents"], page('<div class="nav"><span class="back">Done</span><div class="title">Lease_Agreement_2026.pdf</div><span>⤴︎</span></div><div class="content" style="background:#ddd;height:780px"><div style="background:#fff;color:#111;padding:20px;font-family:Georgia,serif;font-size:12px;line-height:1.5">'
                                    '<h3 style="text-align:center">RESIDENTIAL LEASE AGREEMENT</h3><p>This Lease Agreement ("Agreement") is entered into on October 1, 2026, by and between Peter Gomez ("Landlord") and Sam Rivera ("Tenant").</p>'
                                    '<p>1. PREMISES. Landlord leases to Tenant the premises located at 2200 Mission St, Apt 3, San Francisco, CA 94110.</p><p>2. TERM. The term of this Agreement shall commence on January 1, 2027 and end on December 31, 2027.</p>'
                                    '<p>3. RENT. Tenant shall pay monthly rent of $2,450.00 due on the first day of each month.</p><p>4. SECURITY DEPOSIT. Upon execution, Tenant shall deposit $4,900.00.</p><p class="small">Page 1 of 6</p></div></div>'), allow=["homes", "finance"])
mock("doc-scan", ["documents"], page('<div class="content" style="background:#f7f4ea;height:820px;font-family:Georgia,serif;color:#222"><p style="text-align:right">Invoice #2026-0412</p><h2>Rivera Design Studio</h2><p>Bill to: Northwind Traders, 400 Pine St, Seattle WA</p>'
                                     '<div class="row"><span>Brand identity — phase 2</span><span>$4,800.00</span></div><div class="row"><span>Website design (24 hrs @ $150)</span><span>$3,600.00</span></div><div class="hr"></div><div class="row"><b>Amount due</b><b>$8,400.00</b></div>'
                                     '<p>Payment terms: Net 30. Please remit to account ending 7712.</p></div>'), allow=["receipts", "finance"])
mock("doc-form", ["documents"], page('<div class="content" style="font-family:Arial;font-size:13px"><h3>Form W-9 (Rev. March 2024)</h3><p><b>Request for Taxpayer Identification Number and Certification</b></p>'
                                     '<p>1 Name of entity/individual: Sam Rivera</p><p>2 Business name/disregarded entity name, if different from above</p><p>3a Check the appropriate box for federal tax classification: ☑ Individual/sole proprietor</p>'
                                     '<p>5 Address (number, street, and apt. or suite no.): 2200 Mission St Apt 3</p><p>Part I Taxpayer Identification Number (TIN)</p><p>Part II Certification — Under penalties of perjury, I certify that…</p></div>'), allow=["finance"])

quotes = [("“The best time to plant a tree was 20 years ago. The second best time is now.”", "— Chinese proverb", "#14532d"),
          ("“Be yourself; everyone else is already taken.”", "— Oscar Wilde", "#7c2d12"),
          ("“We suffer more often in imagination than in reality.”", "— Seneca", "#1e1b4b")]
for i, (q, who, bg) in enumerate(quotes):
    mock(f"quote-{i}", ["quotes"], page(f'<div style="position:absolute;inset:0;background:{bg};color:#fff;display:flex;flex-direction:column;justify-content:center;padding:40px;text-align:center">'
                                        f'<p style="font-family:Georgia,serif;font-size:30px;line-height:1.35">{q}</p><p style="margin-top:20px;font-size:18px">{who}</p></div>', dark=True))

memes = [("WHEN THE CODE WORKS", "AND YOU DON'T KNOW WHY", "#666", ["programming"]),
         ("ONE DOES NOT SIMPLY", "WAKE UP BEFORE 9 ON A SATURDAY", "#4b5563", []),
         ("ME: I'LL JUST CHECK ONE THING", "ALSO ME, 3 HOURS LATER:", "#7c3aed", [])]
for i, (top, bottom, bg, extra) in enumerate(memes):
    mock(f"meme-{i}", ["memes"], page(f'<div style="position:absolute;top:160px;left:0;right:0;height:500px;background:linear-gradient(135deg,{bg},#222)"></div>'
                                       f'<div style="position:absolute;top:180px;width:100%;text-align:center;color:#fff;font:900 34px Impact,sans-serif;-webkit-text-stroke:1.5px #000">{top}</div>'
                                       f'<div style="position:absolute;top:590px;width:100%;text-align:center;color:#fff;font:900 34px Impact,sans-serif;-webkit-text-stroke:1.5px #000">{bottom}</div>'
                                       '<div class="content" style="position:absolute;top:680px"><p class="small">👍 4.2K · 💬 318 · ↪︎ Share</p></div>'), allow=extra + ["reddit", "instagram", "twitter"])

events = [("invite", '<div class="content"><h1>Mia\'s 30th 🎉</h1><p>Saturday, November 8 · 7:00 PM – 11:00 PM</p><p>📍 The Riddler, 528 Laguna St, San Francisco</p><div class="card">Hosted by Mia Chen · 24 going · 6 maybe</div>'
                          '<div class="row"><div class="card" style="flex:1;text-align:center">✓ Going</div><div class="card" style="flex:1;text-align:center;margin:10px 6px">? Maybe</div><div class="card" style="flex:1;text-align:center">✕ Can\'t go</div></div></div>'),
          ("calendar", '<div class="content"><span class="back" style="color:#ff3b30">‹ October</span><h1>Thu, Oct 23</h1>'
                       + "".join(f'<div class="card" style="border-left:4px solid {c}"><b>{t}</b><div class="small">{w}</div></div>' for t, w, c in [("Design review", "10:00 – 11:00 AM · Room 4B", "#0a84ff"), ("Lunch with Jordan", "12:30 – 1:30 PM · Tartine", "#34c759"), ("Dentist", "4:15 – 5:00 PM", "#ff9f0a")]) + '</div>'),
          ("eventbrite", '<div class="content"><div style="height:200px;background:linear-gradient(120deg,#f97316,#ec4899);border-radius:12px"></div><p class="small">SAT, NOV 15 · 10:00 AM PST</p><h1>SF Climate Tech Meetup</h1><p>📍 Shack15, Ferry Building</p><p>Free · 212 attending</p><div class="card" style="background:#d1410c;color:#fff;text-align:center">Reserve a spot</div></div>'),
          ("save-the-date", '<div style="position:absolute;inset:0;background:#f5efe6;color:#3b2f2f;text-align:center;padding-top:200px;font-family:Georgia,serif"><p>SAVE THE DATE</p><h1 style="font-size:42px">Ana &amp; Luis</h1><p>June 13, 2027</p><p>Napa Valley, California</p><p style="margin-top:30px">Formal invitation to follow</p></div>')]
for name, body in events:
    mock(f"event-{name}", ["events"], page(body), allow=["notes"])

mock("health-summary", ["health"], page('<div class="content"><h1>Summary</h1><h3>Pinned</h3>'
                                        + "".join(f'<div class="card"><div class="row small"><b style="color:{c}">{a}</b><span>{t}</span></div><h2>{v}</h2></div>' for a, t, v, c in [
                                            ("🔥 Activity", "9:41 AM", "Move 412/600 cal · Exercise 22/30 min", "#ff2d55"), ("👣 Steps", "9:30 AM", "6,241 steps", "#ff9500"), ("❤️ Heart Rate", "9:12 AM", "64 BPM resting", "#ff3b30"), ("🛏 Sleep", "7:02 AM", "7 hr 18 min", "#5e5ce6")])
                                        + '</div>' + tabbar(["Summary", "Sharing", "Browse"])), allow=["exercise"])
mock("health-workout", ["exercise", "health"], page('<div class="content" style="color:#a3e635"><h2 style="color:#fff">Outdoor Run</h2><p class="small">Today 7:02–7:48 AM · Golden Gate Park</p>'
                                                    + "".join(f'<div class="row" style="color:#fff"><span>{a}</span><b style="color:#a3e635">{b}</b></div>' for a, b in [("Workout Time", "0:46:12"), ("Distance", "5.42 MI"), ("Avg. Pace", "8\'31\"/MI"), ("Active Kilocalories", "512 CAL"), ("Avg. Heart Rate", "152 BPM"), ("Elevation Gain", "214 FT")])
                                                    + '</div>', dark=True), allow=["sports"])
mock("exercise-plan", ["exercise"], page('<div class="content"><h1>Leg day 🦵</h1><p class="small">Week 3 · Day 2 · 50 min</p>' + "".join(
    f'<div class="card"><b>{a}</b><div class="small">{b}</div></div>' for a, b in [("Back squat", "4 sets × 6 reps · 185 lb"), ("Romanian deadlift", "3 × 8 · 135 lb"), ("Walking lunges", "3 × 12 each leg"), ("Leg press", "3 × 10 · 270 lb"), ("Calf raises", "4 × 15")]) + '</div>'), allow=["health", "sports"])
mock("health-meds", ["health"], page('<div class="content"><h1>Medications</h1><div class="card"><b>Lisinopril 10 mg</b><div class="small">1 tablet · 8:00 AM · Taken ✓</div></div><div class="card"><b>Vitamin D3 2000 IU</b><div class="small">1 capsule · with breakfast</div></div>'
                                     '<h3>Appointments</h3><div class="card">Dr. Patel — Annual physical<br><span class="small">Tue, Nov 4 at 9:30 AM · One Medical, 1 Embarcadero</span></div></div>'), allow=["events"])

mock("weather-app", ["weather"], page('<div style="position:absolute;inset:0;background:linear-gradient(#4a90d9,#a7c7e7)"></div><div style="position:relative;color:#fff;text-align:center"><p style="font-size:32px;margin-top:30px">San Francisco</p>'
                                      '<p style="font-size:96px;font-weight:200">62°</p><p>Partly Cloudy<br>H:66° L:54°</p></div><div class="card" style="position:relative;margin:20px;background:#ffffff33;color:#fff">'
                                      'Cloudy conditions expected around 4PM. Wind gusts are up to 18 mph.<div class="row">' + "".join(f'<div style="text-align:center">{h}<br>☁︎<br>{t}°</div>' for h, t in [("Now", 62), ("1PM", 64), ("2PM", 65), ("3PM", 66), ("4PM", 63), ("5PM", 61)])
                                      + '</div></div><div class="card" style="position:relative;margin:20px;background:#ffffff33;color:#fff">10-DAY FORECAST<div class="row"><span>Today</span><span>54° ━━━ 66°</span></div><div class="row"><span>Tue</span><span>☂︎ 52° ━━ 60°</span></div><div class="row"><span>Wed</span><span>53° ━━━ 63°</span></div></div>', dark=True))
mock("weather-alert", ["weather"], page('<div class="content"><h2>⚠️ Heat Advisory</h2><p class="small">National Weather Service · Until 8:00 PM PDT</p><p>Temperatures up to 104°F expected. Drink plenty of fluids, stay in an air-conditioned room, stay out of the sun.</p>'
                                        '<div class="card"><div class="row"><span>Feels like</span><b>107°</b></div><div class="row"><span>UV index</span><b>10 Extreme</b></div><div class="row"><span>Humidity</span><b>22%</b></div></div></div>'), allow=["news", "notifications"])

mock("music-nowplaying", ["music"], page('<div style="position:absolute;inset:0;background:linear-gradient(#7c2d12,#111)"></div><div style="position:relative;color:#fff;padding:30px"><div style="height:330px;background:linear-gradient(135deg,#fb923c,#be123c);border-radius:12px"></div>'
                                         '<h2>Motion Sickness</h2><p>Phoebe Bridgers — Stranger in the Alps</p><div style="height:4px;background:#fff8;margin:16px 0"></div><div class="row small" style="color:#ddd"><span>1:12</span><span>-2:37</span></div>'
                                         '<p style="text-align:center;font-size:40px">⏮ ⏸ ⏭</p><p class="small" style="text-align:center;color:#ddd">AirPods Pro · Lyrics · Up Next</p></div>', dark=True))
mock("music-playlist", ["music"], page('<div class="content" style="background:linear-gradient(#065f46,#000 50%);color:#fff;height:820px"><div style="height:220px;width:220px;margin:10px auto;background:linear-gradient(135deg,#34d399,#1e3a8a)"></div><h2>Discover Weekly</h2><p class="small">Made for Sam · 30 songs, 2 hr 4 min</p>'
                                       + "".join(f'<div style="margin:10px 0"><b>{a}</b><div class="small">{b}</div></div>' for a, b in [("Kyoto", "Phoebe Bridgers"), ("Sofia", "Clairo"), ("Ivy", "Frank Ocean"), ("Ribs", "Lorde"), ("Motion Sickness", "Phoebe Bridgers")])
                                       + '</div>' + tabbar(["Home", "Search", "Your Library", "Premium"]).replace('class="tabbar"', 'class="tabbar" style="background:#000;color:#aaa"'), dark=True))
mock("music-concerts", ["music"], page('<div class="content"><h1>Concerts near you</h1>' + "".join(
    f'<div class="card"><b>{a}</b><div class="small">{b}</div></div>' for a, b in [("Phoebe Bridgers", "Nov 14 · Madison Square Garden"), ("Fred again..", "Nov 21 · Brooklyn Mirage"), ("Laufey", "Dec 2 · Radio City Music Hall")]) + '</div>'), allow=["events", "tickets"])

mock("reading-article", ["reading"], page('<div class="content" style="font-family:Georgia,serif;font-size:18px;line-height:1.6"><p class="small">THE ATLANTIC · 14 MIN READ</p><h2 style="font-family:Georgia">The Case for Boredom</h2>'
                                          '<p>For most of human history, idle moments were simply part of life. You waited for the bus, for the kettle, for the doctor. Now every gap is filled by a feed. Researchers who study attention argue that this has a cost, one we are only beginning to measure.</p>'
                                          '<p>In one study, participants left alone with their thoughts for fifteen minutes chose to give themselves mild electric shocks rather than sit quietly…</p></div>'), allow=["news", "books"])
mock("reading-kindle", ["reading"], page('<div class="content" style="background:#f8f1e3;color:#3b2f2f;font-family:Georgia,serif;font-size:19px;line-height:1.6;height:820px"><p class="small" style="text-align:center">Chapter 3</p>'
                                                  '<p>It was a bright cold day in April, and the clocks were striking thirteen. Winston Smith, his chin nuzzled into his breast in an effort to escape the vile wind, slipped quickly through the glass doors of Victory Mansions…</p>'
                                                  '<p class="small" style="text-align:center;margin-top:40px">Location 412 of 5210 · 8%</p></div>'), allow=["books"])
mock("books-goodreads", ["books"], page('<div class="content"><div class="row" style="justify-content:flex-start"><div style="width:110px;height:165px;background:linear-gradient(#0f766e,#134e4a);margin-right:14px"></div><div><h2>Tomorrow, and Tomorrow, and Tomorrow</h2><p>Gabrielle Zevin</p><p>★★★★☆ 4.17 · 1,102,449 ratings</p></div></div>'
                                        '<div class="card" style="text-align:center;background:#409d69;color:#fff">Want to Read</div><p>On a bitter-cold day, in the December of his junior year at Harvard, Sam Masur exits a subway car and sees, amid the hordes of people waiting on the platform, Sadie Green…</p><p class="small">Genres: Fiction · Contemporary · Video Games</p></div>'), allow=["reading", "videoGames"])

mock("movies-watchlist", ["movies"], page('<div class="content" style="background:#14181c;color:#ddd;height:820px"><h2>Watchlist</h2>' + "".join(
    f'<div class="row" style="justify-content:flex-start"><div style="width:70px;height:104px;background:hsl({h},40%,40%);margin:6px 12px 6px 0"></div><div><b>{a}</b><div class="small">{b}</div></div></div>'
    for h, a, b in [(10, "Dune: Part Two", "2024 · Denis Villeneuve · 2h 46m"), (200, "Past Lives", "2023 · Celine Song · 1h 46m"), (300, "The Bear — Season 3", "TV · FX · 10 episodes"), (50, "Oppenheimer", "2023 · Christopher Nolan")]) + '</div>', dark=True))
mock("movies-streaming", ["movies"], page('<div style="height:420px;background:linear-gradient(#0000,#000),linear-gradient(120deg,#7f1d1d,#1e3a8a)"></div><div class="content" style="background:#000;color:#fff;height:420px"><h1>Severance</h1><p class="small">2025 · TV-MA · 2 Seasons · Drama · Sci-Fi</p>'
                                          '<div class="card" style="background:#fff;color:#000;text-align:center">▶︎ Play S2 E4</div><p>Mark leads a team of office workers whose memories have been surgically divided between their work and personal lives.</p><p class="small">Episodes · More Like This · Trailers</p></div>', dark=True))
mock("games-store", ["videoGames"], page('<div class="content" style="background:#1b2838;color:#c7d5e0;height:820px"><div style="height:200px;background:linear-gradient(120deg,#0ea5e9,#7c3aed)"></div><h2>Hades II</h2><p>Supergiant Games · Action Roguelike</p><p>Overwhelmingly Positive (48,102 reviews)</p>'
                                         '<div class="card" style="background:#4c6b22;color:#fff">Buy Hades II — $29.99 · Add to Cart</div><p class="small">Platforms: Windows, macOS · Controller support · Steam Deck Verified</p></div>', dark=True))
mock("games-achievement", ["videoGames"], page('<div style="position:absolute;inset:0;background:radial-gradient(#1d4ed8,#0b1220)"></div><div class="card" style="position:relative;margin:300px 30px 0;background:#111c;color:#fff;text-align:center">🏆<h2>Trophy Unlocked</h2><p>Elden Ring — "Elden Lord"<br>Ultra Rare · 18.2% of players</p></div>'
                                               '<p style="position:relative;color:#fff;text-align:center;margin-top:30px">PlayStation 5 · Level 214</p>', dark=True))
mock("sports-score", ["sports"], page('<div class="content"><h2>NBA · Final</h2><div class="card"><div class="row" style="font-size:28px"><b>GSW</b><b>118</b></div><div class="row" style="font-size:28px"><b>LAL</b><b>112</b></div>'
                                      '<p class="small">Curry 38 PTS · 9 3PM · James 31 PTS, 11 REB</p></div><h3>Box score</h3><div class="row small"><span>Q1 30-28</span><span>Q2 27-31</span><span>Q3 33-24</span><span>Q4 28-29</span></div>'
                                      '<h3>Up next</h3><p>GSW vs DEN · Wed 7:30 PM · TNT</p></div>'))
mock("sports-fantasy", ["sports"], page('<div class="content"><h1>Week 7 matchup</h1><div class="row"><b>Sam\'s Squad 104.2</b><b>88.6 Gridiron Gurus</b></div>' + "".join(
    f'<div class="row"><span>{a}</span><span>{b}</span></div>' for a, b in [("QB  J. Allen BUF", "24.8"), ("RB  C. McCaffrey SF", "21.4"), ("WR  J. Chase CIN", "18.1"), ("TE  T. Kelce KC", "9.2"), ("K  J. Tucker BAL", "8.0")]) + '<p class="small">Projected win probability 81%</p></div>', dark=True))

# ---------------------------------------------------------------- shopping product pages
products = [
    ("watch", "Apple Watch Series 11", "From $399", "Aluminum case · Sport Band · GPS + Cellular", ["watches", "stores", "electronics"], ["watches"]),
    ("bag", "Leather Weekender Bag", "$248", "Full-grain leather · fits 3 days of packing · Cognac", ["bags", "stores"], ["bags"]),
    ("jewelry", "Diamond Tennis Bracelet", "$1,890", "14k white gold · 2.0 ctw lab-grown diamonds", ["jewelry", "stores"], ["jewelry"]),
    ("dress", "Linen Midi Dress", "$128", "100% European linen · Sizes XS–XL · Sage", ["clothes", "stores"], ["clothes"]),
    ("sneakers", "Air Max 90", "$130", "Men's Shoes · 5 colors · Free delivery", ["shoes", "stores"], ["shoes"]),
    ("sofa", "Mid-century 3-seat sofa", "$1,299", "Walnut legs · performance velvet · ships in 2–3 weeks", ["furniture", "stores", "homes"], ["furniture"]),
    ("laptop", "MacBook Air 13-inch M4", "$999", "16GB unified memory · 256GB SSD · Midnight", ["electronics", "stores"], ["electronics"]),
]
for name, title, price, detail, allow, expect in products:
    body = (f'<div class="content"><div class="card small">🔍 Search</div><div style="height:360px;background:linear-gradient(135deg,#e5e7eb,#9ca3af);border-radius:12px"></div>'
            f'<h2>{title}</h2><h2>{price}</h2><p>{detail}</p><p class="small">★★★★½ 2,184 reviews · In stock · Free returns</p>'
            '<div class="card" style="background:#111;color:#fff;text-align:center">Add to Bag</div><div class="card" style="text-align:center">♡ Favorite</div></div>')
    mock(f"product-{name}", expect, page(body), allow=allow)

mock("homes-listing", ["homes"], page('<div style="height:300px;background:linear-gradient(135deg,#a3b18a,#588157)"></div><div class="content"><h1>$1,249,000</h1><p><b>3</b> bd · <b>2</b> ba · <b>1,680</b> sqft</p><p>412 Elm St, Oakland, CA 94610</p>'
                                      '<p class="small">Single family residence · Built 1926 · Lot 4,800 sqft · HOA none</p><p>Est. payment $7,412/mo · Open house Sun 1–4 PM</p><div class="card" style="background:#006aff;color:#fff;text-align:center">Request a tour</div></div>'), allow=["finance"])
mock("homes-rental", ["homes"], page('<div style="height:300px;background:linear-gradient(135deg,#e9c46a,#e76f51)"></div><div class="content"><h2>Sunny 1BR near Dolores Park</h2><p>$3,150/month · Available Dec 1</p><p>1 bed · 1 bath · 640 sqft · in-unit laundry · pets ok</p>'
                                     '<p class="small">Mission District, San Francisco · Listed 2 days ago</p><div class="card">Message landlord</div></div>'))
mock("places-yelp", ["places"], page('<div style="height:240px;background:linear-gradient(135deg,#78350f,#f59e0b)"></div><div class="content"><h1>Tartine Bakery</h1><p>★★★★½ 9,812 reviews · $$ · Bakeries, Cafes</p><p style="color:#34c759">Open until 5:00 PM</p>'
                                     '<p>600 Guerrero St, San Francisco, CA 94110</p><div class="row"><span>📞 Call</span><span>🧭 Directions</span><span>🌐 Website</span><span>⭐ Save</span></div><p class="small">Popular dishes: Morning bun, Country loaf, Croque monsieur</p></div>'), allow=["food"])
mock("places-maps-card", ["places"], page('<div style="height:430px;background:repeating-linear-gradient(45deg,#e5e7eb,#e5e7eb 20px,#d1d5db 20px,#d1d5db 40px)"></div><div class="card" style="margin:-40px 8px 0;background:var(--bg);box-shadow:0 -4px 20px #0002">'
                                          '<h2>Blue Bottle Coffee</h2><p class="small">Coffee Shop · 0.3 mi · Open · Closes 6 PM</p><div class="row"><div class="card" style="background:#0a84ff;color:#fff">🚶 6 min</div><div class="card">Call</div><div class="card">Website</div></div>'
                                          '<p>66 Mint St, San Francisco, CA 94103</p><p class="small">★ 4.5 (1,204 on Yelp) · $$</p></div>'), allow=["drinks", "directions"])
mock("directions-walk", ["directions"], page('<div style="height:470px;background:repeating-linear-gradient(-30deg,#e5e7eb,#e5e7eb 30px,#d1d5db 30px,#d1d5db 34px)"></div><div class="content"><h2>18 min</h2><p>1.2 mi · Walk · Flat</p>'
                                             + "".join(f'<div class="row"><span>{a}</span><span class="small">{b}</span></div>' for a, b in [("↑ Head north on Valencia St", "0.4 mi"), ("→ Turn right onto 16th St", "0.3 mi"), ("← Turn left onto Guerrero St", "0.5 mi"), ("📍 Arrive at Tartine Bakery", "")]) + '<div class="card" style="background:#34c759;color:#fff;text-align:center">GO</div></div>'), allow=["places"])
mock("directions-drive", ["directions"], page('<div style="position:absolute;inset:0;background:#2d3b2d"></div><div class="card" style="position:relative;margin:10px;background:#1c4532;color:#fff"><h1>⤴︎ 0.4 mi</h1><h2>Bay Bridge / I-80 E</h2></div>'
                                              '<div style="position:absolute;bottom:0;left:0;right:0;background:#1c1c1e;color:#fff;padding:20px"><div class="row"><b>4:52 PM arrival</b><b>23 min</b><b>11 mi</b></div><p class="small">Via I-80 E · Traffic is moderate · Toll road</p><div class="card" style="background:#ff3b30;text-align:center">End Route</div></div>', dark=True))

mock("cooking-steps", ["recipes"], page('<div class="content"><h2>Step 3 of 7</h2><div style="height:280px;background:linear-gradient(135deg,#f4a261,#e76f51);border-radius:12px"></div><p style="font-size:20px;line-height:1.5">Melt 2 tbsp butter in a large skillet over medium heat. Add the garlic and cook, stirring, until fragrant, about 1 minute. Do not let it brown.</p>'
                                                   '<p class="small">⏱ Timer 1:00 · Ingredients used: butter, 4 cloves garlic</p><div class="row"><div class="card">← Back</div><div class="card" style="background:#e76f51;color:#fff">Next step →</div></div></div>'), allow=["cooking", "food"])
mock("recipe-card", ["recipes"], page('<div class="content"><p class="small">NYT COOKING</p><h1>Crispy Gnocchi with Burst Tomatoes</h1><p>★★★★★ 12,401 ratings · 25 minutes · Serves 4</p><h3>Ingredients</h3>'
                                      + "".join(f'<p>• {x}</p>' for x in ["1 (16-ounce) package shelf-stable gnocchi", "2 pints cherry tomatoes", "3 tablespoons olive oil", "4 garlic cloves, thinly sliced", "1/2 cup torn basil", "Grated Parmesan, for serving"])
                                      + '<h3>Preparation</h3><p>Step 1: Heat oven to 425 degrees…</p></div>'), allow=["food", "cooking"])
mock("food-delivery", ["food"], page('<div class="content"><h2>Burma Superstar</h2><p class="small">★ 4.7 · 25–35 min · $1.99 delivery</p>' + "".join(
    f'<div class="row" style="padding:10px 0;border-bottom:1px solid var(--line)"><div><b>{a}</b><div class="small">{b}</div></div><span>{c}</span></div>' for a, b, c in [("Tea Leaf Salad", "Fermented tea leaves, peanuts, sesame", "$17.00"), ("Rainbow Salad", "22 ingredients", "$18.00"), ("Coconut Chicken Noodle Soup", "Ohn no khauk swe", "$16.50"), ("Garlic Noodles", "Vegetarian", "$14.00")])
    + '<div class="card" style="background:#ff3008;color:#fff;text-align:center">View cart · 2 items · $33.00</div></div>'), allow=["orders", "places"])
mock("drinks-menu", ["drinks"], page('<div class="content" style="background:#1c1917;color:#f5f5f4;height:820px;font-family:Georgia,serif"><h1 style="text-align:center">Cocktails</h1>' + "".join(
    f'<div style="margin:16px 0"><div class="row"><b>{a}</b><span>{c}</span></div><div class="small">{b}</div></div>' for a, b, c in [("Negroni", "gin, Campari, sweet vermouth", "16"), ("Paper Plane", "bourbon, Aperol, Amaro Nonino, lemon", "17"), ("Espresso Martini", "vodka, coffee liqueur, fresh espresso", "16"), ("Natural Wine, by the glass", "ask your server", "14")]) + '</div>', dark=True), allow=["food"])
mock("coffee-order", ["drinks"], page('<div class="content"><h2>Your order</h2><div class="card"><b>Grande Oat Latte</b><div class="small">Extra shot · Light ice · Vanilla sweet cream</div><div class="row"><span></span><b>$6.95</b></div></div>'
                                      '<div class="card"><b>Butter Croissant</b><div class="row"><span>Warmed</span><b>$3.75</b></div></div><p>Pickup at 4th & King · Ready in 4–6 min</p><div class="card" style="background:#00704a;color:#fff;text-align:center">Pay $10.70</div></div>'), allow=["food", "orders"])

mock("settings-wifi", ["settings"], page('<div class="nav"><span class="back">‹ Settings</span><div class="title">Wi-Fi</div><span class="back">Edit</span></div><div class="content"><div class="card"><div class="row"><b>Wi-Fi</b><span>🟢</span></div><div class="row"><span>✓ Home-5G</span><span>🔒 ᯤ ⓘ</span></div></div>'
                                         '<p class="small">MY NETWORKS</p><div class="card"><div class="row"><span>Cafe Lumen Guest</span><span>🔒 ᯤ ⓘ</span></div></div><p class="small">OTHER NETWORKS</p><div class="card"><div class="row"><span>xfinitywifi</span><span>ᯤ ⓘ</span></div><div class="row"><span>NETGEAR42</span><span>🔒 ᯤ ⓘ</span></div></div>'
                                         '<div class="card"><div class="row"><span>Ask to Join Networks</span><span class="small">Notify ›</span></div><div class="row"><span>Auto-Join Hotspot</span><span class="small">Ask to Join ›</span></div></div></div>'))
mock("settings-screentime", ["settings"], page('<div class="nav"><span class="back">‹ Settings</span><div class="title">Screen Time</div><span></span></div><div class="content"><div class="card"><p class="small">Daily Average</p><h1>4h 12m</h1><p class="small">12% down from last week</p></div>'
                                               '<div class="card">See All App & Website Activity</div><div class="card"><div class="row"><span>Downtime</span><span>›</span></div><div class="row"><span>App Limits</span><span>›</span></div><div class="row"><span>Communication Limits</span><span>›</span></div><div class="row"><span>Content & Privacy Restrictions</span><span>›</span></div></div></div>', dark=True))

# ---------------------------------------------------------------- render
def render():
    from playwright.sync_api import sync_playwright
    out_dir = OUT / "mock"
    out_dir.mkdir(parents=True, exist_ok=True)
    html_dir = OUT / "mock_html"
    html_dir.mkdir(parents=True, exist_ok=True)
    manifest = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(viewport={"width": 402, "height": 874}, device_scale_factor=3)
        tab = ctx.new_page()
        for m in MOCKS:
            html_path = html_dir / f"{m['name']}.html"
            html_path.write_text(m["html"])
            tab.goto(html_path.resolve().as_uri())
            tab.wait_for_timeout(60)
            tab.screenshot(path=str(out_dir / f"{m['name']}.png"))
            manifest.append({"file": f"mock/{m['name']}.png", "expect": m["expect"], "allow": m["allow"], "source": "mock"})
        browser.close()
    (OUT / "mock_manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"rendered {len(manifest)} mocks into {out_dir}")


if __name__ == "__main__":
    render()
