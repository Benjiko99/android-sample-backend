module Api
  # Liveness/readiness probe. Returns 503 if the database is unreachable.
  # Renders the payload directly (no `data` envelope), mirroring health/route.ts.
  class HealthController < BaseController
    def show
      healthy = database_up?

      render json: {
        "status" => healthy ? "ok" : "degraded",
        "database" => healthy ? "up" : "down",
        "uptimeSec" => uptime_seconds,
        "timestamp" => Time.now.utc.iso8601
      }, status: healthy ? :ok : :service_unavailable
    end

    private

    def database_up?
      ActiveRecord::Base.connection.execute("SELECT 1")
      true
    rescue StandardError
      false
    end

    def uptime_seconds
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      (now - Rails.application.config.boot_time).round
    end
  end
end
