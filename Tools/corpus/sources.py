"""Real screenshots captured in the iOS simulator: web pages, full-screen photos and system screens.

Each entry: (id, target, expect, allow). Targets:
  "https://…"        open in Safari
  "wiki:<Article>"   open the article's lead photo full screen (resolved via Wikipedia's REST API)
  "maps://…"         open in Maps
  "home"             the home screen
Labels describe what a person would file the screenshot under.
Before capturing: `xcrun simctl privacy <udid> grant location com.apple.Maps` (otherwise the location prompt covers Maps).
Removed after review: lead images that are maps/logos, and pages behind consent walls.
"""

def wiki(cat, titles, allow=()):
    return [(f"{cat}-{t.lower().replace(' ', '-').replace(',', '')[:40]}", f"wiki:{t}", [cat], list(allow)) for t in titles]

SOURCES = (
    wiki("animals", ["Golden Retriever", "Cat", "Red fox", "Giraffe", "Bald eagle", "Siberian Husky", "Koala", "Bengal tiger"])
    + wiki("beaches", ["Bondi Beach", "Navagio", "Waikiki", "Whitehaven Beach", "Praia da Marinha"], allow=["landscapes", "nature"])
    + wiki("mountains", ["Matterhorn", "Mount Fuji", "Denali", "Mount Rainier", "Eiger"], allow=["landscapes", "nature"])
    + wiki("flowers", ["Rose", "Tulip", "Common sunflower", "Phalaenopsis", "Lavandula"], allow=["plants", "nature"])
    + wiki("plants", ["Monstera deliciosa", "Aloe vera", "Saguaro", "Fern", "Sansevieria trifasciata"], allow=["nature", "flowers", "art"])
    + wiki("sunset", ["Sunset", "Golden hour (photography)", "Afterglow"], allow=["landscapes", "nature", "beaches"])
    + wiki("landscapes", ["Grand Canyon", "Torres del Paine National Park", "Antelope Canyon"], allow=["nature", "mountains"])
    + wiki("nature", ["Forest", "Niagara Falls", "Redwood National and State Parks", "Plitvice Lakes National Park"], allow=["landscapes", "plants"])
    + wiki("sitesOfInterest", ["Colosseum", "Taj Mahal", "Golden Gate Bridge", "Sydney Opera House", "Machu Picchu"], allow=["landscapes", "flights"])
    + wiki("storefronts", ["Shop", "Storefront", "Apple Fifth Avenue", "Shakespeare and Company (bookstore)"], allow=["stores"])
    + wiki("people", ["Portrait photography", "Wedding", "Family", "Selfie"], allow=["events"])
    + wiki("vehicles", ["Ford Mustang", "Tesla Model 3", "Volkswagen Beetle", "Bicycle"])
    + wiki("food", ["Pizza", "Sushi", "Hamburger", "Ramen", "Croissant", "Tacos"], allow=["recipes", "cooking"])
    + wiki("drinks", ["Coffee", "Cocktail", "Latte", "Margarita", "Bubble tea"], allow=["food"])
    + wiki("clothes", ["Little black dress", "Jeans", "Trench coat", "Kimono"])
    + wiki("shoes", ["Sneakers", "Cowboy boot", "Chelsea boot"], allow=["clothes"])
    + wiki("watches", ["Rolex Submariner", "Omega Speedmaster", "Apple Watch"], allow=["electronics", "jewelry"])
    + wiki("bags", ["Handbag", "Backpack", "Birkin bag"], allow=["clothes"])
    + wiki("jewelry", ["Necklace", "Engagement ring", "Earring"])
    + wiki("furniture", ["Eames Lounge Chair", "Couch", "Windsor chair", "Chesterfield (sofa)"], allow=["homes"])
    + wiki("electronics", ["IPhone", "Laptop", "Headphones", "PlayStation 5", "Mechanical keyboard"], allow=["videoGames"])
    + wiki("homes", ["House", "Victorian house", "Bungalow", "A-frame house"], allow=["landscapes"])
    + wiki("art", ["Mona Lisa", "The Starry Night", "Girl with a Pearl Earring", "The Great Wave off Kanagawa", "The Birth of Venus"])
    + [
        ("news-bbc", "https://www.bbc.com/news", ["news"], []),
        ("news-npr", "https://text.npr.org", ["news"], []),
        ("news-ap", "https://apnews.com", ["news"], []),
        ("news-guardian", "https://www.theguardian.com/us", ["news"], []),
        ("news-cnn-lite", "https://lite.cnn.com", ["news"], []),
        ("news-hn", "https://news.ycombinator.com", ["news"], ["programming"]),
        ("programming-github-code", "https://github.com/apple/swift/blob/main/stdlib/public/core/Array.swift", ["programming"], []),
        ("programming-github-repo", "https://github.com/swiftlang/swift-package-manager", ["programming"], []),
        ("programming-python-docs", "https://docs.python.org/3/tutorial/controlflow.html", ["programming"], ["documents", "reading"]),
        ("programming-apple-docs", "https://developer.apple.com/documentation/swiftui/view", ["programming"], ["documents"]),
        ("programming-mdn", "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/map", ["programming"], ["documents"]),
        ("programming-so", "https://stackoverflow.com/questions/24003191/pass-by-reference-in-swift", ["programming"], []),
        ("youtube-watch", "https://m.youtube.com/watch?v=jNQXAC9IVRw", ["youtube"], ["animals"]),
        ("youtube-channel", "https://m.youtube.com/@NASA", ["youtube"], ["news"]),
        ("youtube-search", "https://m.youtube.com/results?search_query=lofi+hip+hop", ["youtube"], ["music"]),
        ("stores-apple-iphone", "https://www.apple.com/shop/buy-iphone", ["stores"], ["electronics"]),
        ("stores-apple-airpods", "https://www.apple.com/shop/buy-airpods", ["errors"], ["stores"]),  # renders Apple's "page can't be found"
        ("stores-ikea", "https://www.ikea.com/us/en/cat/sofas-fu003/", ["stores"], ["furniture", "homes"]),
        ("stores-nike", "https://www.nike.com/w/mens-shoes-nik1zy7ok", ["stores"], ["shoes", "clothes"]),
        ("stores-target", "https://www.target.com/c/kitchen-appliances-dining/-/N-5xtrl", ["stores"], ["cooking", "electronics"]),
        ("stores-etsy", "https://www.etsy.com/c/jewelry", ["stores"], ["jewelry"]),
        ("reddit-pics", "https://www.reddit.com/r/pics/", ["reddit"], ["memes"]),
        ("reddit-askreddit", "https://www.reddit.com/r/AskReddit/", ["reddit"], []),
        ("weather-nws", "https://forecast.weather.gov/MapClick.php?lat=37.7749&lon=-122.4194", ["weather"], []),
        ("weather-nws-home", "https://www.weather.gov", ["weather"], ["news"]),
        ("recipes-allrecipes", "https://www.allrecipes.com/recipe/10813/best-chocolate-chip-cookies/", ["recipes"], ["food", "cooking"]),
        ("recipes-bbcgoodfood", "https://www.bbcgoodfood.com/recipes/easy-pancakes", ["recipes"], ["food", "cooking"]),
        ("recipes-wiki", "https://en.wikibooks.org/wiki/Cookbook:Guacamole", ["recipes"], ["food", "cooking"]),
        ("movies-imdb", "https://m.imdb.com/title/tt15239678/", ["movies"], []),
        ("movies-letterboxd", "https://letterboxd.com/film/past-lives/", ["movies"], []),
        ("movies-wiki", "https://en.m.wikipedia.org/wiki/Oppenheimer_(film)", ["movies"], ["reading"]),
        ("books-goodreads", "https://www.goodreads.com/book/show/58784475-tomorrow-and-tomorrow-and-tomorrow", ["books"], ["reading"]),
        ("books-gutenberg", "https://www.gutenberg.org/ebooks/1342", ["books"], ["reading"]),
        ("reading-gutenberg-text", "https://www.gutenberg.org/cache/epub/1342/pg1342-images.html#link2HCH0001", ["reading", "books"], ["documents"]),
        ("videogames-steam", "https://store.steampowered.com/app/1145350/Hades_II/", ["videoGames"], ["stores"]),
        ("videogames-wiki", "https://en.m.wikipedia.org/wiki/The_Legend_of_Zelda:_Tears_of_the_Kingdom", ["videoGames"], ["reading"]),
        ("sports-espn", "https://www.espn.com/nba/scoreboard", ["sports"], ["news"]),
        ("sports-wiki", "https://en.m.wikipedia.org/wiki/2026_FIFA_World_Cup", ["sports"], ["news", "reading"]),
        ("flights-flightaware", "https://www.flightaware.com/live/flight/UAL837", ["flights"], []),
        ("flights-wiki-sfo", "https://en.m.wikipedia.org/wiki/San_Francisco_International_Airport", ["flights"], ["places", "reading"]),
        ("finance-yahoo", "https://finance.yahoo.com/quote/AAPL/", ["finance"], ["news"]),
        ("finance-coingecko", "https://www.coingecko.com/en/coins/bitcoin", ["finance"], []),
        ("documents-pdf-w9", "https://www.irs.gov/pub/irs-pdf/fw9.pdf", ["documents"], ["finance"]),
        ("documents-pdf-paper", "https://arxiv.org/pdf/1706.03762", ["documents"], ["programming", "reading"]),
        ("homes-redfin", "https://www.redfin.com/city/17151/CA/San-Francisco", ["homes"], ["places"]),
        ("errors-404", "https://github.com/this-user-does-not-exist-8812/nope", ["errors"], ["programming"]),
        ("errors-dns", "https://this-domain-does-not-exist-8812.com", ["errors"], []),
        ("health-cdc", "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html", ["health"], ["exercise", "news"]),
        ("events-eventbrite", "https://www.eventbrite.com/d/ca--san-francisco/events--this-weekend/", ["events"], []),
        ("places-maps", "maps://?q=Tartine+Bakery+San+Francisco", ["places"], ["food", "directions"]),
        ("places-maps-museum", "maps://?q=San+Francisco+Museum+of+Modern+Art", ["places"], ["sitesOfInterest", "art", "directions"]),
        ("directions-maps-drive", "maps://?saddr=Ferry+Building+San+Francisco&daddr=Golden+Gate+Park&dirflg=d", ["directions"], ["places"]),
        ("directions-maps-walk", "maps://?saddr=Union+Square+San+Francisco&daddr=Chinatown+San+Francisco&dirflg=w", ["directions"], ["places"]),
        ("directions-maps-transit", "maps://?saddr=Mission+Dolores+Park&daddr=Salesforce+Tower&dirflg=r", ["directions"], ["places"]),
        ("ioshome-1", "home", ["iosHomeScreens"], []),
        ("other-example", "https://example.com", [], []),
        ("other-wiki-philosophy", "https://en.m.wikipedia.org/wiki/Epistemology", [], ["reading"]),
    ]
)
