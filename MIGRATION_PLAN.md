# Mosaic — Next.js → Ruby on Rails Migration Plan

Recreate the `android-sample-server` backend (Next.js 16 + Prisma 7 + SQLite) as a
Ruby on Rails 8 backend in this project, preserving the **exact HTTP contract** the
Android client (`uno.lux.sample`) depends on.

> The consumer is a native Android app that treats the wire format as a fixed contract.
> Field names (camelCase), response envelopes, status codes, cursor tokens, and the
> `X-User-Id` convention must be reproduced **byte-for-byte**. This is the primary
> constraint that shapes every decision below.

---

## 1. Goals & non-goals

**Goals**
- Reproduce every endpoint in `src/app/api/**` with identical request/response shapes.
- Preserve the layered architecture (routes → services → repositories) using idiomatic
  Rails equivalents (controllers → services / query objects → models).
- Keep zero-setup SQLite and the daily midnight reseed behavior.
- Match seed data exactly (fixed IDs `u1`–`u5`, `p1`–`p6`, etc.) so the Android app's
  hardcoded `X-User-Id: u1` and any fixture assumptions keep working.

**Non-goals**
- Real authentication (the app uses the `X-User-Id` header shim — we keep it).
- The stale CRUD endpoints described in `README.md` (`POST /posts`, `/albums`, `/videos`).
  Those are **not** in the current implementation; we mirror the actual routes only.

---

## 2. Source → target architecture mapping

| Next.js / Prisma layer            | Rails 8 equivalent                                        |
| --------------------------------- | --------------------------------------------------------- |
| App Router `route.ts` handlers    | `Api::*Controller` actions under `/api` namespace         |
| `lib/http.ts` (envelopes + `route` wrapper) | `Api::BaseController` render helpers + `rescue_from` |
| `lib/errors.ts` (AppError tree)   | `app/errors/api_error.rb` hierarchy                       |
| `lib/cursor.ts` (keyset paging)   | `CursorPagination` concern / `lib/cursor.rb`              |
| `lib/current-user.ts`             | `current_user_id` before_action in BaseController         |
| `lib/env.ts`                      | Rails credentials / `config/database.yml` (SQLite default)|
| Zod schemas (`*.schema.ts`)       | Model validations + a params/validation object per action |
| `*.repository.ts` (Prisma access) | ActiveRecord models + scopes / query objects              |
| `*.service.ts` (business rules)   | `app/services/*.rb` POROs returning serializer input      |
| DTO mappers (`toXxxDTO`)          | PORO serializers in `app/serializers/*.rb`                |
| `prisma/schema.prisma`            | `db/migrate/*` + `db/schema.rb`                            |
| `lib/reseed.ts` + `seed.ts`       | `Reseed` service + `db/seeds.rb`                           |
| `instrumentation.ts` (node-cron)  | Solid Queue recurring job (`config/recurring.yml`)        |
| Vitest tests                      | Minitest model + request (integration) tests              |

---

## 3. Framework configuration decisions

1. **Keep the generated full-stack app but namespace the API.** All endpoints live under
   `/api`, returning JSON only. We don't need to regenerate as `--api`; we simply build
   `Api::BaseController < ActionController::API` (or `ActionController::Base` with layouts
   off) and mount controllers under the `api` namespace.
2. **SQLite** in all environments (matches source; Rails 8 default). No external services.
3. **JSON is camelCase.** Rails defaults to snake_case. We will **not** rely on ActiveRecord
   `as_json`; instead every response goes through a hand-written PORO serializer that emits
   the exact DTO keys (`createdAt`, `likeCount`, `isLiked`, `authorId`, `videoUrl`,
   `avatarUrl`, `followerCount`, …). This mirrors the `toXxxDTO` functions 1:1 and avoids
   global key-transform magic.
4. **String primary keys.** IDs are app-defined strings (`u1`, `p1`, `pa1`, cuid-style),
   not integers. All tables use `id: :string`. Runtime-created rows (comments) get a
   generated opaque id (`"c" + SecureRandom` / a cuid gem) in a `before_create`.
