# frozen_string_literal: true

require "bundler/setup"
require "sidekiq/cli" # Fake that we're a worker to test worker-specific things
require "yabeda/sidekiq"

require "sidekiq/testing"
require "active_job"
require "active_job/queue_adapters/sidekiq_adapter"
require "pry"

require_relative "support/jobs"
require_relative "support/sidekiq_inline_middlewares"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec

  Kernel.srand config.seed
  config.order = :random

  config.before(:all) do
    Yabeda.configure!
    Sidekiq::Testing.fake!
    ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper.jobs.clear
  end

  config.after(:all) do
    Sidekiq::Queues.clear_all
    Sidekiq::Testing.disable!
  end
end

ActiveJob::Base.logger = Logger.new(nil)
