# frozen_string_literal: true

require "sidekiq/testing"

module SidekiqTestingInlineWithMiddlewares
  # rubocop:disable Metrics/AbcSize
  def push(job)
    return super unless Sidekiq::Testing.inline?

    job = Sidekiq.load_json(Sidekiq.dump_json(job))
    job["jid"] ||= SecureRandom.hex(12)
    job_class = Object.const_get(job["class"])
    job_instance = job_class.new
    queue = (job_instance.sidekiq_options_hash || {}).fetch("queue", "default")
    server = Sidekiq.respond_to?(:default_configuration) ? Sidekiq.default_configuration : Sidekiq
    server.server_middleware.invoke(job_instance, job, queue) do
      job_instance.perform(*job["args"])
    end
    job["jid"]
  end
  # rubocop:enable Metrics/AbcSize
end

Sidekiq::Client.prepend(SidekiqTestingInlineWithMiddlewares)