5. **Timestamps** are rendered as ISO-8601 strings (`created_at.iso8601`), matching
   `Date.toISOString()`.

---

## 4. Data model (migrations)

One migration per table (or a single `init_social` migration). Column parity with
`schema.prisma`, `snake_case` columns, string PKs, and the same indexes.

**users** — `id` (PK, string), `nickname`, `handle` (unique), `age:int?`, `gender?`,
`location?`, `bio?`, `avatar_url?`, `follower_count:int default 0`,
`following_count:int default 0`.

**posts** — `id` (PK), `author_id → users`, `title`, `body`, `created_at`, `updated_at`,
`like_count:int d0`, `comment_count:int d0`, `album_id → albums?`, `video_id → videos?`.
Indexes: `(created_at, id)`, `author_id`, `album_id`, `video_id`.

**post_likes** — composite PK `(user_id, post_id)`; FK post `on_delete: cascade`.
**post_bookmarks** — composite PK `(user_id, post_id)`; FK post cascade.

**comments** — `id` (PK), `post_id → posts (cascade)`, `author_id → users`, `text`,
`like_count:int d0`, `created_at`. Indexes: `(post_id, created_at, id)`, `author_id`.

**comment_likes** — composite PK `(user_id, comment_id)`; FK comment cascade.

**albums** — `id` (PK), `user_id → users`, `title`, `item_count:int d0`, `created_at`,
`updated_at`. Index: `user_id`.

**photos** — `id` (PK), `album_id → albums (cascade)`, `url`, `caption?`,
`position:int d0`. Index: `album_id`.

**videos** — `id` (PK), `user_id → users`, `title`, `url`, `thumbnail_url?`,
`duration_seconds:int?`, `view_count:int d0`, `created_at`, `updated_at`. Index: `user_id`.

**Composite-PK note:** Rails migrations support `create_table :post_likes, primary_key:
[:user_id, :post_id]`. Models declare `self.primary_key = [:user_id, :post_id]` (Rails 7.1+
composite keys) or are treated as join records with a unique index — either works; composite
PK matches Prisma most closely.

**Models & associations** (`app/models`):
- `User` → has_many :posts (author), :albums, :videos, :comments, :post_likes,
  :post_bookmarks, :comment_likes.
- `Post` belongs_to :author (User), :album (optional), :video (optional); has_many
  :comments (dependent: :destroy via cascade), :post_likes, :post_bookmarks.
- `Comment` belongs_to :post, :author; has_many :comment_likes.
- `Album` belongs_to :user; has_many :photos (ordered by position), :posts.
- `Photo` belongs_to :album. `Video` belongs_to :user; has_many :posts.
- `PostLike`, `PostBookmark`, `CommentLike` join models.

---

## 5. Serialization layer (`app/serializers`)

Plain Ruby objects, one per DTO, mirroring the TS mappers exactly:

- `UserSerializer.full(user)` → id, nickname, handle, age, gender, location, bio,
  avatarUrl, followerCount, followingCount.
- `UserSerializer.minimal(user)` → id, handle, nickname, avatarUrl.
- `AlbumSerializer` → id, title, itemCount, `images` = first 3 photo urls (by position).
- `VideoSerializer` → id, title, durationSeconds, viewCount, `videoUrl` (from `url`).
- `PostSerializer.full(post, viewer)` → …, isLiked, isBookmarked, **author** (full),
  album|null, video|null. (For `GET /posts/:id`.)
- `PostSerializer.feed_item(post, viewer)` → same but **authorId** instead of embedded
  author. (For `/feed` and `/users/:id/posts`.)
- `CommentSerializer` → id, text, createdAt, likeCount, isLiked, author (full).

`isLiked` / `isBookmarked` are computed from viewer-scoped associations preloaded per
request (see §6.4), exactly as `post.likes.length > 0` in the source.

---

