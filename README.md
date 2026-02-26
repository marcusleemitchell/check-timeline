# check-timeline

A Ruby CLI tool that aggregates data from multiple sources — REST APIs and local JSON files — onto a single, chronological timeline for a given check, identified by UUID. Results are rendered as a self-contained, modern HTML file that opens automatically in your browser.

---

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Basic usage](#basic-usage)
  - [With a local check file](#with-a-local-check-file)
  - [With a local check file and payments file](#with-a-local-check-file-and-payments-file)
  - [With Raygun exception files](#with-raygun-exception-files)
  - [Using glob patterns](#using-glob-patterns)
  - [Controlling output](#controlling-output)
  - [Parallel fetching](#parallel-fetching)
  - [Quiet mode](#quiet-mode)
- [Data Sources](#data-sources)
  - [Checks API](#checks-api)
  - [Check File Source](#check-file-source)
  - [PaperTrail Versions](#papertrail-versions)
  - [Raygun File Source](#raygun-file-source)
- [Architecture](#architecture)
  - [Project structure](#project-structure)
  - [Data flow](#data-flow)
  - [Core models](#core-models)
    - [Event](#event)
    - [Timeline](#timeline)
  - [Renderers](#renderers)
  - [Aggregator](#aggregator)
- [HTML Output](#html-output)
- [Adding a New Data Source](#adding-a-new-data-source)
- [Event Types Reference](#event-types-reference)
- [Severity Levels](#severity-levels)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

---

## Overview

`check-timeline` answers the question: *"What actually happened to this check?"*

Given a check UUID, the tool fetches data from one or more sources:

1. **Live API** — Calls `/public/checks/:id` and `/public/checks/:id/payments` for check, line item, discount, and payment events
2. **Local check file** — Reads a saved `check.json` in the same JSON:API format as the API response, optionally paired with a `payments.json` file. Useful offline or for investigating saved snapshots without API credentials. If the file's `included` array contains PaperTrail version records, they are parsed automatically — no extra flag needed
3. **Raygun files** — Reads any number of local Raygun exception JSON files

All events are merged onto a single chronological timeline and rendered as a self-contained HTML file with a visual timeline, value ledger chart, severity badges, and expandable event cards.

> **Note:** The live API and `--check-file` are mutually exclusive for check data — if `--check-file` is provided the live API is skipped, preventing double-counting of check events. Raygun files can be combined with either. PaperTrail version records are parsed automatically from the check file when present.

The HTML output is entirely standalone — no server required, no external CDN dependencies. Just open it in a browser.

---

## Requirements

- Ruby `~> 3.2`
- Bundler

---

## Installation

```sh
git clone https://github.com/your-org/check-timeline.git
cd check-timeline
gem install bundler
bundle install
chmod +x bin/check-timeline
```

Verify the install:

```sh
./bin/check-timeline --help
```

---

## Configuration

The Checks API source is configured entirely through environment variables. **Credentials are never stored in code or config files.**

| Variable | Required | Description |
|---|---|---|
| `CHECKS_API_BASE_URL` | ✅ | Base URL of the Checks API, e.g. `https://api.example.com` |
| `CHECKS_API_KEY` | ✅ | Sent as the `X-API-Key` request header |
| `CHECKS_APP_NAME` | ✅ | Sent as the `X-App-Name` request header |

### Setting environment variables

Export them in your shell before running:

```sh
export CHECKS_API_BASE_URL="https://api.example.com"
export CHECKS_API_KEY="your-api-key"
export CHECKS_APP_NAME="your-app-name"
```

Or prefix them inline per invocation:

```sh
CHECKS_API_BASE_URL="https://api.example.com" \
CHECKS_API_KEY="your-api-key" \
CHECKS_APP_NAME="your-app-name" \
./bin/check-timeline generate <UUID>
```

Or store them in a `.env` file (never commit this file):

```sh
# .env
CHECKS_API_BASE_URL=https://api.example.com
CHECKS_API_KEY=your-api-key
CHECKS_APP_NAME=your-app-name
```

Then load it before running:

```sh
set -a && source .env && set +a
./bin/check-timeline generate <UUID>
```

> ⚠️ Add `.env` to your `.gitignore` to avoid accidentally committing credentials.

---

## Usage

### Basic usage

Fetch live API data and render the timeline for a check UUID:

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77
```

This will:
- Fetch check and payment data from the API
- Write `timeline_8ac70c0e-8760-47b6-92f1-a8bf26e86a77.html` to the current directory
- Automatically open the file in your default browser

---

### With a local check file

Use a saved `check.json` instead of making a live API call. The file must be in the same JSON:API format returned by `GET /public/checks/:id`. No API credentials are needed.

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --check-file check.json
```

If you don't know the UUID up front, omit it — the tool reads `data.id` from the file itself:

```sh
./bin/check-timeline generate --check-file check.json
```

---

### With a local check file and payments file

Pair `--check-file` with `--payments-file` to also load payment events from a saved response. The payments file must be in the same format as `GET /public/checks/:id/payments` (a root array, `{ "data": [...] }`, or `{ "payments": [...] }`).

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --check-file check.json \
  --payments-file payments.json
```

> **Note:** `--payments-file` is only used when `--check-file` is also given. When using the live API, payments are always fetched automatically from `/public/checks/:id/payments`.

### With Raygun exception files

Pass one or more local Raygun JSON files using the `--raygun` flag. Each file should contain a single Raygun exception payload.

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --raygun exceptions/error1.json \
  --raygun exceptions/error2.json
```

The `--raygun` flag can be repeated as many times as needed.

---

### Using glob patterns

Pass a glob pattern to load all matching files in one go:

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --raygun "exceptions/*.json"
```

> ⚠️ Quote glob patterns to prevent your shell from expanding them before they reach the tool.

---

### Controlling output

By default the HTML file is written to the current directory as `timeline_<check_id>.html`. Specify a custom path with `--output`:

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --output /tmp/my_timeline.html
```

To write the file without automatically opening it in the browser:

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --no-open
```

---

### Parallel fetching

By default all sources are fetched sequentially. Enable parallel fetching (each source runs in its own thread) with the `--parallel` flag:

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --raygun "exceptions/*.json" \
  --parallel
```

This is most useful when multiple API sources are configured.

---

### Quiet mode

Suppress all progress output (useful in scripts):

```sh
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 --quiet
```

Errors and warnings are always written to `stderr` regardless of this flag.

---

### All flags at a glance

```
USAGE
  bin/check-timeline generate [UUID] [options]

  UUID is optional when --check-file is given (the id is read from the file).
  UUID is required in all other cases.

OPTIONS
  -c, --check-file PATH       Path to a local check JSON file in the same
                              JSON:API format as the API response.
                              When provided, the live API is skipped for check
                              data. UUID argument becomes optional.

  -p, --payments-file PATH    Path to a local payments JSON file. Only used
                              alongside --check-file. Ignored when using the
                              live API (payments are fetched automatically).

  -r, --raygun PATH           Path or glob to a Raygun exception JSON file.
                              Can be specified multiple times:
                                --raygun a.json --raygun b.json
                                --raygun "exceptions/*.json"

  -o, --output PATH           Output path for the rendered HTML file.
                              Default: ./timeline_<check_id>.html

      --[no-]open             Open the HTML file in the default browser after
                              rendering. Enabled by default; use --no-open to
                              suppress.

  -P, --parallel              Fetch all sources concurrently using threads.
                              Most useful with multiple API sources.

  -q, --quiet                 Suppress progress output. Errors and warnings
                              still go to stderr.

  -v, --version               Print the check-timeline version and exit.

      --help, -h              Print this help message.
```

---

## Data Sources

### Source selection rules

| Scenario | Check data source | Payment data source | PaperTrail versions |
|---|---|---|---|
| API credentials set, no `--check-file` | Live API (`/public/checks/:id`) | Live API (`/public/checks/:id/payments`) | — |
| `--check-file` given | Local file | `--payments-file` if given, otherwise none | Parsed automatically if present in `included` |
| Neither API credentials nor `--check-file` | ❌ Error — no source available | — | — |

Raygun files are always additive — they can be combined with either of the above. PaperTrail versions require no separate flag; they are detected automatically from the check file.

---

### Checks API

**Class:** `CheckTimeline::Sources::ChecksApiSource`

Makes two HTTP GET requests:

#### `GET /public/checks/:id`

Returns a [JSON:API](https://jsonapi.org/) document containing:

| Field | Description |
|---|---|
| `data.id` | Check UUID |
| `data.attributes.check_number` | Human-readable check number |
| `data.attributes.status` | Current status (`open`, `paid`, etc.) |
| `data.attributes.currency` | ISO 4217 currency code (e.g. `GBP`) |
| `data.attributes.total_cents` | Total amount in cents |
| `data.attributes.remaining_cents` | Unpaid amount in cents |
| `data.attributes.line_items` | Array of items on the check |
| `data.attributes.discounts` | Array of applied discounts |
| `data.attributes.service_charges` | Array of service charges |
| `data.attributes.created_at` | ISO 8601 timestamp |
| `data.attributes.updated_at` | ISO 8601 timestamp |
| `data.attributes.paid_at` | ISO 8601 timestamp or `null` |
| `included` | Sideloaded venue and location records |

The following events are produced from this endpoint:

| Event Type | Trigger |
|---|---|
| `check.created` | `created_at` is present |
| `check.updated` | `updated_at` differs from `created_at` |
| `check.paid` | `paid_at` is non-null |
| `check.line_item_added` | One event per entry in `line_items` |
| `check.discount_applied` | One event per entry in `discounts` |
| `check.service_charge_added` | One event per entry in `service_charges` |

> **Note on line item timestamps:** The API does not return individual timestamps for line items. They are assigned a synthetic timestamp of `created_at + N seconds` (one second per item) so they appear after the check creation event but remain grouped correctly.

#### `GET /public/checks/:id/payments`

Returns either a JSON:API array or a wrapper object with a `data` or `payments` key. Both shapes are handled automatically.

| Event Type | Trigger |
|---|---|
| `payment.initiated` | `created_at` or `initiated_at` is present |
| `payment.captured` | `captured_at` or `succeeded_at` is present |
| `payment.failed` | `failed_at` is present |
| `payment.refunded` | `refunded_at` is present |

**Authentication headers sent with every request:**

| Header | Source |
|---|---|
| `X-API-Key` | `CHECKS_API_KEY` env var |
| `X-App-Name` | `CHECKS_APP_NAME` env var |
| `Accept` | `application/json` |
| `User-Agent` | `check-timeline/1.0` |

The HTTP client (Faraday) is configured with automatic retries: up to **3 attempts** with **0.5s base interval** and **exponential backoff**, for connection failures and timeouts only. Non-2xx responses are not retried.

---

### Check File Source

**Class:** `CheckTimeline::Sources::CheckFileSource`

Reads a local JSON file in the same JSON:API format returned by `GET /public/checks/:id`, and optionally a companion payments file. Shares all parsing logic with `ChecksApiSource` via the `ChecksParser` mixin — the events produced are identical regardless of whether the data came from the network or disk.

#### When to use it

- **Offline development** — no API credentials available in your current environment
- **Saved snapshots** — investigating a specific check using a response body you captured earlier (e.g. from a browser dev tools network tab, `curl`, or Postman)
- **Reproducible investigations** — pin the input data so the timeline is identical on every run
- **CI / automated checks** — run against fixture files without needing live API access

#### Usage

```sh
# Check file only — UUID read from data.id in the file
./bin/check-timeline generate --check-file check.json

# Explicit UUID (overrides data.id for event ID generation)
./bin/check-timeline generate 8ac70c0e-8760-47b6-92f1-a8bf26e86a77 \
  --check-file check.json

# Check file + payments file
./bin/check-timeline generate --check-file check.json \
  --payments-file payments.json

# Check file + payments file + Raygun exceptions
./bin/check-timeline generate --check-file check.json \
  --payments-file payments.json \
  --raygun "exceptions/*.json"
```

#### Expected check file format

The file must be the JSON:API envelope exactly as returned by the API:

```json
{
  "data": {
    "id": "8ac70c0e-8760-47b6-92f1-a8bf26e86a77",
    "type": "checks",
    "attributes": {
      "check_number": "174077",
      "status": "open",
      "currency": "GBP",
      "total_cents": 400,
      "line_items": [ ... ],
      "discounts": [],
      "service_charges": [],
      "created_at": "2026-02-26T19:19:36.307Z",
      "updated_at": "2026-02-26T19:19:44.237Z",
      "paid_at": null
    },
    "relationships": { ... }
  },
  "included": [ ... ]
}
```

#### Expected payments file format

Any of the three shapes accepted by the API are supported:

```json
[ { "id": "...", "attributes": { ... } } ]
```
```json
{ "data": [ { "id": "...", "attributes": { ... } } ] }
```
```json
{ "payments": [ { ... } ] }
```

#### Events produced

Identical to those from the live Checks API source:

| Event Type | Trigger |
|---|---|
| `check.created` | `created_at` is present |
| `check.updated` | `updated_at` differs from `created_at` |
| `check.paid` | `paid_at` is non-null |
| `check.line_item_added` | One event per entry in `line_items` |
| `check.discount_applied` | One event per entry in `discounts` |
| `check.service_charge_added` | One event per entry in `service_charges` |
| `payment.initiated` | `created_at` or `initiated_at` (payments file) |
| `payment.captured` | `captured_at` or `succeeded_at` (payments file) |
| `payment.failed` | `failed_at` (payments file) |
| `payment.refunded` | `refunded_at` (payments file) |

---

### PaperTrail Versions

**Class:** `CheckTimeline::Sources::CheckFileSource` (via `ChecksParser#parse_versions_document`)

Reads PaperTrail audit records and converts each database mutation into a discrete timeline event. Version records are detected automatically from the `included` array of the check file wherever `type == "versions"` — no separate file or flag is required.

#### When they appear

PaperTrail versions provide a low-level audit trail that sits *between* the high-level check events. They are included automatically when your check file has them sideloaded. They answer questions like:

- Why did the check status change, and when exactly?
- Which background worker applied the service charge?
- Were there multiple concurrent settlement attempts?
- What was the value of the check at each step of its lifecycle?

#### File format

When the API response includes PaperTrail records (i.e. the `included` array contains objects with `"type": "versions"`), they are parsed automatically when you pass that file to `--check-file`. The relationships block lists the version IDs and the records themselves appear in `included`:

```json
{
  "data": {
    "relationships": {
      "paper_trail_versions": {
        "data": [
          { "type": "versions", "id": 166877028 },
          { "type": "versions", "id": 166877037 }
        ]
      }
    }
  },
  "included": [
    {
      "id": "166877028",
      "type": "versions",
      "attributes": {
        "id": 166877028,
        "item_type": "Persistence::HousepayCheck",
        "item_id": "f76f4463-260a-41d5-8776-61c4f5a93c2f",
        "object_changes": {
          "status": ["open", "closed"],
          "reason": ["Tmed", "FinalTender"]
        },
        "event": "update",
        "whodunnit": "host:chq-master pid:65 verb:POST path:/public/external/dll/checks",
        "created_at": "2026-02-26T20:37:35.832Z"
      }
    }
  ]
}
```

The `object_changes` field uses PaperTrail's standard `[before, after]` diff format for each changed attribute.

#### How titles are derived from `object_changes`

Each version event is given a meaningful title by inspecting the changed fields in priority order:

| Changed field(s) | Example title |
|---|---|
| `status` | `Status: open → closed` |
| `paid_at` (with amount change) | `Check Settled (£9.16 → £0.00)` |
| `amount_due` (no settlement) | `Amount Due: £0.00 → £9.16` |
| `discounts` added | `Discount Applied: Staff Welfare Food 100%` |
| `discounts` removed | `Discount Removed: Staff Welfare Food 100%` |
| `service_charges` added/removed | `Service Charge Added` / `Service Charge Removed` |
| `other_payments` | `Other Payment: O/L VISA` |
| `currency` | `Currency Set: — → GBP` |
| `reason` | `Reason: SvcTotal → Tmed` |
| `event == "create"` | `Check #14233 Created` |
| Anything else | `Updated: field1, field2` |

The event description shows the full human-readable diff for all remaining changed fields not used in the title.

#### Monetary formatting in diffs

Currency is automatically derived from the check file (via `data.attributes.currency`). All monetary fields in `object_changes` (`amount_due`, `subtotal`, `gratuities_cents`, `line_items_tax_cents`, `extra_tax_cents`) are formatted using the correct symbol — e.g. `£9.16` for GBP.

#### What is stored in metadata per version event

| Metadata key | Description |
|---|---|
| `version_id` | PaperTrail version record ID |
| `item_type` | Model class name, e.g. `Persistence::HousepayCheck` |
| `item_id` | Check UUID this version belongs to |
| `event` | `"create"` or `"update"` |
| `whodunnit` | Process / worker / request that triggered the change |
| `changed_fields` | Comma-separated list of all fields that changed |

#### Events produced

| Event Type | Category | Source | Trigger |
|---|---|---|---|
| `version.create` | `:version` | `:paper_trail` | PaperTrail `event == "create"` record |
| `version.update` | `:version` | `:paper_trail` | PaperTrail `event == "update"` record |

---

### Raygun File Source

**Class:** `CheckTimeline::Sources::RaygunFileSource`

Reads one or more local JSON files in the standard Raygun error payload format. Each file represents a single exception occurrence.

#### Expected file format

```json
{
  "OccurredOn": "2024-01-15T10:23:45.000Z",
  "Details": {
    "Error": {
      "ClassName": "RuntimeError",
      "Message": "Something went wrong",
      "StackTrace": [
        {
          "FileName": "app/services/payment_service.rb",
          "LineNumber": 42,
          "MethodName": "process",
          "ClassName": "PaymentService"
        }
      ],
      "InnerError": {
        "ClassName": "Stripe::CardError",
        "Message": "Your card was declined."
      }
    },
    "Request": {
      "Url": "https://api.example.com/public/checks/abc-123/payments",
      "HttpMethod": "POST",
      "IpAddress": "192.168.1.1"
    },
    "Response": {
      "StatusCode": 500
    },
    "User": {
      "Identifier": "user@example.com"
    },
    "Tags": ["payment", "stripe"],
    "UserCustomData": {
      "check_id": "abc-123",
      "venue": "White City House"
    },
    "MachineName": "web-01",
    "Version": "2.4.1"
  }
}
```

Both PascalCase (`OccurredOn`, `ClassName`) and camelCase (`occurredOn`, `className`) keys are supported.

#### Severity mapping

| Condition | Severity |
|---|---|
| Exception class matches `OutOfMemoryError`, `SystemStackError`, `NoMemoryError`, `FatalError`, `Segfault`, `SignalException` | `critical` |
| HTTP response status in `500–599` | `error` |
| HTTP response status in `400–499` | `warning` |
| All other exceptions | `error` |

#### What is extracted per file

- Exception class and message (shown as the event title)
- Request method and URL
- HTTP response status code
- Inner exception (cause chain)
- Top 5 stack frames
- Tags
- Machine name and app version
- User identity
- All `UserCustomData` fields (flattened into metadata)

---

## Architecture

### Project structure

```
check-timeline/
├── bin/
│   └── check-timeline              # CLI entry point (Thor-based)
├── lib/
│   └── check_timeline/
│       ├── check_timeline.rb       # Top-level loader / Zeitwerk setup
│       ├── aggregator.rb           # Orchestrates sources → Timeline
│       ├── currency.rb             # Shared currency formatting module
│       ├── event.rb                # Canonical Event value object (dry-struct)
│       ├── timeline.rb             # Sorted, queryable collection of Events
│       ├── sources/
│       │   ├── base_source.rb      # Abstract base all sources inherit from
│       │   ├── checks_parser.rb    # Shared JSON:API + versions parsing mixin
│       │   ├── checks_api.rb       # Live Checks + Payments API source
│       │   ├── check_file.rb       # Local check.json / payments.json source
│       │   │                       # (versions auto-parsed from included array)
│       │   └── raygun_file.rb      # Local Raygun exception JSON file source
│       └── renderers/
│           └── html_renderer.rb    # Renders Timeline to self-contained HTML
├── templates/
│   └── timeline.html.erb           # ERB template (CSS + JS inlined)
├── config/
│   └── sources.yml                 # Optional static configuration
├── Gemfile
└── README.md
```

---

### Data flow

```
                         ┌─────────────────────────────┐
  UUID ──────────────►  │          Aggregator           │
  (optional w/file)      └──────────────┬──────────────┘
                                        │
          ┌─────────────────────────────┼──────────────────────────┐
          ▼                             ▼                           ▼
┌───────────────────────┐  ┌──────────────────────────┐  ┌──────────────────────┐
│   ChecksApiSource     │  │     CheckFileSource       │  │  RaygunFileSource    │
│   (live API)          │  │     (--check-file)        │  │  (--raygun)          │
│                       │  │                           │  │                      │
│ GET /checks/:id       │  │ reads check.json          │  │ reads *.json files   │
│                       │  │ reads payments.json       │  │                      │
│                       │  │         (optional)        │  │                      │
│                       │  │ auto-parses versions from │  │                      │
│                       │  │ included[] if present     │  │                      │
│  ╔══════════════════╗ │  │  ╔═════════════════════╗  │  │                      │
│  ║  ChecksParser    ║ │  │  ║  ChecksParser       ║  │  │                      │
│  ║  (shared mixin)  ║ │  │  ║  (shared mixin)     ║  │  │                      │
│  ╚══════════════════╝ │  │  ╚═════════════════════╝  │  │                      │
└──────────┬────────────┘  └─────────────┬─────────────┘  └──────────┬───────────┘
           │    [mutually exclusive]      │                            │
           └──────────────────────────────┼────────────────────────────┘
                                          ▼
                               [Event, Event, Event, ...]
                                          │
                                          ▼
                         ┌─────────────────────────────┐
                         │    Timeline.new(events)      │
                         │    (sorted by timestamp)     │
                         └──────────────┬──────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────┐
                         │       HtmlRenderer           │
                         │  timeline_<uuid>.html        │
                         └─────────────────────────────┘
```

> `ChecksApiSource` and `CheckFileSource` both include the `ChecksParser` mixin. All JSON:API event-building logic lives once in that module — the only difference between the two sources is where the document comes from (HTTP vs. disk). The PaperTrail version parser (`parse_versions_document`) also lives in `ChecksParser`, and `CheckFileSource` calls it automatically whenever the check document's `included` array contains version records.

---

### Core models

#### Event

**File:** `lib/check_timeline/event.rb`

The canonical data model. Every source — regardless of origin — must produce an array of `CheckTimeline::Event` instances. This uniform shape is what makes it possible to merge, sort, and render events from completely different systems.

| Attribute | Type | Description |
|---|---|---|
| `id` | `String` | Deterministic SHA1 hash (enables deduplication) |
| `timestamp` | `DateTime` | When the event occurred — the sort key |
| `source` | `Symbol` | Which system produced it: `:checks_api`, `:raygun` |
| `category` | `Symbol` | Broad type: `:check`, `:payment`, `:exception`, `:unknown` |
| `event_type` | `String` | Fine-grained label, e.g. `"payment.captured"` |
| `title` | `String` | Short human-readable headline |
| `description` | `String?` | Optional multi-line detail |
| `severity` | `Symbol` | `:info`, `:warning`, `:error`, or `:critical` |
| `amount` | `Integer?` | Monetary value **in cents** (negative = debit/refund) |
| `currency` | `String` | ISO 4217 code, e.g. `"GBP"` |
| `metadata` | `Hash` | Arbitrary extra fields from the raw payload |

`Event` is a frozen `Dry::Struct` value object — immutable once created.

---

#### Timeline

**File:** `lib/check_timeline/timeline.rb`

A sorted, queryable collection of `Event` objects. Implements `Enumerable`, so you can use `map`, `select`, `each`, etc. directly.

Key methods:

| Method | Returns | Description |
|---|---|---|
| `events` | `Array<Event>` | All events, sorted by timestamp |
| `started_at` | `DateTime?` | Earliest event timestamp |
| `ended_at` | `DateTime?` | Latest event timestamp |
| `duration` | `String` | Human-readable span, e.g. `"2h 14m 33s"` |
| `by_date` | `Hash<Date, Array<Event>>` | Events grouped by calendar date |
| `by_source` | `Hash<Symbol, Array<Event>>` | Events grouped by source |
| `by_category` | `Hash<Symbol, Array<Event>>` | Events grouped by category |
| `filter_by_source(*sources)` | `Timeline` | New Timeline with only matching sources |
| `filter_by_category(*categories)` | `Timeline` | New Timeline with only matching categories |
| `errors` | `Timeline` | New Timeline with only `:error` / `:critical` events |
| `error_count` | `Integer` | Count of error-level events |
| `value_ledger` | `Array<[Event, Integer]>` | Chronological `[event, running_total_cents]` pairs |
| `final_value_cents` | `Integer` | Sum of all `amount` fields |
| `formatted_final_value` | `String` | Final value as a currency string, e.g. `"£4.00"` |
| `severity_counts` | `Hash<Symbol, Integer>` | Count per severity level |

---

### Renderers

**File:** `lib/check_timeline/renderers/html_renderer.rb`

The `HtmlRenderer` class renders a `Timeline` to a self-contained HTML file using an ERB template. All CSS (custom properties, grid layout) and JavaScript (filtering, minimap, value chart) is inlined — no external dependencies, no internet required.

The `TemplateContext` inner class exposes all formatting helpers to the template:

| Helper | Description |
|---|---|
| `format_timestamp(dt)` | `"26 Feb 2026 19:19:36 UTC"` |
| `format_time_only(dt)` | `"19:19:36"` |
| `format_date(dt)` | `"Thursday, 26 February 2026"` |
| `relative_offset(event_ts, base_ts)` | `"+14s"` offset from the first event |
| `severity_style(severity)` | Inline CSS string for the event card |
| `severity_dot_color(severity)` | Hex colour for the timeline dot |
| `category_icon(category)` | Emoji icon for the category |
| `timeline_position(event)` | 0–100 float for minimap positioning |
| `events_json` | Full events array as JSON for the JS minimap |
| `ledger_json` | Value ledger data as JSON for the chart |
| `h(text)` | HTML-escapes a string |
| `nl2br(text)` | Converts newlines to `<br>` tags |

---

### Aggregator

**File:** `lib/check_timeline/aggregator.rb`

Coordinates all sources and merges their events into a single `Timeline`. It does not know anything about individual sources — it only knows that each source responds to `safe_fetch` and returns an array of `Event` objects.

`safe_fetch` (defined on `BaseSource`) wraps the source's `fetch` method with:
- An **availability check** (`available?`) — skips sources that aren't configured
- **Error isolation** — if a source raises, it logs a warning to `stderr` and returns `[]`, so a broken source never takes down the entire run

```ruby
aggregator = CheckTimeline::Aggregator.new(
  check_id: uuid,
  sources: [
    CheckTimeline::Sources::ChecksApiSource.new(check_id: uuid),
    CheckTimeline::Sources::RaygunFileSource.new(check_id: uuid, files: ["error.json"])
  ],
  parallel: false
)

timeline = aggregator.run
```

---

## HTML Output

The rendered HTML file includes:

- **Header bar** — Check UUID, location name, generated timestamp
- **Stats strip** — Total events, error count, active sources, timeline duration, final check value
- **Severity badge row** — Count of info / warning / error / critical events with colour coding
- **Category filter tabs** — Click to show only Check, Payment, or Exception events
- **Source filter chips** — Toggle individual sources on/off
- **Timeline minimap** — A proportional dot strip showing where all events fall in time; click to jump
- **Event cards** — One card per event, showing:
  - Timestamp and relative offset from first event
  - Severity colour bar (left border)
  - Category icon and label
  - Source badge
  - Title and description
  - Formatted amount (where applicable)
  - Expandable metadata table with all raw fields
- **Value ledger chart** — Running total of check value over time, plotted as a step chart
- **Error summary panel** — Collapsible list of all error/critical events at the top for quick triage

---

## Adding a New Data Source

All sources follow the same contract. The `ChecksParser` mixin is a good example of how to share parsing logic between sources that deal with the same document format but retrieve it differently (network vs. file).

To add a new one:

**1. Create a new file in `lib/check_timeline/sources/`:**

```ruby
# lib/check_timeline/sources/my_new_source.rb
module CheckTimeline
  module Sources
    class MyNewSource < BaseSource

      def available?
        # Return false to silently skip this source when not configured.
        # For example, gate on an environment variable:
        !ENV["MY_SOURCE_API_KEY"].to_s.strip.empty?
      end

      def fetch
        # Fetch or read your raw data here.
        raw_records = load_data

        # Map each raw record to a CheckTimeline::Event.
        raw_records.map do |record|
          build_event(
            id:          event_id("my_source", record["id"]),
            timestamp:   parse_timestamp(record["occurred_at"]),
            source:      :my_new_source,
            category:    :unknown,   # :check | :payment | :exception | :unknown
            event_type:  "my_source.thing_happened",
            title:       "Something Happened",
            description: record["message"],
            severity:    :info,      # :info | :warning | :error | :critical
            amount:      nil,
            currency:    "GBP",
            metadata:    record.transform_keys(&:to_s)
          )
        end
      end

      private

      def load_data
        # ... HTTP call, file read, database query, etc.
        []
      end
    end
  end
end
```

**2. Register it in the CLI** (`bin/check-timeline`) by adding a `--my-source` flag and instantiating the new source class alongside the existing ones.

**3. If your new source shares a document format with an existing one**, extract the parsing logic into a new `lib/check_timeline/sources/my_parser.rb` mixin module (following the pattern of `ChecksParser`) and `include` it in both source classes.

**4. Add icon and label metadata** to `HtmlRenderer::SOURCE_META` and `HtmlRenderer::CATEGORY_META` if you introduce new source or category keys.

**Helper methods available to all sources (from `BaseSource`):**

| Method | Description |
|---|---|
| `build_event(**attrs)` | Constructs a `CheckTimeline::Event` |
| `event_id(*components)` | Deterministic SHA1 ID from check_id + components |
| `parse_timestamp(value)` | Parses `String`, `Time`, or `DateTime` to `DateTime` |
| `warn_log(message)` | Writes a `[WARN]` line to `stderr` |

---

## Event Types Reference

| Event Type | Category | Source | Description |
|---|---|---|---|
| `check.created` | `:check` | `:checks_api` | Check was first opened |
| `check.updated` | `:check` | `:checks_api` | Check attributes changed after creation |
| `check.paid` | `:check` | `:checks_api` | Check was fully settled |
| `check.line_item_added` | `:check` | `:checks_api` | A line item was added to the check |
| `check.discount_applied` | `:check` | `:checks_api` | A discount was applied |
| `check.service_charge_added` | `:check` | `:checks_api` | A service charge was added |
| `payment.initiated` | `:payment` | `:checks_api` | Payment was created/initiated |
| `payment.captured` | `:payment` | `:checks_api` | Payment was successfully captured |
| `payment.failed` | `:payment` | `:checks_api` | Payment capture failed |
| `payment.refunded` | `:payment` | `:checks_api` | A refund was processed |
| `version.create` | `:version` | `:paper_trail` | PaperTrail create record — check first persisted |
| `version.update` | `:version` | `:paper_trail` | PaperTrail update record — one or more fields changed |
| `exception.raised` | `:exception` | `:raygun` | An exception was recorded |

---

## Severity Levels

| Level | Colour | Meaning |
|---|---|---|
| `:info` | Blue | Normal operational event |
| `:warning` | Amber | Noteworthy but not a failure (e.g. refund, void, status → closed) |
| `:error` | Red | A failure occurred (failed payment, 5xx exception) |
| `:critical` | Purple | A severe system-level failure (OOM, stack overflow) |

Version events use `:info` by default, with `:warning` applied when a status transition to `closed` is detected.

---

## Troubleshooting

**`Source 'checks_api_source' is not available (skipping)`**
One or more of `CHECKS_API_BASE_URL`, `CHECKS_API_KEY`, or `CHECKS_APP_NAME` is not set. Export all three before running.

**`checks_api_source received HTTP 401`**
Your `CHECKS_API_KEY` or `CHECKS_APP_NAME` is incorrect. Verify both values.

**`checks_api_source received HTTP 404`**
The UUID does not exist in the API's environment. Confirm you are pointing at the right `CHECKS_API_BASE_URL` (production vs. staging) and that the UUID is correct.

**`No sources are configured`**
Neither API credentials nor `--check-file` were provided. You must supply at least one check data source.

**`check.json does not look like a check JSON:API document`**
The file passed to `--check-file` is missing a root `"data"` key. Ensure it is the full API response body, not just the `data.attributes` object.

**`Could not determine check id: no UUID argument was given and "data.id" is missing`**
When omitting the UUID positional argument, `--check-file` must contain a `data.id` field. Add the UUID as the first argument to work around a malformed file.

**`Payments file not found: payments.json — skipping payment events`**
The path passed to `--payments-file` does not exist or is not readable. This is a warning, not a fatal error — the timeline will still render without payment events.

**Version events show but monetary diffs display `n/a`**
The currency could not be derived from the check file. Ensure `data.attributes.currency` is present in your check file. The tool falls back to `GBP` when the field is absent.

**All version events have the same title `Updated: ...`**
The `object_changes` for those versions contain only fields not covered by the priority rules (e.g. internal fields like `simphony_id`). These are intentionally treated as low-signal and displayed with a generic fallback title. The full diff is still visible in the event's expanded metadata.

**`Could not parse JSON in exceptions/error.json`**
The file is not valid JSON, or it is a multi-exception array rather than a single-exception object. Each Raygun file must contain exactly one exception payload object.

**`Raygun file not found: exceptions/error.json`**
The path is relative to the working directory from which you run the command, not relative to the project root. Run from the project root or use absolute paths.

**No browser opens after rendering**
Use `--no-open` to suppress the attempt, and open the file manually. The auto-open feature uses `open` (macOS), `xdg-open` (Linux), or `start` (Windows). Ensure the appropriate command is available on your system.

**Events are out of order / duplicate**
Event IDs are deterministic SHA1 hashes of their content. If you run the tool twice against the same data, IDs will be identical. A future deduplication pass in the `Aggregator` can use these IDs to deduplicate across runs.

---

## Development

### Running with `pry`

```sh
bundle exec pry -r ./lib/check_timeline
```

### Inspecting a timeline without rendering

```ruby
require_relative "lib/check_timeline"

timeline = CheckTimeline::Aggregator.new(
  check_id: "8ac70c0e-8760-47b6-92f1-a8bf26e86a77",
  sources: [
    CheckTimeline::Sources::ChecksApiSource.new(
      check_id: "8ac70c0e-8760-47b6-92f1-a8bf26e86a77"
    )
  ]
).run

puts timeline.count
puts timeline.duration
puts timeline.formatted_final_value

timeline.each { |e| puts "#{e.timestamp} #{e.severity.upcase.ljust(8)} #{e.title}" }
```

### Dependency overview

| Gem | Purpose |
|---|---|
| `thor` | CLI argument parsing and help text |
| `faraday` | HTTP client for API calls |
| `faraday-retry` | Automatic retry middleware for Faraday |
| `erubi` | Fast, modern ERB template engine |
| `dry-struct` | Typed, immutable value objects for `Event` |
| `dry-types` | Type system backing `dry-struct` |
| `zeitwerk` | Auto-loading of the `lib/` directory |
| `pastel` | Terminal colour output |
| `tty-table` | Terminal table rendering |
| `pry` | *(development)* Interactive REPL debugger |

### Key source files for the file-based workflow

| File | Role |
|---|---|
| `lib/check_timeline/currency.rb` | Single authoritative currency formatting module — used everywhere |
| `lib/check_timeline/sources/checks_parser.rb` | Pure parsing mixin — no I/O, no HTTP. Contains all JSON:API event builders (check, payment, version) shared by both API and file sources |
| `lib/check_timeline/sources/checks_api.rb` | HTTP wrapper — fetches the document then delegates to `ChecksParser` |
| `lib/check_timeline/sources/check_file.rb` | File wrapper — reads check and payments documents from disk, auto-parses any version records found in `included`, delegates all parsing to `ChecksParser` |
