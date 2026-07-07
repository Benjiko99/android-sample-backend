require "test_helper"

class Api::UsersTest < ActionDispatch::IntegrationTest
  setup { Reseed.call }

  test "GET /api/users/:id returns the full profile and a Cache-Control header" do
    get "/api/users/u2", headers: headers
    assert_response :ok
    user = response.parsed_body["data"]
    assert_equal "Grace Hopper", user["nickname"]
    assert_equal %w[id nickname handle age gender location bio avatarUrl followerCount followingCount].sort,
                 user.keys.sort
    # Rails normalizes Cache-Control and adds a scope token (private); the
    # meaningful directives from the source are preserved.
    cache_control = response.headers["Cache-Control"]
    assert_match(/max-age=60/, cache_control)
    assert_match(/stale-while-revalidate=300/, cache_control)
  end

  test "GET /api/users/:id 404s for a missing user" do
    get "/api/users/nope", headers: headers
    assert_response :not_found
  end

  test "PATCH applies a partial update and clears fields with explicit null" do
    patch "/api/users/u1", params: { nickname: "Ada L.", bio: nil }, as: :json, headers: headers
    assert_response :ok
    user = response.parsed_body["data"]
    assert_equal "Ada L.", user["nickname"]
    assert_nil user["bio"]
    assert_equal "@countess", user["handle"] # untouched
  end

  test "PATCH is forbidden for another user" do
    patch "/api/users/u2", params: { nickname: "Nope" }, as: :json, headers: headers("u1")
    assert_response :forbidden
    assert_equal "FORBIDDEN", response.parsed_body["error"]["code"]
  end

  test "PATCH validation errors return 422 with details" do
    patch "/api/users/u1", params: { age: 5, gender: "Robot" }, as: :json, headers: headers
    assert_response :unprocessable_entity
    body = response.parsed_body["error"]
    assert_equal "VALIDATION_ERROR", body["code"]
    paths = body["details"].map { |d| d["path"] }
    assert_includes paths, "age"
    assert_includes paths, "gender"
  end

  test "PATCH uploads an avatar file and returns an absolute avatarUrl" do
    assert_not User.find("u1").avatar.attached?, "avatar should start unattached"

    patch "/api/users/u1",
          params: { nickname: "Ada", avatar: fixture_file_upload("avatar.png", "image/png") },
          headers: headers
    assert_response :ok

    assert User.find("u1").avatar.attached?
    avatar_url = response.parsed_body["data"]["avatarUrl"]
    assert_match %r{\Ahttp://example\.com/.*active_storage}, avatar_url
  end

  test "PATCH rejects an avatar that is not a supported image" do
    patch "/api/users/u1",
          params: { avatar: fixture_file_upload("not_an_image.txt", "text/plain") },
          headers: headers
    assert_response :unprocessable_entity
    assert_equal "avatar", response.parsed_body["error"]["details"].first["path"]
    assert_not User.find("u1").avatar.attached?
  end
end