## 6. Shared infrastructure

### 6.1 Response envelopes (`Api::BaseController`)
- `render_data(obj, status: :ok, headers: {})` → `{ "data": obj }`.
- `render_created(obj)` → 201 `{ "data": obj }`.
- `render_cursor(items, page)` → `{ "data": items, "page": { next_cursor:, has_more: } }`.
- Feed action renders `{ data:, included?:, page: }` **directly** (not wrapped again),
  matching `feed/route.ts` which returns the compound doc verbatim.

### 6.2 Error handling (`rescue_from` in BaseController)
Map to the envelope `{ "error": { code, message, details? } }`:

| Exception                              | Status | code               |
| -------------------------------------- | ------ | ------------------ |
| `ApiError::BadRequest`                 | 400    | `BAD_REQUEST`      |
| `ApiError::Validation` / param errors  | 422    | `VALIDATION_ERROR` |
| `ApiError::Forbidden`                  | 403    | `FORBIDDEN`        |
| `ApiError::NotFound` / `RecordNotFound`| 404    | `NOT_FOUND`        |
| `ApiError::Conflict`                   | 409    | `CONFLICT`         |
| anything else                          | 500    | `INTERNAL`         |

Validation `details` must be an array of `{ path, code, message }` (mirroring the Zod
issue formatter in `http.ts`). Build this from ActiveModel errors / the params validator.
In production, 500 messages are generic ("Internal server error"); in dev, echo the message.

