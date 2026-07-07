# Absolute-URL generation (e.g. Active Storage avatar links in UserSerializer)
# happens outside a request context, so it needs a configured host. The Android
# client reaches the production server at http://65.108.255.16:8080.
options =
  case Rails.env
  when "production"
    { host: ENV.fetch("APP_HOST", "65.108.255.16"), port: ENV.fetch("APP_PORT", "8080").to_i }
  when "test"
    { host: "example.com" }
  else
    { host: "localhost", port: 3000 }
  end

Rails.application.routes.default_url_options = options
