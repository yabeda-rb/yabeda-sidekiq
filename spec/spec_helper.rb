# frozen_string_literal: true

require "bundler/setup"
require "sidekiq/cli" # Fake that we're a worker to test worker-specific things
require "yabeda/sidekiq"

require "yabeda/rspec"
require "sidekiq/testing"
require "active_job"
require "active_job/queue_adapters/sidekiq_adapter"
require "pry"

require_relative "support/custom_metrics"
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

  config.filter_run focus: true
  config.run_all_when_everything_filtered = true

  config.before(:all) do
    Sidekiq::Testing.fake!
    ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper.jobs.clear
  end

  config.after(:all) do
    Sidekiq::Queues.clear_all
    Sidekiq::Testing.disable!
  end

  config.around do |ex|
    next ex.run unless ex.metadata[:sidekiq]

    begin
      previous_mode = Sidekiq::Testing.__test_mode
      Sidekiq::Testing.__set_test_mode(ex.metadata[:sidekiq])
      ex.run
    ensure
      Sidekiq::Testing.__set_test_mode(previous_mode)
    end
  end
end

ActiveJob::Base.logger = Logger.new(nil)
