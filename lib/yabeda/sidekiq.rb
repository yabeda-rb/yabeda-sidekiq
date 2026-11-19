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
    def self.config
      @config ||= Config.new
    end

    Yabeda.configure do
      config = ::Yabeda::Sidekiq.config

      group :sidekiq

      counter :jobs_enqueued_total, tags: %i[queue worker], comment: "A counter of the total number of jobs sidekiq enqueued."
      counter :jobs_rerouted_total, tags: %i[from_queue to_queue worker], comment: "A counter of the total number of rerouted jobs sidekiq enqueued."

      if config.declare_process_metrics # defaults to +::Sidekiq.server?+
        failed_total_tags = config.label_for_error_class_on_sidekiq_jobs_failed ? %i[queue worker error] : %i[queue worker]

        counter   :jobs_executed_total,  tags: %i[queue worker], comment: "A counter of the total number of jobs sidekiq executed."
        counter   :jobs_success_total,   tags: %i[queue worker], comment: "A counter of the total number of jobs successfully processed by sidekiq."
        counter   :jobs_failed_total,    tags: failed_total_tags, comment: "A counter of the total number of jobs failed in sidekiq."

        gauge     :running_job_runtime,  tags: %i[queue worker], aggregation: :max, unit: :seconds,
                                         comment: "How long currently running jobs are running (useful for detection of hung jobs)"

        histogram :job_latency, comment: "The job latency, the difference in seconds between enqueued and running time",
                                unit: :seconds, per: :job,
                                tags: %i[queue worker],
                                buckets: config.buckets
        histogram :job_runtime, comment: "A histogram of the job execution time.",
                                unit: :seconds, per: :job,
                                tags: %i[queue worker],
                                buckets: config.buckets
      end

      # Metrics not specific for current Sidekiq process, but representing state of the whole Sidekiq installation (queues, processes, etc)
      # You can opt-out from collecting these by setting YABEDA_SIDEKIQ_COLLECT_CLUSTER_METRICS to falsy value (+no+ or +false+)
      if config.collect_cluster_metrics # defaults to +::Sidekiq.server?+
        retry_count_tags = config.retries_segmented_by_queue ? %i[queue] : []
        dead_count_tags = config.dead_segmented_by_queue ? %i[queue] : []
        scheduled_count_tags = config.scheduled_segmented_by_queue ? %i[queue] : []

        gauge     :jobs_waiting_count,   tags: %i[queue],            aggregation: :most_recent, comment: "The number of jobs waiting to process in sidekiq."
        gauge     :active_workers_count, tags: [],                   aggregation: :most_recent,
                                         comment: "The number of currently running machines with sidekiq workers."
        gauge     :jobs_scheduled_count, tags: scheduled_count_tags, aggregation: :most_recent, comment: "The number of jobs scheduled for later execution."
        gauge     :jobs_retry_count,     tags: retry_count_tags,     aggregation: :most_recent, comment: "The number of failed jobs waiting to be retried"
        gauge     :jobs_dead_count,      tags: dead_count_tags,      aggregation: :most_recent, comment: "The number of jobs exceeded their retry count."
        gauge     :active_processes,     tags: [],                   aggregation: :most_recent, comment: "The number of active Sidekiq worker processes."
        gauge     :queue_latency,        tags: %i[queue],            aggregation: :most_recent,
                                         comment: "The queue latency, the difference in seconds since the oldest job in the queue was enqueued"
      end

      collect do
        Yabeda::Sidekiq.track_max_job_runtime if ::Sidekiq.server?

        next unless config.collect_cluster_metrics

        stats = ::Sidekiq::Stats.new
        queue_sizes = stats.queues

        queue_sizes.each do |k, v|
          sidekiq_jobs_waiting_count.set({ queue: k }, v)
        end
        sidekiq_active_workers_count.set({}, stats.workers_size)
        sidekiq_active_processes.set({}, stats.processes_size)

        queues_for_latency =
          if config.filter_queues_by_current_process
            process_queues = ::Sidekiq.default_configuration.queues.uniq
            ::Sidekiq::Queue.all.select { |q| process_queues.include?(q.name) }
          else
            ::Sidekiq::Queue.all
          end
        queues_for_latency.each do |queue|
          sidekiq_queue_latency.set({ queue: queue.name }, queue.latency)
        end

        if config.retries_segmented_by_queue
          Yabeda::Sidekiq.set_jobs_count_by_queue(sidekiq_jobs_retry_count, ::Sidekiq::RetrySet.new, queue_sizes.keys)
        else
          sidekiq_jobs_retry_count.set({}, stats.retry_size)
        end

        if config.dead_segmented_by_queue
          Yabeda::Sidekiq.set_jobs_count_by_queue(sidekiq_jobs_dead_count, ::Sidekiq::DeadSet.new, queue_sizes.keys)
        else
          sidekiq_jobs_dead_count.set({}, stats.dead_size)
        end

        if config.scheduled_segmented_by_queue
          Yabeda::Sidekiq.set_jobs_count_by_queue(sidekiq_jobs_scheduled_count, ::Sidekiq::ScheduledSet.new, queue_sizes.keys)
        else
          sidekiq_jobs_scheduled_count.set({}, stats.scheduled_size)
        end
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
        worker = job["wrapped"] || worker
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

      # Counts jobs in a Sidekiq job set (retry, dead, scheduled) per queue.
      # Known queues without jobs in the set are reported as zero, so their series don't go stale.
      def set_jobs_count_by_queue(metric, job_set, known_queues)
        counts = job_set.each_with_object(Hash.new(0)) { |job, cntr| cntr[job["queue"]] += 1 }
        (known_queues | counts.keys).each { |queue| metric.set({ queue: queue }, counts[queue]) }
      end
    end

    self.jobs_started_at = Concurrent::Map.new { |hash, key| hash[key] = Concurrent::Map.new }
  end
end
