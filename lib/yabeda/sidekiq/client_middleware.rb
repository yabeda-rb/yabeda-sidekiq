# frozen_string_literal: true

module Yabeda
  module Sidekiq
    # Client middleware to count number of enqueued jobs
    class ClientMiddleware
      def call(worker, job, queue, _redis_pool)
        labels = Yabeda::Sidekiq.labelize(worker, job, job["queue"] || queue)
        Yabeda.sidekiq_jobs_enqueued_total.increment(labels)

        if job["queue"] && job["queue"] != queue
          labels = Yabeda::Sidekiq.labelize(worker, job, queue)
          Yabeda.sidekiq_jobs_rerouted_total.increment({ from_queue: queue, to_queue: job["queue"], **labels.except(:queue) })
        end

        yield
      end
    end
  end
end
