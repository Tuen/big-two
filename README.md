# Big Two

Four people play Big Two (Choh Dai Di) in a browser. There are no computer players. The server decides every play. A phone sends "play these cards" or "pass", then draws what the server says is true.

The playable page is [https://tuen.github.io/big-two/](https://tuen.github.io/big-two/). Phones and computers open that address. Nothing on this PC has to stay on.

You can also pass one phone around the table. **Play on this device** uses the same rules and does not send scores anywhere. The score webhook runs on the server, after a real online hand.

The house rules are in [RULES.md](RULES.md).

## Folder layout

| Path | What it is |
| --- | --- |
| `app/` | Flutter web app. |
| `app/lib/rules/` | Dart rules. Practice mode uses these. The table also uses them to grey out a play the server would refuse. |
| `app/lib/` | Screens, the online client, and widgets. |
| `app/test/` | Flutter tests. |
| `app/web/` | `index.html`, the web manifest, and icons. The icon files are stored as `.png.b64`. The Pages workflow decodes them before the build. |
| `app/public-client.json` | Public Supabase URL and publishable key. The Pages workflow passes this to the web build. |
| `supabase/functions/_shared/rules/` | The same rules in TypeScript. Edge Functions play the hand from this code. |
| `supabase/functions/` | `table`, `deal`, `play`, `pass`, `tick`, `ping`, and `home`. |
| `supabase/migrations/` | `001_init.sql` tables and row-level security, `002_reorder_seats.sql` seating, `003_webhook_log.sql` score delivery. |
| `rules/test/rules.test.ts` | Node tests for the TypeScript rules. |
| `.github/workflows/pages.yml` | Builds the web app from source and publishes `gh-pages`. |
| `.github/workflows/keep-awake.yml` | Pings Supabase on Sunday and Wednesday. |

The Dart and TypeScript engines are two copies. If you change a rule, change both, then run both test suites.

## Run locally

Flutter 3.47.7 is the version the Pages workflow uses. From `app`:

```powershell
$env:Path = "C:\Users\justi\flutter\bin;" + $env:Path
cd C:\Users\justi\Grokbuild\big-two\app
flutter pub get
flutter run -d chrome --dart-define-from-file=public-client.json
```

Type a name and tap **Play on this device**. The app fills the other three seats with names you can edit before the deal. After each turn it covers the cards. The next person taps **Show my cards**. The turn timer, if you turn one on, starts at that moment.

**Create a table** and **Join** need the defines above. A build with both values empty still runs practice. Create and Join then say that this copy has no server.

Opening `index.html` as a file does not run the app.

## Tests

```powershell
cd C:\Users\justi\Grokbuild\big-two\rules
node --experimental-strip-types --test test/rules.test.ts

cd C:\Users\justi\Grokbuild\big-two\app
flutter test
flutter analyze
```

Node 22 or newer is enough for the TypeScript tests. The Pages workflow runs both suites before it publishes.

## Build the web app

```powershell
cd C:\Users\justi\Grokbuild\big-two\app
flutter build web --release --base-href /big-two/ --dart-define-from-file=public-client.json
```

The Pages files are in `app/build/web`. `--base-href /big-two/` matches `https://tuen.github.io/big-two/`. CanvasKit loads from gstatic, so the published site omits the `canvaskit` folder.

A local LAN copy can use `--base-href /` and `--output build/web`. Do not commit `app/build/`.

## Deploy the database and Edge Functions

The live project is `ascorkeijzrpmfykpcrb` in Sydney. Anonymous sign-in is on.

From `big-two`, with the [Supabase CLI](https://supabase.com/docs/guides/cli) logged in and linked:

```powershell
$env:Path = "C:\Program Files\nodejs;" + $env:Path
npx supabase db query --linked -f supabase/migrations/001_init.sql
npx supabase db query --linked -f supabase/migrations/002_reorder_seats.sql
npx supabase db query --linked -f supabase/migrations/003_webhook_log.sql
npx supabase functions deploy table deal play pass tick ping --use-api
```

`001` and `002` are already applied on the live project. Run a migration file again only when you mean to re-apply it. `supabase/config.toml` turns JWT checks on for `table`, `deal`, `play`, `pass`, and `tick`. `ping` and `home` are public.

Supabase injects `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` into Edge Functions. The service-role key stays there. It does not go in git, in the app, or in GitHub Actions.

### Who can see which cards

A seated player can read the table, the seats, the hands, the event log, their own cards, and finished results. They cannot read `hand_secrets` (the shuffled deck) and they cannot write any row. Only the Edge Functions write. `webhook_log` is service-role only. Players see the status word (`sent`, `failed`, `skipped`, `pending`, `sending`) on the score sheet.

The app subscribes to hands and seats, then asks `tick` for a fresh view. That view includes `yourCards` for the signed-in seat and a count for everyone else.

## GitHub Pages

A push to `main` runs **Publish the web app** (`.github/workflows/pages.yml`). It checks out the source, runs the tests, builds with `flutter build web --release --base-href /big-two/ --dart-define-from-file=public-client.json`, and commits the result to `gh-pages` when the site changed. It does not force-push. The public anon key and project URL in `app/public-client.json` are meant to be public. Do not add a service-role key or a webhook key to that file or to the workflow.

`gh-pages` is what [https://tuen.github.io/big-two/](https://tuen.github.io/big-two/) serves. `main` holds the source.

On an iPhone or iPad: open the site in Safari, Share, **Add to Home Screen**, then launch **Big Two** from the icon.

## Keep-awake

A free Supabase project pauses after about seven days without API traffic. `.github/workflows/keep-awake.yml` runs at 18:00 UTC on Sunday and Wednesday (`0 18 * * 0,3`) and requests:

`https://ascorkeijzrpmfykpcrb.supabase.co/functions/v1/ping`

`ping` writes one row in `keep_alive`. That write is the activity. Someone opening the app also counts. If the project is already paused, restore it in the dashboard. The ping cannot wake a paused project.

The turn timer is not a sleeping job. Any open client calls `tick` about every 8 seconds. If everybody has closed the app, a timed-out turn waits until someone opens the table again.

## The table

Anyone can create a table. Each **Create** makes a new table and a new 6-character code. The alphabet is `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no I, O, 0, or 1). The creator is the host of that table only. Four seats. There is no lock that stops someone else creating another table.

Any seated player can deal, deal the next hand, or start a new round. Only the host changes settings, seating, and display names, and only in the lobby before a hand of that round. **New round** returns to the lobby and does not deal by itself. Seat 1 leads the first hand, then play goes to the left. Seats stay fixed for every hand inside a round.

Settings, with the defaults:

- Passing does not lock you for the rest of the trick.
- Straights do not wrap.
- Turn timer off. The choices are off, 15, 30, 45, and 60 seconds.
- Season 24. The host can change it in the lobby.
- The round number starts at 1 and goes up when a round ends. The host can set the first round number before any hand exists.
- Score dates use `Australia/Melbourne`. The host can pick Sydney, Brisbane, Adelaide, Perth, Auckland, or UTC.

In the lobby the host can shuffle seats, move a player up or down, and rename a seated player. A name is at most 24 characters.

## Score webhook

When an online hand finishes, the Edge Function POSTs one JSON body to `SCORE_WEBHOOK_URL`. Practice mode does not POST. Bonuses played during the hand are stored on that same hand and go out in this one request. The body is saved on the hand, so a retry sends the same `handId`.

Set these in the Supabase dashboard: Project Settings, Edge Functions, Secrets. Or from the linked CLI:

```powershell
npx supabase secrets set SCORE_WEBHOOK_URL=https://your-host.example/scores SCORE_WEBHOOK_KEY=your-key SCORE_WEBHOOK_KEY_HEADER=X-Score-Key
```

| Secret | Role |
| --- | --- |
| `SCORE_WEBHOOK_URL` | Where to POST. If this is unset, the hand is marked `skipped` and nothing is sent. |
| `SCORE_WEBHOOK_KEY` | Sent as the header value, with no `Bearer` prefix. |
| `SCORE_WEBHOOK_KEY_HEADER` | Header name. Letters, digits, and hyphens, 1 to 64 characters. If unset, the header is `X-Score-Key`. |

Leave the URL unset until the receiver exists. Do not put the URL or the key in git.

An older secret name, `SCORE_WEBHOOK_SECRET`, still works when `SCORE_WEBHOOK_KEY` is unset. In that case the header defaults to `X-Score-Secret` unless `SCORE_WEBHOOK_KEY_HEADER` is set.

The function tries up to 5 times, waiting 400 ms, 800 ms, 1.6 s, and 3.2 s between tries. Each try is a row in `webhook_log` (status code and a short detail, not the response body). After 5 failures the hand is `failed`. A later `tick` retries while the status is `pending`, `failed`, or `sending`, and stops once 5 attempts are recorded. `handId` does not change, so the receiver can ignore a duplicate.

The score sheet and the hand-over screen show **Scores sent ✓**, **Scores failed**, **Scores not sent**, or **Sending scores**.

```json
{
  "handId": "the-hand-uuid",
  "tableCode": "ABC123",
  "season": 24,
  "round": 11,
  "hand": 3,
  "date": "2026-10-24",
  "players": ["Justin", "Mary", "Pauline", "Damien"],
  "cardsLeft": [0, 11, 9, 4],
  "handPoints": [8, 30, 17, 4],
  "bonuses": [{ "player": "Damien", "combo": "straight flush", "pointsEach": 8 }],
  "runningTotals": [28, 60, 55, 49],
  "roundOver": true,
  "roundWinner": "Justin"
}
```

`date` is the calendar date in the table's timezone. `handPoints` is card points plus bonuses that player was given during the hand. In the example, cards left of 0, 11, 9, and 4 are worth 0, 22, 9, and 4. Damien's straight flush added 8 to the other three, which is why their hand points are 8, 30, 17, and 4. `roundWinner` is null until the round is over. If two players share the lowest total, the names are joined in seat order, such as `"Justin, Mary"`.

**Scores → Export round as CSV** still copies a sheet you can paste into Excel. The snackbar says "Round CSV copied. Paste it into Excel."

`season, round, hand, date, player, cards_left, hand_points, running_total, round_over, bonuses`
