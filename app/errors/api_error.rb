# Application error hierarchy.
#
# Services and models raise these semantic errors; Api::BaseController is the
# single place that maps them to status codes and the JSON error envelope. This
# keeps business logic free of transport concerns (mirrors lib/errors.ts).
class ApiError < StandardError
  attr_reader :status, :code, :details

  def initialize(message, status:, code:, details: nil)
    super(message)
    @status = status
    @code = code
    @details = details
  end

  class BadRequest < ApiError
    def initialize(message = "Bad request", details: nil)
      super(message, status: 400, code: "BAD_REQUEST", details: details)
    end
  end

  class Validation < ApiError
    def initialize(message = "Validation failed", details: nil)
      super(message, status: 422, code: "VALIDATION_ERROR", details: details)
    end

    # The common case: one field-level complaint. Builds the {path, code, message}
    # detail the clients parse, so its shape is defined once rather than hand-rolled
    # at each raise site.
    def self.for(path:, code:, message:)
      new(details: [ { "path" => path, "code" => code, "message" => message } ])
    end
  end

  class Forbidden < ApiError
    def initialize(message = "Forbidden")
      super(message, status: 403, code: "FORBIDDEN")
    end
  end

  class NotFound < ApiError
    def initialize(message = "Resource not found")
      super(message, status: 404, code: "NOT_FOUND")
    end
  end

  class Conflict < ApiError
    def initialize(message = "Conflict", details: nil)
      super(message, status: 409, code: "CONFLICT", details: details)
    end
  end
end
