# Absolute-URL generation (e.g. Active Storage avatar links in UserSerializer)
# happens outside a request context, so it needs a configured host. The Android
# client reaches production at https://mosaic.tree-among-shrubs.com.
options =
  case Rails.env
  when "production"
    { host: ENV.fetch("APP_HOST", "mosaic.tree-among-shrubs.com"),
      protocol: ENV.fetch("APP_PROTOCOL", "https") }
  when "test"
    { host: "example.com" }
  else
    # APP_HOST is overridable in development too: an emulator or a phone on the LAN
    # can't resolve "localhost" to this machine, and the stored images are served
    # from whatever host is baked into these URLs (e.g. APP_HOST=10.0.2.2).
    { host: ENV.fetch("APP_HOST", "localhost"), port: ENV.fetch("APP_PORT", 3000) }
  end

Rails.application.routes.default_url_options = options
