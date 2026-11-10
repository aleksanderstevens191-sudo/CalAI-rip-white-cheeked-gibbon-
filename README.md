# White Cheeked Gibbon

A personal AI calorie tracker for iPhone (SwiftUI + SwiftData, iOS 18+). No subscription, no account, all data stays on the phone. Photo analysis uses your own Anthropic API key, so you pay only for what you scan.

## How a scan works

1. **Recognition + portions (Claude):** the photo goes to Claude, which lists every component (including hidden oils, sauces, dressings), estimates grams from plate/utensil scale cues, and names each one the way USDA does (e.g. "Chicken, broilers or fryers, breast, meat only, cooked, roasted").
2. **Nutrition (USDA FoodData Central):** the app looks each ingredient up in USDA's lab-analyzed Foundation Foods and SR Legacy data and replaces the AI's per-100 g numbers with USDA's when the match passes a sanity check. Ingredients with a USDA match get a green **USDA** badge.
3. **Math (on device):** grams × per-100 g values. Editing an amount rescales every nutrient.

Nutrition labels skip step 2 (the label is exact). "Fix results" never re-estimates values that came from a label, a database, a USDA food you picked, or your own edits.

## Snack scanning (+ → Barcode / QR)

Reads retail barcodes (EAN/UPC, including UPC-E) and GS1 QR codes, from the camera or a photo/screenshot. Every code is normalized to one 13-digit form, then looked up in order:

1. **Your own history** — products you've logged before are rebuilt from the values first recorded for them (free, offline).
2. **USDA Branded Foods** — manufacturer-supplied data, the most reliable source for US products (needs the free USDA key; skipped if USDA is unavailable).
3. **Open Food Facts** — free community database; the card says so, since entries are volunteer-typed.
4. **Not found** — snap the nutrition label once (one AI call) and it's remembered under that barcode.

A quick-add card lets you pick servings or grams and the meal. Nothing is saved until you tap **Log**.

## Features

- **Onboarding**: gender, birthday, height/weight, workouts per week, goal, goal weight, pace, optional API key, then an editable plan.
- **Home**: week strip with colored day rings, swipeable cards (calories, macros, fiber/sugar/sodium, health score, calories burned, weight, water), streak, every meal grouped by breakfast/lunch/dinner/snack.
- **Logging (+)**: scan food, barcode, nutrition label, describe food, food database (USDA generic foods + Open Food Facts packaged products), saved foods, exercise, water, weight with progress photo.
- **Ingredient editing**: change grams, edit any nutrient, **Match to USDA lab data** by hand, add ingredients by describing them or manually, remove them, change servings, **Fix results** to tell the AI what it got wrong.
- **Progress**: streak, badges, weight chart, weight changes, progress photos, calorie and energy charts, BMI.
- **Profile**: AI settings (Anthropic key, USDA key, model, effort, monthly spend), personal details, preferences, nutrition goals, reminders, weight history, PDF and CSV export.
- **Cost tracking**: each meal shows what its AI analysis cost, and AI settings shows this month's total, both calculated from the token usage Anthropic reports.

Not included on purpose: Apple Health, Groups, paywall.

## Keys

- **Anthropic API key** (required for photo/text AI): https://console.anthropic.com/settings/keys
- **USDA FoodData Central key** (free, recommended): https://api.data.gov/signup/ — without it the app uses the shared `DEMO_KEY`, which only allows about 10 lookups per hour (roughly 1–2 scans). A personal key allows 1,000 per hour.

Both are stored in the iOS Keychain.

## Choosing a model (Profile → AI settings)

Rough per-scan estimates at High effort (photo ~1,500×1,200 px, ~3k output tokens); actual spend is shown in the app.

| Model | Per scan | 3 scans/day for a month |
|---|---|---|
| Claude Haiku 5.5 (default) | ~0.2¢ | ~$0.15 |
| Claude Sonnet 5.5 | ~2–3¢ | ~$2–3 |
| Claude Opus 5.5 | ~6¢ | ~$5–6 |

USDA grounding means the model mostly has to identify foods and estimate portions; the nutrition numbers for generic foods come from USDA either way.

## Run it

```bash
cd Gibbon
xcodegen generate
open Gibbon.xcodeproj
```

### On your iPhone

1. Plug in your iPhone and turn on **Developer Mode** (Settings → Privacy & Security → Developer Mode).
2. In Xcode select the **Gibbon** target → **Signing & Capabilities** → choose your Apple ID team. If the bundle ID `com.alek.gibbon` is taken, change it.
3. Pick your iPhone as the run destination and press **Run**.
4. First launch: Settings → General → VPN & Device Management → trust your developer certificate.

With a free Apple ID the app must be reinstalled from Xcode every 7 days; a paid developer account removes that limit.

## Code map

| Folder | What's there |
|---|---|
| `Gibbon/Models` | SwiftData models, nutrient math, plan calculator (Mifflin–St Jeor), day stats/streaks |
| `Gibbon/Services` | Claude client + spend tracking, food prompts/schemas (`FoodAI.swift`), USDA lookup and grounding (`USDA.swift`), Open Food Facts, Keychain, reminders, PDF/CSV export |
| `Gibbon/App` | App entry, tab bar, + menu, app state, background analysis manager |
| `Gibbon/Onboarding` | Onboarding flow |
| `Gibbon/Home` | Home screen, week strip, summary cards, meal list |
| `Gibbon/Logging` | Camera scanner, barcode, describe/search/saved foods, water, weight, exercise |
| `Gibbon/FoodDetail` | Meal detail, ingredient editor, USDA picker, add ingredient, fix results |
| `Gibbon/ProgressTab` | Progress charts and badges |
| `Gibbon/Profile` | Settings screens |
| `Art/gibbon-face.svg` | Mascot source (also in the asset catalog as `Gibbon`) |

## Adding your keys without pasting

Copy `Secrets.example.plist` to `Gibbon/Config/Secrets.plist` and fill in your Anthropic and USDA keys. On launch the app saves them to the Keychain. That file is git-ignored; never commit it.

Set `DEVELOPMENT_TEAM` in `project.yml` to your own Apple team ID before installing on a device.
