module Api
  # Base for all JSON API controllers. Owns the response envelopes and the single
  # error-mapping point (mirrors lib/http.ts + the `route` wrapper).
  #
  # Success shapes:
  #   { "data": ... }                    single resource
  #   { "data": [...], "page": ... }     cursor-paginated collection
  # Error shape:
  #   { "error": { "code", "message", "details"? } }
  class BaseController < ActionController::API
    # JSON bodies are read at the top level, not nested under a model root key.
    wrap_parameters false

    # Registered last = matched first. Keep the generic StandardError first so
    # more specific handlers below take precedence.
    rescue_from StandardError, with: :handle_internal
    rescue_from ActionController::ParameterMissing, with: :handle_bad_request
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_bad_json
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
    rescue_from ApiError, with: :handle_api_error

    private

    def current_user_id
      @current_user_id ||= request.headers["X-User-Id"].presence || "u1"
    end

    # ── Envelopes ────────────────────────────────────────────────────────────
    def render_data(data, status: :ok, headers: {})
      headers.each { |k, v| response.set_header(k, v) }
      render json: { "data" => data }, status: status
    end

    def render_created(data)
      render json: { "data" => data }, status: :created
    end

    def render_cursor(page, included: nil)
      body = { "data" => page.items, "page" => page.page.as_json }
      body["included"] = included unless included.nil?
      render json: body
    end

    # Validates an optional enum query param, returning the value (or nil when
    # absent) and raising a 422 with the standard details shape otherwise.
    def validate_enum!(value, param:, allowed:)
      return nil if value.blank?
      return value if allowed.include?(value)

      expected = allowed.map { |v| "'#{v}'" }.join(" | ")
      # Not ApiError::Validation.for — this one carries its own envelope message
      # ("Invalid query parameters"), which clients may be matching on.
      raise ApiError::Validation.new("Invalid query parameters", details: [
        { "path" => param, "code" => "invalid_enum_value", "message" => "Invalid option: expected #{expected}" }
      ])
    end

    # ── Error handlers ───────────────────────────────────────────────────────
    def handle_api_error(error)
      render_error(error.status, error.code, error.message, error.details)
    end

    def handle_not_found(error)
      render_error(404, "NOT_FOUND", error.message)
    end

    def handle_record_invalid(error)
      render_error(422, "VALIDATION_ERROR", "Validation failed", format_model_errors(error.record))
    end

    def handle_bad_request(error)
      render_error(400, "BAD_REQUEST", error.message)
    end

    def handle_bad_json(_error)
      render_error(400, "BAD_REQUEST", "Request body must be valid JSON")
    end

    def handle_internal(error)
      Rails.logger.error("[api] Unhandled error: #{error.class}: #{error.message}")
      Rails.logger.error(error.backtrace&.first(10)&.join("\n"))
      message = Rails.env.production? ? "Internal server error" : error.message
      render_error(500, "INTERNAL", message)
    end

    def render_error(status, code, message, details = nil)
      body = { "code" => code, "message" => message }
      body["details"] = details unless details.nil?
      render json: { "error" => body }, status: status
    end

    def format_model_errors(record)
      record.errors.map do |error|
        {
          "path" => error.attribute.to_s.camelize(:lower),
          "code" => error.type.to_s,
          "message" => error.full_message
        }
      end
    end
  end
end
