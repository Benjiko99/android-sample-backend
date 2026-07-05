# Seeds the sample social data (users, posts, comments, albums, videos) that
# mirrors the Android app's SampleData.kt. Idempotent: Reseed.call wipes and
# re-inserts every time.
Reseed.call
