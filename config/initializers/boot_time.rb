# Captured once at boot so the health probe can report process uptime,
# mirroring Node's process.uptime().
Rails.application.config.boot_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