### 6.3 Current user
`before_action` sets `@current_user_id = request.headers["X-User-Id"].presence || "u1"`.
Exposed as `current_user_id`. No DB lookup (matches source — it's just an id string).

### 6.4 Cursor pagination (`lib/cursor.rb`)
Reproduce the keyset scheme:
- Token = base64url of `"v1:<created_at_ms>:<id>"`; opaque to clients. Decode failures →
  `ApiError::BadRequest("Invalid cursor")`.
- Query: `WHERE (created_at < c.ts) OR (created_at = c.ts AND id < c.id)`
  `ORDER BY created_at DESC, id DESC LIMIT limit + 1`.
- Fetch `limit + 1`, pop the extra to compute `has_more`, encode `next_cursor` from the
  last returned row. Returns `{ items:, page: { next_cursor:, has_more: } }`.
- `limit` param: integer, 1..100, default 20. `cursor` optional string.
- A `Paginatable` model scope applies the where/order; the `Cursor` helper handles
  encode/decode + the `limit + 1` trimming. To match viewer-scoped `isLiked`, preload
  `post_likes`/`post_bookmarks` filtered to `current_user_id` (Prisma did
  `likes: { where: { userId } }`) — use a scoped `preload` / `includes` with a
  conditional association or a manual per-page lookup keyed by id.

---

## 7. Endpoint-by-endpoint plan

All under `namespace :api`. Left column = current Next.js route.

| Route (source)                                   | Rails route → controller#action        | Response |
| ------------------------------------------------ | --------------------------------------- | -------- |
| `GET /api/health`                                | `Api::HealthController#show`            | `{ status, database, uptimeSec, timestamp }`, 503 if `SELECT 1` fails |
| `GET /api/feed`                                  | `Api::FeedController#index`             | `{ data:[PostFeedItem], included?:{users:[UserMinimal]}, page }`; `?include=author` triggers `included`; `?cursor`, `?limit` |
| `GET /api/posts/:id`                             | `Api::PostsController#show`             | `{ data: PostFull }`; 404 if missing |
| `POST /api/posts/:id/like`                       | `Api::PostsController#toggle_like`      | `{ data: { isLiked, likeCount } }` |
| `POST /api/posts/:id/bookmark`                   | `Api::PostsController#toggle_bookmark`  | `{ data: { isBookmarked } }` |
| `GET /api/posts/:id/comments`                    | `Api::CommentsController#index`         | `{ data:[Comment], page }`; `?cursor`, `?limit` |
| `POST /api/posts/:id/comments`                   | `Api::CommentsController#create`        | 201 `{ data: Comment }`; body `{ text }`; 404 if post missing |
| `POST /api/posts/:id/comments/:commentId/like`   | `Api::CommentsController#toggle_like`   | `{ data: { isLiked, likeCount } }` |
| `GET /api/users/:id`                             | `Api::UsersController#show`             | `{ data: UserFull }` + `Cache-Control: max-age=60, stale-while-revalidate=300`; 404 |
| `PATCH /api/users/:id`                           | `Api::UsersController#update`           | `{ data: UserFull }`; 403 unless `id == current_user_id`; 404; partial update |
| `GET /api/users/:id/profile`                     | `Api::ProfilesController#show`          | `{ data: { postsCount, albumsCount, videosCount } }`; 404 |
| `GET /api/users/:id/posts`                       | `Api::PostsController#by_user`          | `{ data:[PostFeedItem], page }`; `?type=photo|video|text`, `?cursor`, `?limit` |

`routes.rb` sketch:
```ruby
namespace :api do
  get "health", to: "health#show"
  get "feed",   to: "feed#index"

  resources :posts, only: :show do
    member do
      post :like,     to: "posts#toggle_like"
      post :bookmark, to: "posts#toggle_bookmark"
    end
    resources :comments, only: [:index, :create] do
      post :like, on: :member, to: "comments#toggle_like"
    end
  end

  resources :users, only: [:show, :update] do
    get :profile, on: :member
    get :posts,   on: :member, to: "posts#by_user"
  end
end
```

---

## 8. Business logic (services)

- **`Posts::ToggleLike`** — in a transaction: if a `PostLike(user,post)` exists, delete it
  and `decrement` `like_count`; else create it and `increment`. Return `{ isLiked, likeCount }`.
- **`Posts::ToggleBookmark`** — same pattern, no counter → `{ isBookmarked }`.
- **`Comments::ToggleLike`** — mirrors ToggleLike against `comment_likes` / `comment.like_count`.
- **`Comments::Create`** — 404 unless post exists; in a transaction create comment and
  `increment` `post.comment_count`; return the comment (with author + viewer like flag).
- **`Posts::ListByUser`** — filter by `author_id`, plus `type`: `photo` → `album_id NOT NULL`,
  `video` → `video_id NOT NULL`, `text` → both NULL; keyset paginate.
- **`Feed::List`** — keyset paginate all posts; if `include=author`, collect distinct
  `author_id`s, load those users, emit `included.users` as UserMinimal.
- **`Profiles::Stats`** — 404 unless user exists; counts: posts where `author_id = id`;
  albums where `user_id = id AND no linked posts`; videos where `user_id = id AND no linked
  posts` (Prisma `posts: { none: {} }` → `WHERE NOT EXISTS (posts …)`).
- **`Users::UpdateProfile`** — 403 unless `id == current_user_id`; 404 if missing; apply
  only keys **present** in the body (distinguish absent vs explicit `null`); validate
  nickname (1..50), age (13..120, nullable), gender (`Man`/`Woman`, nullable), bio (1..500,
  nullable), avatarUrl (valid URL, nullable). `handle`, `location`, counters are not editable.

---

## 9. Seeds & daily reseed

- **`Reseed` service** (`app/services/reseed.rb`) ports `lib/reseed.ts`: wipes all tables in
  FK-safe order, then inserts the exact fixtures — 5 users (`u1`–`u5`), 14 profile albums,
  2 post-attachment albums (`pa1`, `pa4`) with 3 photos each, 13 profile videos + 2 post
  videos (`pv3`, `pv5`), 6 posts (`p1`–`p6`) with the same relative timestamps
  (`minsAgo/hoursAgo/daysAgo` → Ruby `n.minutes.ago` etc.), u1's likes/bookmarks, and 12
  comments with fixed ids and like counts. Same sample image/video URLs.
- **`db/seeds.rb`** calls `Reseed.call` so `bin/rails db:seed` works.
- **Daily reset**: register a Solid Queue recurring job. Add to `config/recurring.yml`:
  ```yaml
  production:
    daily_reseed:
      class: ReseedJob
      schedule: "every day at midnight"   # 0 0 * * *
  ```
  `ReseedJob#perform` calls `Reseed.call`. (Solid Queue is already installed in this app.)

---

## 10. Testing (Minitest)

Port the existing Vitest coverage to Rails request + model tests:
- **Cursor** (`test/lib/cursor_test.rb`) ← `cursor.test.ts`: encode/decode round-trip,
  malformed-token rejection, `has_more`/trim logic.
- **Posts** (request + service) ← `post.service.test.ts`, `post.schema.test.ts`: show,
  toggle like/bookmark idempotency & counters, `by_user` type filters, DTO shape.
- **Comments** ← `comment.service.test.ts`: list paging, create increments count, 404 on
  missing post, toggle like.
- **Feed** ← `feed.service.test.ts`: ordering, `include=author` → `included.users`.
- **Users** ← `user.service.test.ts`: show 404, PATCH 403 for non-owner, partial update,
  validation failures → 422 with `details`.
- **Contract tests**: assert camelCase keys, envelope shapes, and status codes for every
  endpoint — the safety net for Android compatibility.

---

## 11. Implementation order (phased)

1. **Config**: API base controller, `/api` namespace, JSON-only, SQLite confirmed, initial
   commit already done.
2. **Schema**: migrations for all 9 tables + indexes; models + associations; string PKs and
   comment id generation.
3. **Infra**: `ApiError` hierarchy, `rescue_from` error envelope, `current_user_id`,
   `Cursor` + pagination scope, serializers.
4. **Read endpoints**: health, `GET /posts/:id`, `GET /users/:id`, `GET /users/:id/profile`,
   `GET /users/:id/posts`, `GET /feed`, `GET /posts/:id/comments`.
5. **Write endpoints**: post like/bookmark, comment create, comment like, `PATCH /users/:id`.
6. **Seeds**: `Reseed` service + `db/seeds.rb`; verify data matches source counts
   (5 users, 6 posts, 16 albums, 15 videos, 12 comments).
7. **Scheduler**: `ReseedJob` + `config/recurring.yml`.
8. **Tests**: port suites; add contract tests.
9. **Verify parity**: run both servers, diff responses for each endpoint with `X-User-Id: u1`.

---

## 12. Parity checklist & risks

- [ ] **camelCase everywhere** — the single biggest divergence risk vs. Rails defaults.
- [ ] **Envelope precision** — feed returns `{data,included?,page}` un-nested; everything
      else is `{data}` or `{data,page}`. Errors are `{error:{code,message,details?}}`.
- [ ] **`page` keys** are `next_cursor` / `has_more` (snake_case *inside* page — matches
      source exactly; do not camelCase these).
- [ ] **Viewer-scoped `isLiked`/`isBookmarked`** — must reflect `X-User-Id`, per row.
- [ ] **Counter integrity** — like/comment counts updated transactionally with join rows.
- [ ] **Profile counts** exclude post-linked albums/videos.
- [ ] **Partial PATCH** — absent key ≠ explicit null; validation error format matches Zod.
- [ ] **Cursor token format** — clients treat as opaque, but keep `v1:<ms>:<id>` base64url
      so tokens remain stable and decodable.
- [ ] **Cache-Control** header on `GET /users/:id`.
- [ ] **Health** returns 503 + `status:"degraded"` when the DB check fails.

**Open questions for you:**
1. Keep the exact `v1:<ms>:<id>` cursor format, or is any opaque token fine (clients treat
   it as a black box)? Keeping it is safest.
2. Composite primary keys for join tables (closest to Prisma) vs. surrogate id + unique
   index (more conventional Rails)? Recommend composite PKs for fidelity.
3. Test framework: Minitest (Rails default, already set up) vs. RSpec? Recommend Minitest.
