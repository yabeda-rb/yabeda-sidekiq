# frozen_string_literal: true

require "sidekiq/testing"

module SidekiqTestingInlineWithMiddlewares
  def push(job)
    return super unless Sidekiq::Testing.inline?

    job = Sidekiq.load_json(Sidekiq.dump_json(job))
    job_class = Sidekiq::Testing.constantize(job["class"])
    job_instance = job_class.new
    queue = (job_instance.sidekiq_options_hash || {}).fetch("queue", "default")
    Sidekiq.server_middleware.invoke(job_instance, job, queue) do
      job_instance.perform(*job["args"])
    end
    job["jid"]
  end
end

Sidekiq::Client.prepend(SidekiqTestingInlineWithMiddlewares)
