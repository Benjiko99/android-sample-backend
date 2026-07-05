# Daily database reset. Scheduled via config/recurring.yml (Solid Queue),
# replacing the node-cron scheduler in the original instrumentation.ts.
class ReseedJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("[scheduler] Running daily database reset…")
    Reseed.call
  rescue StandardError => e
    Rails.logger.error("[scheduler] Daily database reset failed: #{e.class}: #{e.message}")
    raise
  end
end
