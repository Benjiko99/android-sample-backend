# Wipes all content tables and re-inserts the sample data that mirrors the
# Android app's SampleData.kt. Ported from lib/reseed.ts. Called by db/seeds.rb
# and by the daily midnight ReseedJob.
module Reseed
  SAMPLE_VIDEO_URL = "https://getsamplefiles.com/download/mp4/sample-5.mp4".freeze
  SAMPLE_IMAGES = [
    "https://getsamplefiles.com/download/jpg/sample-2.jpg",
    "https://getsamplefiles.com/download/jpg/sample-4.jpg",
    "https://getsamplefiles.com/download/jpg/sample-5.jpg"
  ].freeze

  module_function

  def call
    Rails.logger.info("[reseed] Resetting tables…")
    reset_tables
    seed_users
    seed_profile_albums
    seed_post_attachment_albums
    seed_profile_videos
    seed_post_attachment_videos
    seed_posts
    seed_likes_and_bookmarks
    seed_comments
    log_summary
  end

  # ── Deletion (FK-safe order, children first) ─────────────────────────────────
  def reset_tables
    CommentLike.delete_all
    Comment.delete_all
    PostLike.delete_all
    PostBookmark.delete_all
    Post.delete_all
    Photo.delete_all
    Album.delete_all
    Video.delete_all
    User.delete_all
  end

  def seed_users
    Rails.logger.info("[reseed] Seeding users…")
    User.create!([
      { id: "u1", nickname: "Ada Lovelace", handle: "@countess", age: 36, gender: "Woman",
        location: "London, England",
        bio: "Mathematician & writer. The Analytical Engine weaves algebra the way the loom weaves flowers. Poetical science, mostly.",
        follower_count: 128_400, following_count: 212 },
      { id: "u2", nickname: "Grace Hopper", handle: "@amazinggrace", age: 85, gender: "Woman",
        location: "Arlington, Virginia",
        bio: "Rear Admiral. Compiler pioneer. It's easier to ask forgiveness than permission.",
        follower_count: 342_000, following_count: 180 },
      { id: "u3", nickname: "Alan Turing", handle: "@enigma", age: 41, gender: "Man",
        location: "Manchester, England",
        bio: "Asking the only question that matters: can a machine play the imitation game?",
        follower_count: 891_000, following_count: 73 },
      { id: "u4", nickname: "Margaret Hamilton", handle: "@mhamilton", age: 88, gender: "Woman",
        location: "Cambridge, Massachusetts",
        bio: "I coined \"software engineering\" so they'd take the code as seriously as the hardware. Apollo guidance, priority scheduling.",
        follower_count: 154_300, following_count: 96 },
      { id: "u5", nickname: "Linus", handle: "@torvalds", age: 54, gender: "Man",
        location: "Portland, Oregon",
        bio: "Just a hobby, won't be big. Talk is cheap — show me the code.",
        follower_count: 5_200_000, following_count: 12 }
    ])
  end

  def seed_profile_albums
    Rails.logger.info("[reseed] Seeding profile albums…")
    Album.create!([
      { id: "a1", user_id: "u1", title: "Engine Sketches", item_count: 24 },
      { id: "a2", user_id: "u1", title: "Notation Studies", item_count: 12 },
      { id: "a3", user_id: "u1", title: "Loom Patterns", item_count: 18 },
      { id: "a4", user_id: "u1", title: "Letters & Margins", item_count: 7 },
      { id: "a5", user_id: "u2", title: "Mark I Logbook", item_count: 31 },
      { id: "a6", user_id: "u2", title: "The First Bug", item_count: 4 },
      { id: "a7", user_id: "u2", title: "Nanoseconds", item_count: 9 },
      { id: "a8", user_id: "u3", title: "Bombe Rotors", item_count: 16 },
      { id: "a9", user_id: "u3", title: "Morphogenesis", item_count: 22 },
      { id: "a10", user_id: "u4", title: "Rope Memory", item_count: 14 },
      { id: "a11", user_id: "u4", title: "Launch Room", item_count: 28 },
      { id: "a12", user_id: "u4", title: "The Listing", item_count: 6 },
      { id: "a13", user_id: "u5", title: "Build Logs", item_count: 42 },
      { id: "a14", user_id: "u5", title: "Diving Trips", item_count: 11 }
    ])
  end

  def seed_post_attachment_albums
    Rails.logger.info("[reseed] Seeding post attachment albums…")
    [
      { id: "pa1", user_id: "u1", title: "Engine sketches" },
      { id: "pa4", user_id: "u4", title: "Launch room" }
    ].each do |attrs|
      album = Album.create!(attrs.merge(item_count: SAMPLE_IMAGES.length))
      SAMPLE_IMAGES.each_with_index do |url, i|
        album.photos.create!(url: url, position: i)
      end
    end
  end

  def seed_profile_videos
    Rails.logger.info("[reseed] Seeding profile videos…")
    Video.create!([
      { id: "v1", user_id: "u1", title: "Weaving algebra on the Analytical Engine", url: SAMPLE_VIDEO_URL, duration_seconds: 222, view_count: 41_200 },
      { id: "v2", user_id: "u1", title: "Note G, explained", url: SAMPLE_VIDEO_URL, duration_seconds: 615, view_count: 12_800 },
      { id: "v3", user_id: "u1", title: "Poetical science", url: SAMPLE_VIDEO_URL, duration_seconds: 95, view_count: 8_400 },
      { id: "v4", user_id: "u2", title: "How a compiler thinks", url: SAMPLE_VIDEO_URL, duration_seconds: 1325, view_count: 220_000 },
      { id: "v5", user_id: "u2", title: "A nanosecond in your hand", url: SAMPLE_VIDEO_URL, duration_seconds: 184, view_count: 1_200_000 },
      { id: "v6", user_id: "u3", title: "The imitation game", url: SAMPLE_VIDEO_URL, duration_seconds: 742, view_count: 980_000 },
      { id: "v7", user_id: "u3", title: "On computable numbers", url: SAMPLE_VIDEO_URL, duration_seconds: 2010, view_count: 154_000 },
      { id: "v8", user_id: "u3", title: "Breaking Enigma", url: SAMPLE_VIDEO_URL, duration_seconds: 366, view_count: 512_300 },
      { id: "v9", user_id: "u4", title: "The 1202 alarm", url: SAMPLE_VIDEO_URL, duration_seconds: 488, view_count: 1_540_000 },
      { id: "v10", user_id: "u4", title: "Software, taken seriously", url: SAMPLE_VIDEO_URL, duration_seconds: 277, view_count: 96_500 },
      { id: "v11", user_id: "u5", title: "Talk is cheap", url: SAMPLE_VIDEO_URL, duration_seconds: 132, view_count: 3_100_000 },
      { id: "v12", user_id: "u5", title: "Git in ten minutes", url: SAMPLE_VIDEO_URL, duration_seconds: 631, view_count: 2_050_000 },
      { id: "v13", user_id: "u5", title: "Why monolithic", url: SAMPLE_VIDEO_URL, duration_seconds: 1442, view_count: 740_000 }
    ])
  end

  def seed_post_attachment_videos
    Rails.logger.info("[reseed] Seeding post attachment videos…")
    Video.create!([
      { id: "pv3", user_id: "u3", title: "The imitation game, in five seconds", url: SAMPLE_VIDEO_URL, duration_seconds: 5, view_count: 48_900 },
      { id: "pv5", user_id: "u5", title: "Booting the kernel", url: SAMPLE_VIDEO_URL, duration_seconds: 5, view_count: 2_050_000 }
    ])
  end

  def seed_posts
    Rails.logger.info("[reseed] Seeding posts…")
    p1_at = 4.minutes.ago
    p2_at = 38.minutes.ago
    p3_at = 2.hours.ago
    p4_at = 6.hours.ago
    p5_at = 1.day.ago
    p6_at = 3.days.ago

    Post.create!([
      { id: "p1", author_id: "u1", title: "The engine weaves algebraic patterns",
        body: "Just like the Jacquard loom weaves flowers and leaves. A machine need not be limited to numbers — give it the right notation and it can compose.",
        created_at: p1_at, updated_at: p1_at, like_count: 128, comment_count: 17, album_id: "pa1" },
      { id: "p2", author_id: "u2", title: "Found the bug",
        body: "It was an actual moth, taped into the logbook at 15:45. First recorded case of debugging being literal. Onward to the next nanosecond.",
        created_at: p2_at, updated_at: p2_at, like_count: 342, comment_count: 51 },
      { id: "p3", author_id: "u3", title: "Can machines think?",
        body: "The question is too meaningless to deserve discussion. So replace it: can a machine play the imitation game well enough that you can't tell?",
        created_at: p3_at, updated_at: p3_at, like_count: 891, comment_count: 203, video_id: "pv3" },
      { id: "p4", author_id: "u4", title: "Priority scheduling saved the landing",
        body: "Three minutes before touchdown the computer flashed a 1202 alarm. Because we designed it to shed low-priority work under overload, it kept the essentials running. Apollo 11 landed anyway.",
        created_at: p4_at, updated_at: p4_at, like_count: 1543, comment_count: 88, album_id: "pa4" },
      { id: "p5", author_id: "u5", title: "Just a hobby, won't be big",
        body: "I'm doing a (free) operating system — nothing professional like GNU — for 386(486) AT clones. It probably never will support anything other than AT hard disks, as that's all I have. :)",
        created_at: p5_at, updated_at: p5_at, like_count: 5200, comment_count: 612, video_id: "pv5" },
      { id: "p6", author_id: "u1", title: "On numbers and music",
        body: "Supposing the relations of pitched sounds could be expressed by the engine, it might compose elaborate pieces of music of any degree of complexity.",
        created_at: p6_at, updated_at: p6_at, like_count: 64, comment_count: 5 }
    ])
  end

  def seed_likes_and_bookmarks
    Rails.logger.info("[reseed] Seeding likes and bookmarks…")
    PostLike.create!([
      { user_id: "u1", post_id: "p1" },
      { user_id: "u1", post_id: "p4" }
    ])
    PostBookmark.create!([
      { user_id: "u1", post_id: "p2" },
      { user_id: "u1", post_id: "p4" }
    ])
  end

  def seed_comments
    Rails.logger.info("[reseed] Seeding comments…")
    Comment.create!([
      { id: "c1p1", post_id: "p1", author_id: "u2", text: "The loom analogy is poetic — your best one yet.", like_count: 24, created_at: 3.minutes.ago },
      { id: "c2p1", post_id: "p1", author_id: "u3", text: "Did Ada ever see a Jacquard loom? I believe she did.", like_count: 9, created_at: 1.minute.ago },
      { id: "c1p2", post_id: "p2", author_id: "u3", text: "First recorded debugging session. The logbook is incredible.", like_count: 61, created_at: 35.minutes.ago },
      { id: "c2p2", post_id: "p2", author_id: "u4", text: "It's always the actual bugs, isn't it.", like_count: 18, created_at: 20.minutes.ago },
      { id: "c1p3", post_id: "p3", author_id: "u1", text: "The imitation game is really a test of our assumptions, not the machine.", like_count: 44, created_at: 115.minutes.ago },
      { id: "c2p3", post_id: "p3", author_id: "u4", text: "The question itself is the insight. Brilliant framing.", like_count: 12, created_at: 90.minutes.ago },
      { id: "c3p3", post_id: "p3", author_id: "u5", text: "Philosophy embedded in a practical test.", like_count: 3, created_at: 38.minutes.ago },
      { id: "c1p4", post_id: "p4", author_id: "u1", text: "The 1202 alarm story is one of the best in engineering. They kept going.", like_count: 31, created_at: 350.minutes.ago },
      { id: "c2p4", post_id: "p4", author_id: "u3", text: "Priority scheduling is underappreciated in computing history.", like_count: 7, created_at: 3.hours.ago },
      { id: "c1p5", post_id: "p5", author_id: "u2", text: "Famous last words. The kernel is still running.", like_count: 22, created_at: 20.hours.ago },
      { id: "c2p5", post_id: "p5", author_id: "u1", text: "I love how this turned out to be just a hobby.", like_count: 15, created_at: 16.hours.ago },
      { id: "c1p6", post_id: "p6", author_id: "u2", text: "The Analytical Engine composing music — a beautiful idea.", like_count: 11, created_at: 2.days.ago }
    ])
  end

  def log_summary
    Rails.logger.info(
      "[reseed] Done: #{User.count} users, #{Post.count} posts, #{Album.count} albums, " \
      "#{Video.count} videos, #{Comment.count} comments."
    )
  end
end
