# frozen_string_literal: true

class SamplePlainJob
  include Sidekiq::Worker

  def perform(*_args)
    "My job is simple"
  end
end

class SampleLongRunningJob
  include Sidekiq::Worker

  def perform(*_args)
    sleep 0.05
    "Phew, I'm done!"
  end
end

class SampleComplexJob
  include Sidekiq::Worker

  def perform(*_args)
    Yabeda.test.whatever.increment({ explicit: true })
    "My job is complex"
  end

  def yabeda_tags
    { implicit: true }
  end
end

class FailingPlainJob
  include Sidekiq::Worker

  SpecialError = Class.new(StandardError)

  def perform(*_args)
    raise SpecialError, "Badaboom"
  end
end

class SampleActiveJob < ActiveJob::Base
  self.queue_adapter = :Sidekiq

  def perform(*_args)
    "I'm doing my job"
  end
end

class FailingActiveJob < ActiveJob::Base
  SpecialError = Class.new(StandardError)

  self.queue_adapter = :Sidekiq
  def perform(*_args)
    raise SpecialError, "Boom"
  end
end

class ReRouteJobsMiddleware
  def call(_worker, job, _queue, _redis_pool)
    job["queue"] = "rerouted_queue"

    yield
  end
end
