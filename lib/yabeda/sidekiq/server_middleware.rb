# frozen_string_literal: true

module Yabeda
  module Sidekiq
    # Sidekiq worker middleware
    class ServerMiddleware
      # See https://github.com/mperham/sidekiq/discussions/4971
      JOB_RECORD_CLASS = defined?(::Sidekiq::JobRecord) ? ::Sidekiq::JobRecord : ::Sidekiq::Job

      # rubocop: disable Metrics/AbcSize, Metrics/MethodLength:
      def call(worker, job, queue)
        custom_tags = Yabeda::Sidekiq.custom_tags(worker, job).to_h
        labels = Yabeda::Sidekiq.labelize(worker, job, queue).merge(custom_tags)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          job_instance = JOB_RECORD_CLASS.new(job)
          Yabeda.sidekiq_job_latency.measure(labels, job_instance.latency)
          Yabeda::Sidekiq.jobs_started_at[labels][job["jid"]] = start
          Yabeda.with_tags(**custom_tags) do
            yield
          end
          Yabeda.sidekiq_jobs_success_total.increment(labels)
        rescue Exception => e # rubocop: disable Lint/RescueException
          jobs_failed_labels = labels.dup
          jobs_failed_labels[:error] = e.class.name if Yabeda::Sidekiq.config.label_for_error_class_on_sidekiq_jobs_failed
          Yabeda.sidekiq_jobs_failed_total.increment(jobs_failed_labels)
          raise
        ensure
          Yabeda.sidekiq_job_runtime.measure(labels, elapsed(start))
          Yabeda.sidekiq_jobs_executed_total.increment(labels)
          Yabeda::Sidekiq.jobs_started_at[labels].delete(job["jid"])
        end
      end
      # rubocop: enable Metrics/AbcSize, Metrics/MethodLength:

      private

      def elapsed(start)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(3)
      end
    end
  end
end
