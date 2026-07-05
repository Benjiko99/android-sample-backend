require "test_helper"

class Api::HealthTest < ActionDispatch::IntegrationTest
  test "reports ok with database up" do
    get "/api/health"
    assert_response :ok
    body = response.parsed_body
    assert_equal "ok", body["status"]
    assert_equal "up", body["database"]
    assert_kind_of Integer, body["uptimeSec"]
    assert body["timestamp"].present?
  end
end
