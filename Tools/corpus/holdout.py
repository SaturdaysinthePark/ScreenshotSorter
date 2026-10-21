"""Held-out captures: never used for tuning. Score them, don't tune on them.
    python3 Tools/corpus/capture.py build/holdout --sources holdout
"""
from sources import wiki

SOURCES = (
    wiki("animals", ["Border Collie", "Red panda", "Elephant", "Penguin"])
    + wiki("beaches", ["Copacabana (Rio de Janeiro)", "Maya Bay"], allow=["landscapes", "nature"])
    + wiki("mountains", ["K2", "Mont Blanc"], allow=["landscapes", "nature"])
    + wiki("flowers", ["Daisy", "Peony"], allow=["plants", "nature"])
    + wiki("plants", ["Bonsai", "Ficus lyrata"], allow=["nature"])
    + wiki("food", ["Lasagna", "Pad thai", "Cheesecake"], allow=["recipes", "cooking"])
    + wiki("drinks", ["Espresso", "Mojito"], allow=["food"])
    + wiki("vehicles", ["Porsche 911", "Vespa"])
    + wiki("art", ["The Scream", "American Gothic"])
    + wiki("sitesOfInterest", ["Big Ben", "Petra"], allow=["landscapes"])
    + wiki("electronics", ["AirPods"], allow=["videoGames"])  # Nintendo Switch lead image is a logo
    + wiki("shoes", ["Stiletto heel"], allow=["clothes"])  # Air Jordan lead image is a logo
    + [
        ("news-npr-story", "https://text.npr.org/1", ["errors"], ["news"]),  # renders "Page Not Found"
        ("news-reuters", "https://www.reuters.com", ["news"], []),
        ("news-verge", "https://www.theverge.com", ["news"], ["electronics"]),
        ("news-aljazeera", "https://www.aljazeera.com", ["news"], []),
        ("programming-github-issues", "https://github.com/swiftlang/swift/issues", ["programming"], []),
        ("programming-swift-docs", "https://www.swift.org/documentation/", ["programming"], ["documents"]),
        ("programming-rust-book", "https://doc.rust-lang.org/book/ch01-02-hello-world.html", ["programming"], ["documents", "reading"]),
        ("recipes-seriouseats", "https://www.seriouseats.com/the-best-chili-recipe", ["recipes"], ["food", "cooking"]),
        ("recipes-budgetbytes", "https://www.budgetbytes.com/one-pot-creamy-cajun-chicken-pasta/", ["recipes"], ["food", "cooking"]),
        ("stores-target-tv", "https://www.target.com/c/tvs-home-theater-electronics/-/N-5xtdj", ["stores"], ["electronics"]),
        ("stores-etsy-art", "https://www.etsy.com/c/art-and-collectibles", ["stores"], ["art"]),
        ("weather-nws-nyc", "https://forecast.weather.gov/MapClick.php?lat=40.7128&lon=-74.006", ["weather"], []),
        ("movies-imdb-oppenheimer", "https://m.imdb.com/title/tt15398776/", ["movies"], []),
        ("sports-espn-nfl", "https://www.espn.com/nfl/scoreboard", ["sports"], ["news"]),
        ("finance-yahoo-tsla", "https://finance.yahoo.com/quote/TSLA/", ["finance"], ["news"]),
        ("books-goodreads-dune", "https://www.goodreads.com/book/show/44767458-dune", ["books"], ["reading", "movies"]),
        ("videogames-steam-stardew", "https://store.steampowered.com/app/413150/Stardew_Valley/", ["videoGames"], ["stores"]),
        ("errors-404-apple", "https://www.apple.com/this-page-does-not-exist", ["errors"], []),
        ("homes-redfin-nyc", "https://www.redfin.com/city/30749/NY/New-York", ["homes"], ["places"]),
        ("flights-flightaware-dl", "https://www.flightaware.com/live/flight/DAL1", ["flights"], []),
        ("places-maps-ferry", "maps://?q=Ferry+Building+Marketplace+San+Francisco", ["places"], ["food", "sitesOfInterest"]),
        ("directions-maps-bike", "maps://?saddr=Golden+Gate+Park&daddr=Ocean+Beach+San+Francisco&dirflg=w", ["directions"], ["places"]),
        ("documents-pdf-i9", "https://www.uscis.gov/sites/default/files/document/forms/i-9.pdf", ["documents"], []),
        ("health-nih", "https://www.nhlbi.nih.gov/health/heart-healthy-living/physical-activity", ["health"], ["exercise"]),
    ]
)
