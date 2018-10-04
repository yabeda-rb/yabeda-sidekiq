# frozen_string_literal: true

require "sidekiq"
require "sidekiq/api"

require "evil/metrics/sidekiq/version"
require "evil/metrics/sidekiq/client_middleware"
require "evil/metrics/sidekiq/server_middleware"

module Evil
  module Metrics
    module Sidekiq
      LONG_RUNNING_JOB_RUNTIME_BUCKETS = [
        0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, # standard (from Prometheus)
        30, 60, 120, 300, 1800, 3600, 21_600 # Sidekiq tasks may be very long-running
      ].freeze

      Evil::Metrics.configure do
        group :sidekiq

        counter :jobs_enqueued_total, comment: "A counter of the total number of jobs sidekiq enqueued."

        next unless ::Sidekiq.server?

        counter   :jobs_executed_total,  comment: "A counter of the total number of jobs sidekiq executed."
        counter   :jobs_success_total,   comment: "A counter of the total number of jobs successfully processed by sidekiq."
        counter   :jobs_failed_total,    comment: "A counter of the total number of jobs failed in sidekiq."
        gauge     :jobs_waiting_count,   comment: "The number of jobs waiting to process in sidekiq."
        gauge     :active_workers_count, comment: "The number of currently running machines with sidekiq workers."
        gauge     :jobs_scheduled_count, comment: "The number of jobs scheduled for later execution."
        gauge     :jobs_retry_count,     comment: "The number of failed jobs waiting to be retried"
        gauge     :jobs_dead_count,      comment: "The number of jobs exceeded their retry count."
        gauge     :active_processes,     comment: "The number of active Sidekiq worker processes."
        histogram :job_runtime, unit: :seconds, per: :job, comment: "A histogram of the job execution time.",
                                buckets: LONG_RUNNING_JOB_RUNTIME_BUCKETS

        collect do
          stats = ::Sidekiq::Stats.new

          stats.queues.each do |k, v|
            sidekiq_jobs_waiting_count.set({ queue: k }, v)
          end
          sidekiq_active_workers_count.set({}, stats.workers_size)
          sidekiq_jobs_scheduled_count.set({}, stats.scheduled_size)
          sidekiq_jobs_dead_count.set({}, stats.dead_size)
          sidekiq_active_processes.set({}, stats.processes_size)
          sidekiq_jobs_retry_count.set({}, stats.retry_size)

          # That is quite slow if your retry set is large
          # I don't want to enable it by default
          # retries_by_queues =
          #     ::Sidekiq::RetrySet.new.each_with_object(Hash.new(0)) do |job, cntr|
          #       cntr[job["queue"]] += 1
          #     end
          # retries_by_queues.each do |queue, count|
          #   sidekiq_jobs_retry_count.set({ queue: queue }, count)
          # end
        end
      end

      class << self
        def labelize(worker, job, queue)
          { queue: queue, worker: worker_class(worker, job) }
        end

        def worker_class(worker, job)
          if defined?(ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper)
            return job["wrapped"] if worker.is_a?(ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper)
          end
          (worker.is_a?(String) ? worker : worker.class).to_s
        end
      end
    end
  end
end
