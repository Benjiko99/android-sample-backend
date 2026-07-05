require "test_helper"

# Mirrors cursor.test.ts — encode/decode round-trip and token validation.
class CursorTest < ActiveSupport::TestCase
  test "round-trips a (created_at, id) position" do
    at = Time.utc(2026, 6, 23, 10, 27, 14, 500_000) # includes sub-second component
    token = Cursor.encode(at, "abc123")
    decoded = Cursor.decode(token)

    assert_equal "abc123", decoded[:id]
    assert_equal (at.to_r * 1000).to_i, (decoded[:created_at].to_r * 1000).to_i
  end

  test "produces a url-safe token without padding" do
    token = Cursor.encode(Time.now, "id")
    assert_no_match(/[+\/=]/, token)
  end

  test "rejects a malformed token" do
    assert_raises(ApiError::BadRequest) { Cursor.decode("not-base64-@@@") }
  end

  test "rejects a wrong-version token" do
    bad = Base64.urlsafe_encode64("v2:123:abc", padding: false)
    assert_raises(ApiError::BadRequest) { Cursor.decode(bad) }
  end

  test "rejects a token with a non-numeric timestamp" do
    bad = Base64.urlsafe_encode64("v1:notanumber:abc", padding: false)
    assert_raises(ApiError::BadRequest) { Cursor.decode(bad) }
  end

  test "limit clamps to the [1, MAX] range with a default" do
    assert_equal Cursor::DEFAULT_LIMIT, Cursor.limit(nil)
    assert_equal 1, Cursor.limit("1")
    assert_equal Cursor::MAX_LIMIT, Cursor.limit("9999")
  end

  test "limit rejects non-numeric and out-of-range values" do
    assert_raises(ApiError::Validation) { Cursor.limit("abc") }
    assert_raises(ApiError::Validation) { Cursor.limit("0") }
  end
end
