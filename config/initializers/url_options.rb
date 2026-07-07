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
    { host: "localhost", port: 3000 }
  end

Rails.application.routes.default_url_options = options
