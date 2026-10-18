# Category Testing Guide

## How to Test & Provide Feedback

### Step 1: Test Screenshots in the App
1. Run the app on simulator or device
2. Import/categorize screenshots
3. Open the home ⋯ menu → "Evaluation (debug)" to see what the pipeline extracted, and export real cases as golden fixtures

### Step 2: Fill Out the CSV

Open `category_testing_template.csv` and fill in the columns:

**Columns:**
- `test_id`: Auto-numbered (1, 2, 3...)
- `image_description`: Brief description of what's in the image
- `expected_categories`: What categories SHOULD it be (semicolon-separated: `food;drinks`)
- `actual_categories`: What categories it WAS (copy from app or logs)
- `accuracy_rating`: 1-5 scale (1=terrible, 5=perfect)
- `notes`: Any additional comments about why it was right/wrong

**Example Row:**
```csv
5,Dog playing in a park,animals;nature;parks,animals;landscapes,4,"Got animals right, but missed 'parks' - detected generic landscape instead"
```

### Step 3: Look for Debug Output

In Xcode console, you'll see something like this:

```
================================================================================
📊 CATEGORIZATION DEBUG REPORT
================================================================================
🔍 Detection Results:
   • People detected: false
   • Animals detected: true
   • App categories: 0
   • Text categories: 1
   • Vision categories: 3

📈 All Category Scores (before filtering):
   ✅ animals              : 0.720
   ✅ nature               : 0.560
   ❌ parks                : 0.380  ← Below threshold!
   ❌ landscapes           : 0.240
================================================================================
```

**Copy the key info:**
- Which categories passed (✅) vs failed (❌)
- The actual scores
- Any surprising results

### Step 4: Share the CSV

Two options:

**Option A: Simple - Just share individual rows**
Copy-paste problematic rows in chat:
```
test_id,image_description,expected_categories,actual_categories,accuracy_rating,notes
12,Beach sunset photo,beaches;sunset;nature,sunset;landscapes,3,"Missed 'beaches' - only got sunset. Beach keywords might be too weak"
```

**Option B: Complete - Upload the full CSV**
Save the file and I can read it with:
```
Read the category_testing_template.csv file
```

## What I'll Do With Your Feedback

Based on your CSV data, I'll:

1. **Identify patterns** - Which categories are consistently missed?
2. **Adjust weights** - Increase/decrease category scoring weights
3. **Add keywords** - Add missing keywords to Vision mappings
4. **Tune thresholds** - Adjust the 0.45 confidence threshold if needed
5. **Fix scoring logic** - Update how categories are combined

## Example Analysis

If you report:
```csv
15,Mountain landscape,mountains;landscapes;nature,landscapes;nature,4,"Missed 'mountains' - score was 0.42 (just below 0.45 threshold)"
```

I might respond with:
- "Mountains scored 0.42 but threshold is 0.45 - let's lower threshold to 0.40"
- OR "Let's increase Vision weight for mountains from 0.8 to 0.9"
- OR "Add more mountain keywords: 'peak', 'summit', 'alpine'"

## Quick Testing Checklist

Test these categories specifically (new additions):

**Nature & Outdoors:**
- [ ] Nature/wilderness scenes
- [ ] Landscapes/vistas
- [ ] Beaches/ocean
- [ ] Mountains/peaks
- [ ] Flowers close-ups
- [ ] Plants/gardens
- [ ] Sunsets/sunrises

**Cooking:**
- [ ] Cooking in progress
- [ ] Recipe screenshots
- [ ] Kitchen scenes

**Activities:**
- [ ] Exercise/gym
- [ ] Art/painting
- [ ] Reading/books

## Tips for Good Test Data

1. **Test edge cases** - Images with multiple categories
2. **Test borderline cases** - Is it "nature" or "landscape" or both?
3. **Test common scenarios** - What users actually screenshot
4. **Note ambiguity** - Sometimes multiple answers are correct!
5. **Include negatives** - Things that should NOT match

## Current Category List

All available categories (reference for `expected_categories` column):

**Social Media:** instagram, tiktok, twitter, facebook, linkedin, reddit, youtube
**Communication:** imessage, whatsapp, signal, telegram, discord, slack, email, gmail
**Clothing:** clothes, shoes, watches, bags, jewelry
**Products:** vehicles, electronics, stores, storefronts
**Home:** furniture, homes
**Food:** food, drinks, cooking, recipes
**Nature:** nature, landscapes, beaches, mountains, flowers, plants, sunset
**Places:** places, sitesOfInterest, directions
**Events:** events, codes, flights
**Work:** documents, notes, receipts
**Media:** books, movies, music, memes, videoGames
**Lifestyle:** health, sports, weather, people, animals, exercise, art, reading
**Info:** news, quotes
**System:** notifications, iosHomeScreens

---

Ready to help improve the accuracy! 🎯
