# frozen_string_literal: true

module Yabeda
  module Sidekiq
    # Sidekiq worker middleware
    class ServerMiddleware
      def call(worker, job, queue)
        labels = Yabeda::Sidekiq.labelize(worker, job, queue)
        start = Time.now
        begin
          Yabeda.sidekiq_job_latency.measure(labels, job.latency)
          yield
          Yabeda.sidekiq_jobs_success_total.increment(labels)
        rescue Exception # rubocop: disable Lint/RescueException
          Yabeda.sidekiq_jobs_failed_total.increment(labels)
          raise
        ensure
          Yabeda.sidekiq_job_runtime.measure(labels, elapsed(start))
          Yabeda.sidekiq_jobs_executed_total.increment(labels)
        end
      end

      private

      def elapsed(start)
        (Time.now - start).round(3)
      end
    end
  end
end
