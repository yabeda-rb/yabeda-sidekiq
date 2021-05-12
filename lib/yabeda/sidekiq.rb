# frozen_string_literal: true

require "sidekiq"
require "sidekiq/api"

require "yabeda"
require "yabeda/sidekiq/version"
require "yabeda/sidekiq/client_middleware"
require "yabeda/sidekiq/server_middleware"
require "yabeda/sidekiq/config"

module Yabeda
  module Sidekiq
    LONG_RUNNING_JOB_RUNTIME_BUCKETS = [
      0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, # standard (from Prometheus)
      30, 60, 120, 300, 1800, 3600, 21_600, # Sidekiq tasks may be very long-running
    ].freeze

    Yabeda.configure do
      config = Config.new

      group :sidekiq

      counter :jobs_enqueued_total, tags: %i[queue worker], comment: "A counter of the total number of jobs sidekiq enqueued."

      if ::Sidekiq.server?
        counter   :jobs_executed_total,  tags: %i[queue worker], comment: "A counter of the total number of jobs sidekiq executed."
        counter   :jobs_success_total,   tags: %i[queue worker], comment: "A counter of the total number of jobs successfully processed by sidekiq."
        counter   :jobs_failed_total,    tags: %i[queue worker], comment: "A counter of the total number of jobs failed in sidekiq."

        gauge     :running_job_runtime,  tags: %i[queue worker], aggregation: :max, unit: :seconds,
                                         comment: "How long currently running jobs are running (useful for detection of hung jobs)"

        histogram :job_latency, comment: "The job latency, the difference in seconds between enqueued and running time",
                                unit: :seconds, per: :job,
                                tags: %i[queue worker],
                                buckets: LONG_RUNNING_JOB_RUNTIME_BUCKETS
        histogram :job_runtime, comment: "A histogram of the job execution time.",
                                unit: :seconds, per: :job,
                                tags: %i[queue worker],
                                buckets: LONG_RUNNING_JOB_RUNTIME_BUCKETS
      end

      # Metrics not specific for current Sidekiq process, but representing state of the whole Sidekiq installation (queues, processes, etc)
      # You can opt-out from collecting these by setting YABEDA_SIDEKIQ_COLLECT_CLUSTER_METRICS to falsy value (+no+ or +false+)
      if config.collect_cluster_metrics # defaults to +::Sidekiq.server?+
        gauge     :jobs_waiting_count,   tags: %i[queue], comment: "The number of jobs waiting to process in sidekiq."
        gauge     :active_workers_count, tags: [],        comment: "The number of currently running machines with sidekiq workers."
        gauge     :jobs_scheduled_count, tags: [],        comment: "The number of jobs scheduled for later execution."
        gauge     :jobs_retry_count,     tags: [],        comment: "The number of failed jobs waiting to be retried"
        gauge     :jobs_dead_count,      tags: [],        comment: "The number of jobs exceeded their retry count."
        gauge     :active_processes,     tags: [],        comment: "The number of active Sidekiq worker processes."
        gauge     :queue_latency,        tags: %i[queue], comment: "The queue latency, the difference in seconds since the oldest job in the queue was enqueued"
      end

      collect do
        Yabeda::Sidekiq.track_max_job_runtime if ::Sidekiq.server?

        next unless config.collect_cluster_metrics

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

      # Hash of hashes containing all currently running jobs' start timestamps
      # to calculate maximum durations of currently running not yet completed jobs
      # { { queue: "default", worker: "SomeJob" } => { "jid1" => 100500, "jid2" => 424242 } }
      attr_accessor :jobs_started_at

      def track_max_job_runtime
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ::Yabeda::Sidekiq.jobs_started_at.each do |labels, jobs|
          oldest_job_started_at = jobs.values.min
          oldest_job_duration = oldest_job_started_at ? (now - oldest_job_started_at).round(3) : 0
          Yabeda.sidekiq.running_job_runtime.set(labels, oldest_job_duration)
        end
      end
    end

    self.jobs_started_at = Concurrent::Hash.new { |hash, key| hash[key] = Concurrent::Hash.new }
  end
end
