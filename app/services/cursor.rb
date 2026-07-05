# Keyset (cursor) pagination over an (created_at, id) ordering.
#
# Mirrors lib/cursor.ts: an opaque base64url token encodes "v1:<ms>:<id>".
# Clients treat the token as a black box. The scope orders by
# (created_at DESC, id DESC) and fetches limit + 1 rows to compute has_more
# without a second COUNT query.
module Cursor
  VERSION = "v1"
  DEFAULT_LIMIT = 20
  MAX_LIMIT = 100

  PageMeta = Struct.new(:next_cursor, :has_more) do
    def as_json(*) = { "next_cursor" => next_cursor, "has_more" => has_more }
  end

  Page = Struct.new(:items, :page)

  module_function

  def encode(created_at, id)
    ms = (created_at.to_r * 1000).to_i
    Base64.urlsafe_encode64("#{VERSION}:#{ms}:#{id}", padding: false)
  end

  # Returns { created_at:, id: } or raises ApiError::BadRequest on any bad token.
  def decode(token)
    raw = Base64.urlsafe_decode64(token)
    version, ms, id = raw.split(":", 3)
    raise ApiError::BadRequest, "Invalid cursor" if version != VERSION || ms.blank? || id.blank?

    ms_int = Integer(ms, exception: false)
    raise ApiError::BadRequest, "Invalid cursor" if ms_int.nil?

    { created_at: Time.at(ms_int / 1000.0), id: id }
  rescue ArgumentError
    raise ApiError::BadRequest, "Invalid cursor"
  end

  # Normalizes limit param to an integer in [1, MAX_LIMIT], default DEFAULT_LIMIT.
  def limit(raw)
    return DEFAULT_LIMIT if raw.blank?

    value = Integer(raw, exception: false)
    raise ApiError::Validation.new("Invalid query parameters", details: [
      { "path" => "limit", "code" => "invalid_type", "message" => "Expected number" }
    ]) if value.nil?
    raise ApiError::Validation.new("Invalid query parameters", details: [
      { "path" => "limit", "code" => "too_small", "message" => "limit must be >= 1" }
    ]) if value < 1

    [value, MAX_LIMIT].min
  end

  # Applies the keyset WHERE + ORDER to a relation for the given decoded cursor.
  def scope(relation, cursor)
    relation = relation.order(created_at: :desc, id: :desc)
    return relation unless cursor

    relation.where(
      "created_at < :ts OR (created_at = :ts AND id < :id)",
      ts: cursor[:created_at], id: cursor[:id]
    )
  end

  # Runs a keyset page. `relation` should already be filtered (but not ordered/limited).
  # Rows must respond to #created_at and #id.
  def paginate(relation, cursor_token:, limit_param:)
    lim = limit(limit_param)
    cursor = cursor_token.present? ? decode(cursor_token) : nil

    rows = scope(relation, cursor).limit(lim + 1).to_a
    has_more = rows.length > lim
    rows.pop if has_more

    last = rows.last
    next_cursor = has_more && last ? encode(last.created_at, last.id) : nil

    Page.new(rows, PageMeta.new(next_cursor, has_more))
  end
end
