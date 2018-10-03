# frozen_string_literal: true

module Evil
  module Metrics
    module Sidekiq
      # Sidekiq worker middleware
      class ServerMiddleware
        def call(worker, job, queue)
          labels = Evil::Metrics::Sidekiq.labelize(worker, job, queue)
          start = Time.now
          begin
            yield
            Evil::Metrics.sidekiq_jobs_success_total.increment(labels)
          rescue Exception # rubocop: disable Lint/RescueException
            Evil::Metrics.sidekiq_jobs_failed_total.increment(labels)
            raise
          ensure
            Evil::Metrics.sidekiq_job_runtime.measure(labels, elapsed(start))
            Evil::Metrics.sidekiq_jobs_executed_total.increment(labels)
          end
        end

        private

        def elapsed(start)
          (Time.now - start).round(3)
        end
      end
    end
  end
end
