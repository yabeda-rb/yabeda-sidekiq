# frozen_string_literal: true

module Evil
  module Metrics
    module Sidekiq
      # Client middleware to count number of enqueued jobs
      class ClientMiddleware
        def call(worker, job, queue, _redis_pool)
          labels = Evil::Metrics::Sidekiq.labelize(worker, job, queue)
          Evil::Metrics.sidekiq_jobs_enqueued_total.increment(labels)
          yield
        end
      end
    end
  end
end
