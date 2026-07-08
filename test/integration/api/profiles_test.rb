require "test_helper"

class Api::ProfilesTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "returns the user's post count" do
    get "/api/users/u1/profile", headers: headers
    assert_response :ok
    assert_equal({ "postsCount" => 2 }, response.parsed_body["data"]) # u1 authored p1 and p6
  end

  test "404s for a missing user" do
    get "/api/users/nope/profile", headers: headers
    assert_response :not_found
  end
end
