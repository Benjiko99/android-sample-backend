# README

This README would normally document whatever steps are necessary to get the
application up and running.

## System dependencies

**ffmpeg**, for local development only — the Docker image and CI install it
themselves. `VideoMetadata` reads an uploaded video's length and resolution with
`ffprobe`, and `VideoThumbnail` extracts a poster frame with `ffmpeg`; without it
a video post still publishes, but its duration is stored as 0, its resolution as
null, and it gets no thumbnail.

```bash
sudo apt install ffmpeg
```

Things you may want to cover:

* Ruby version

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
