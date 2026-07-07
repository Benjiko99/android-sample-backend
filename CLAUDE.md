# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Rails 8 (API-only) backend for **Mosaic**, a social feed consumed by an Android client. It is a **line-for-line port of a prior TypeScript/Node backend**: nearly every Ruby file carries a comment naming the `*.ts` file it mirrors (e.g. `feed.service.ts`, `post.schema.ts`, `lib/cursor.ts`, `lib/errors.ts`). When changing behavior, preserve the wire contract and the layering the source established — the port fidelity is intentional. There is no frontend; the ERb/Stimulus/Propshaft scaffolding is stock Rails and unused.

## Commands

```bash
bin/setup                 # install gems, prepare DB, seed, start server (--skip-server to not boot)
bin/dev                   # run the server (thin wrapper over bin/rails server)
bin/rails db:seed         # (re)load sample data via Reseed.call
bin/rails test            # run the test suite (Minitest)
bin/rails test test/integration/api/posts_test.rb          # single file
bin/rails test test/integration/api/posts_test.rb:42       # single test at line 42
bin/rubocop               # lint (rubocop-rails-omakase); -a to autocorrect
bin/brakeman --no-pager   # static security scan
```

CI (`.github/workflows/ci.yml`) runs Brakeman, `importmap audit`, RuboCop, and `bin/rails db:test:prepare test test:system` on every PR. Match those before pushing.

## Architecture

Request flow is a strict pipeline; keep concerns in their layer:

```
routes (config/routes.rb, all under /api)
  → Api::*Controller        thin: parse params, call a service, render an envelope
    → *Service (app/services) business logic — the real work lives here (module_function modules)
      → models / serializers  ActiveRecord + plain-hash serializers
```

- **`Api::BaseController`** (`app/controllers/api/base_controller.rb`) is the spine. It owns the JSON envelopes (`render_data`, `render_created`, `render_cursor`) and is the **single place** that maps exceptions to HTTP status + error body via `rescue_from`. `rescue_from` order matters: registered-last matches first, so the generic `StandardError` is declared first and specific handlers after. Controllers and services never build error responses by hand — they raise.
- **`ApiError`** (`app/errors/api_error.rb`) is the semantic error hierarchy (`NotFound`, `Validation`, `Forbidden`, `Conflict`, …). Services/models raise these; the base controller translates them. This keeps business logic free of transport concerns — do not reference status codes outside the base controller.
- **Services are `module_function` modules**, not classes — stateless functions grouped by resource (`PostsService`, `FeedService`, `CommentsService`, `UsersService`, `ProfilesService`). Cross-cutting helpers are their own modules: `Cursor`, `LikeToggle`, `ViewerFlags`, `Reseed`.
- **Serializers** (`app/serializers/*`) are `module_function` modules returning plain hashes with **camelCase string keys** (`"authorId"`, `"likeCount"`) — that is the wire format the Android client expects. Two projections recur: `full` (embeds the author object) vs `feed_item`/`minimal` (author by `authorId` reference). Timestamps are `iso8601`.

### Response envelopes (defined once in the base controller)

```
{ "data": ... }                                 single resource
{ "data": [...], "page": { next_cursor, has_more }, "included"? }   collection
{ "error": { "code", "message", "details"? } }  error
```

### Cross-cutting mechanisms to know before editing

- **Auth is a stub.** `current_user_id` reads the `X-User-Id` header, defaulting to `"u1"`. There are no sessions/passwords. In tests, use the `headers(user_id)` helper from `test/test_helper.rb`.
- **Cursor pagination** (`app/services/cursor.rb`) is keyset-based over `(created_at DESC, id DESC)`. The cursor is an opaque base64url `v1:<ms>:<id>` token; it fetches `limit + 1` rows to compute `has_more` without a COUNT. Any paginated endpoint should route through `Cursor.paginate`. Bad tokens/limits raise `ApiError`.
- **Viewer-scoped flags** (`isLiked`/`isBookmarked`) are resolved **once per page** via `ViewerFlags` (batched `pluck` → `Set`) to avoid N+1. When adding a per-viewer boolean, follow this pattern rather than per-row queries.
- **String primary keys.** All domain tables use opaque string ids, not integers. `GeneratesStringId` (`app/models/concerns/generates_string_id.rb`) assigns `"<id_prefix><random>"` on create when no id is supplied; each model sets its own `id_prefix` (`"p"` posts, `"c"` comments…). Seed rows carry fixed ids like `"p1"`. Treat ids as opaque.
- **Like/counter consistency.** `LikeToggle.call` toggles the join row and the owner's `like_count` in one transaction. Reuse it for any new likeable resource.

### Avatars / Active Storage

User avatars are uploaded files (`has_one_attached :avatar`), not URL strings. Key points:
- `UsersController#update` accepts **multipart** with an `avatar` file field. Upload validation (content type sniffed from bytes via Marcel, size ≤ 10 MB) lives in `UsersService#attach_avatar`, **not** as a model validation — attaching to an already-persisted record saves immediately, so a `save!` validation would fire too late.
- `UserSerializer#avatar_url` emits an absolute **proxy** URL (`rails_storage_proxy_url`) so the Android Coil loader streams bytes in one hop. Because this runs outside a request, the host comes from `config/initializers/url_options.rb` (`default_url_options`), which reads `APP_HOST`/`APP_PROTOCOL` in production.
- Empty text fields on a multipart update clear nullable columns (`age`, `gender`, `bio`); `nickname` is required. See `UsersService::EDITABLE_KEYS`/`NULLABLE_KEYS`.

### Sample data & reseeding

`Reseed.call` (`app/services/reseed.rb`) wipes all content tables (FK-safe order, purging avatars first) and inserts fixed sample data mirroring the Android app's `SampleData.kt` — the 5 users are computing pioneers with fixed ids `u1`–`u5`. It runs from `db/seeds.rb` and daily at midnight via `ReseedJob`, scheduled in `config/recurring.yml` (Solid Queue). Editing sample content means editing `Reseed`.

## Stack & infrastructure

- **Rails 8.0, Ruby 3.4.4, SQLite** (via `sqlite3` gem, string-keyed schema in `db/schema.rb`).
- **Solid Queue / Solid Cache / Solid Cable** — DB-backed adapters; no Redis. Jobs run in-process under Puma (`SOLID_QUEUE_IN_PUMA=true`).
- **Deploy: Kamal** (`config/deploy.yml`) to a Docker host, joining a shared `kamal-proxy` and routed by host `mosaic.tree-among-shrubs.com`. Image `benjiko99/mosaic`. Needs `RAILS_MASTER_KEY` and `KAMAL_REGISTRY_PASSWORD`.
- Health probes: `/up` (Rails default) and `/api/health` (the app's own).

## Conventions

- Match the port's style: a service is a `module_function` module; a serializer returns camelCase string-keyed hashes; errors are raised as `ApiError`/`ActiveRecord` exceptions and never rendered directly.
- Tests are Minitest integration tests under `test/integration/api/`, asserting the JSON envelopes and status codes end-to-end. Add coverage there for new endpoints; unit-test standalone helpers (see `test/services/cursor_test.rb`).
- `MIGRATION_PLAN.md` documents the TS→Rails port and is useful background when a mirrored `.ts` reference is unclear.
