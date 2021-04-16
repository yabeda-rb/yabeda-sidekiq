# frozen_string_literal: true

require "sidekiq"
require "sidekiq/api"

require "yabeda"
require "yabeda/sidekiq/version"
require "yabeda/sidekiq/client_middleware"
require "yabeda/sidekiq/server_middleware"

module Yabeda
  module Sidekiq
    LONG_RUNNING_JOB_RUNTIME_BUCKETS = [
      0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, # standard (from Prometheus)
      30, 60, 120, 300, 1800, 3600, 21_600, # Sidekiq tasks may be very long-running
    ].freeze

    Yabeda.configure do
      group :sidekiq

      counter :jobs_enqueued_total, tags: %i[queue worker], comment: "A counter of the total number of jobs sidekiq enqueued."

      next unless ::Sidekiq.server?

      counter   :jobs_executed_total,  tags: %i[queue worker], comment: "A counter of the total number of jobs sidekiq executed."
      counter   :jobs_success_total,   tags: %i[queue worker], comment: "A counter of the total number of jobs successfully processed by sidekiq."
      counter   :jobs_failed_total,    tags: %i[queue worker], comment: "A counter of the total number of jobs failed in sidekiq."

      gauge     :jobs_waiting_count,   tags: %i[queue], comment: "The number of jobs waiting to process in sidekiq."
      gauge     :active_workers_count, tags: [],        comment: "The number of currently running machines with sidekiq workers."
      gauge     :jobs_scheduled_count, tags: [],        comment: "The number of jobs scheduled for later execution."
      gauge     :jobs_retry_count,     tags: [],        comment: "The number of failed jobs waiting to be retried"
      gauge     :jobs_dead_count,      tags: [],        comment: "The number of jobs exceeded their retry count."
      gauge     :active_processes,     tags: [],        comment: "The number of active Sidekiq worker processes."
      gauge     :queue_latency,        tags: %i[queue], comment: "The queue latency, the difference in seconds since the oldest job in the queue was enqueued"
      gauge     :job_max_runtime,      tags: %i[queue worker], comment: "The actual job runtime"

      histogram :job_latency, comment: "The job latency, the difference in seconds between enqueued and running time",
                              unit: :seconds, per: :job,
                              tags: %i[queue worker],
                              buckets: LONG_RUNNING_JOB_RUNTIME_BUCKETS
      histogram :job_runtime, comment: "A histogram of the job execution time.",
                              unit: :seconds, per: :job,
                              tags: %i[queue worker],
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

        ::Sidekiq::Queue.all.each do |queue|
          sidekiq_queue_latency.set({ queue: queue.name }, queue.latency)
        end

        Yabeda::Sidekiq.track_max_job_runtime
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

    ::Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add ServerMiddleware
      end
      config.client_middleware do |chain|
        chain.add ClientMiddleware
      end
    end

    ::Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.add ClientMiddleware
      end
    end

    class << self
      attr_accessor :previous_max_job_runtimes

      def labelize(worker, job, queue)
        { queue: queue, worker: worker_class(worker, job) }
      end

      def worker_class(worker, job)
        if defined?(ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper)
          if worker.is_a?(ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper) || worker == ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper
            return job["wrapped"].to_s
          end
        end
        (worker.is_a?(String) || worker.is_a?(Class) ? worker : worker.class).to_s
      end

      def custom_tags(worker, job)
        return {} unless worker.respond_to?(:yabeda_tags)

        worker.method(:yabeda_tags).arity.zero? ? worker.yabeda_tags : worker.yabeda_tags(*job["args"])
      end
    end

    self.previous_max_job_runtimes = Set.new

    # rubocop: disable Metrics/AbcSize
    def self.track_max_job_runtime
      now = Time.now.utc
      job_runtimes = ::Sidekiq::Workers.new.each_with_object({}) do |(_process, _thread, msg), result|
        payload = msg["payload"]
        tags = { queue: payload["queue"], worker: payload["wrapped"] || payload["class"] }

        duration = now - Time.at(msg["run_at"])
        result[tags] = duration if !result[tags] || result[tags] < duration
      end

      job_runtimes.each do |tags, duration|
        Yabeda.sidekiq.job_max_runtime.set(tags, duration)
      end

      # Reset durations to zero for finished jobs we saw earlier
      previous_max_job_runtimes.subtract(job_runtimes.keys)
      previous_max_job_runtimes.each do |tags|
        Yabeda.sidekiq.job_max_runtime.set(tags, 0)
      end

      # Populate previous runtimes for the next time
      self.previous_max_job_runtimes = Set.new(job_runtimes.keys)
    end
    # rubocop: enable Metrics/AbcSize
  end
end
