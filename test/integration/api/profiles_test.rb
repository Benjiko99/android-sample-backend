require "test_helper"

class Api::ProfilesTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "returns counts excluding post-linked albums and videos" do
    get "/api/users/u1/profile", headers: headers
    assert_response :ok
    # u1: posts p1,p6 => 2; albums a1-a4 (pa1 is linked to p1) => 4; videos v1-v3 => 3
    assert_equal({ "postsCount" => 2, "albumsCount" => 4, "videosCount" => 3 },
                 response.parsed_body["data"])
  end

  test "404s for a missing user" do
    get "/api/users/nope/profile", headers: headers
    assert_response :not_found
  end
end
