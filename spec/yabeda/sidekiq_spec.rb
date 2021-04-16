# frozen_string_literal: true

RSpec.describe Yabeda::Sidekiq do
  it "has a version number" do
    expect(Yabeda::Sidekiq::VERSION).not_to be nil
  end

  it "configures middlewares" do
    expect(Sidekiq.client_middleware).to include(have_attributes(klass: Yabeda::Sidekiq::ClientMiddleware))
  end

  describe "plain Sidekiq jobs" do
    it "counts enqueues" do
      Yabeda.sidekiq.jobs_enqueued_total.values.clear # This is a hack

      SamplePlainJob.perform_async
      SamplePlainJob.perform_async
      FailingPlainJob.perform_async

      expect(Yabeda.sidekiq.jobs_enqueued_total.values).to include(
        { queue: "default", worker: "SamplePlainJob" } => 2,
        { queue: "default", worker: "FailingPlainJob" } => 1,
      )
    end

    it "measures runtime" do
      Yabeda.sidekiq.jobs_executed_total.values.clear   # This is a hack
      Yabeda.sidekiq.jobs_success_total.values.clear    # This is a hack
      Yabeda.sidekiq.jobs_failed_total.values.clear     # This is a hack
      Yabeda.sidekiq.job_runtime.values.clear           # This is a hack also

      Sidekiq::Testing.inline! do
        SamplePlainJob.perform_async
        SamplePlainJob.perform_async
        begin
          FailingPlainJob.perform_async
        rescue StandardError
          nil
        end
      end

      expect(Yabeda.sidekiq.jobs_executed_total.values).to eq(
        { queue: "default", worker: "SamplePlainJob" } => 2,
        { queue: "default", worker: "FailingPlainJob" } => 1,
      )
      expect(Yabeda.sidekiq.jobs_success_total.values).to eq(
        { queue: "default", worker: "SamplePlainJob" } => 2,
      )
      expect(Yabeda.sidekiq.jobs_failed_total.values).to eq(
        { queue: "default", worker: "FailingPlainJob" } => 1,
      )
      expect(Yabeda.sidekiq.job_runtime.values).to include(
        { queue: "default", worker: "SamplePlainJob" } => kind_of(Numeric),
        { queue: "default", worker: "FailingPlainJob" } => kind_of(Numeric),
      )
    end

    it "measures maximum runtime" do
      invoked = 0
      allow(Sidekiq::Workers).to receive(:new) do
        [
          [
            [
              "server:pid:wtf", "tid1", {
                "queue" => "default",
                "payload" => { "queue" => "default", "class" => "FailingPlainJob" },
                "run_at" => Time.now.to_i - 10,
              },
            ],
          ],
          [
            [
              "server:pid:wtf", "tid1", {
                "queue" => "default",
                "payload" => { "queue" => "default", "class" => "SamplePlainJob" },
                "run_at" => Time.now.to_i,
              },
            ],
            [
              "server:pid:wtf", "tid2", {
                "queue" => "default",
                "payload" => { "queue" => "default", "class" => "SamplePlainJob" },
                "run_at" => Time.now.to_i - 5,
              },
            ],
          ],
        ][(invoked += 1) - 1]
      end

      Yabeda.collectors.each(&:call)

      expect(Yabeda.sidekiq.job_max_runtime.values).to include(
        { queue: "default", worker: "FailingPlainJob" } => (be >= 10),
      )

      Yabeda.collectors.each(&:call)

      expect(Yabeda.sidekiq.job_max_runtime.values).to include(
        { queue: "default", worker: "SamplePlainJob" } => (be >= 5),
        { queue: "default", worker: "FailingPlainJob" } => 0,
      )
    end
  end

  describe "ActiveJob jobs" do
    it "counts enqueues" do
      Yabeda.sidekiq.jobs_enqueued_total.values.clear # This is a hack
      SampleActiveJob.perform_later
      expect(Yabeda.sidekiq.jobs_enqueued_total.values).to include(
        { queue: "default", worker: "SampleActiveJob" } => 1,
      )
    end

    it "measures runtime" do
      Yabeda.sidekiq.jobs_executed_total.values.clear   # This is a hack
      Yabeda.sidekiq.jobs_success_total.values.clear    # This is a hack
      Yabeda.sidekiq.jobs_failed_total.values.clear     # This is a hack
      Yabeda.sidekiq.job_runtime.values.clear           # This is a hack also

      Sidekiq::Testing.inline! do
        SampleActiveJob.perform_later
        SampleActiveJob.perform_later
        begin
          FailingActiveJob.perform_later
        rescue StandardError
          nil
        end
      end

      expect(Yabeda.sidekiq.jobs_executed_total.values).to eq(
        { queue: "default", worker: "SampleActiveJob" } => 2,
        { queue: "default", worker: "FailingActiveJob" } => 1,
      )
      expect(Yabeda.sidekiq.jobs_success_total.values).to eq(
        { queue: "default", worker: "SampleActiveJob" } => 2,
      )
      expect(Yabeda.sidekiq.jobs_failed_total.values).to eq(
        { queue: "default", worker: "FailingActiveJob" } => 1,
      )
      expect(Yabeda.sidekiq.job_runtime.values).to include(
        { queue: "default", worker: "SampleActiveJob" } => kind_of(Numeric),
        { queue: "default", worker: "FailingActiveJob" } => kind_of(Numeric),
      )
    end

    it "measures maximum runtime" do
      allow(Sidekiq::Workers).to receive(:new) do
        [
          [
            "server:pid:wtf", "tid1", {
              "queue" => "default",
              "payload" => {
                "queue" => "default",
                "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
                "wrapped" => "SampleActiveJob",
              },
              "run_at" => Time.now.to_i - 42,
            },
          ],
        ]
      end

      Yabeda.collectors.each(&:call)

      expect(Yabeda.sidekiq.job_max_runtime.values).to include(
        { queue: "default", worker: "SampleActiveJob" } => (be >= 42),
      )
    end
  end

  describe "#yabeda_tags worker method" do
    it "uses custom labels for both sidekiq and application metrics" do
      Yabeda.sidekiq.jobs_executed_total.values.clear   # This is a hack
      Yabeda.sidekiq.job_runtime.values.clear           # This is a hack also
      Yabeda.test.whatever.values.clear                 # And this

      Sidekiq::Testing.inline! do
        SampleComplexJob.perform_async
      end

      expect(Yabeda.sidekiq.jobs_executed_total.values).to eq(
        { queue: "default", worker: "SampleComplexJob", implicit: true } => 1,
      )
      expect(Yabeda.sidekiq.job_runtime.values).to include(
        { queue: "default", worker: "SampleComplexJob", implicit: true } => kind_of(Numeric),
      )
      expect(Yabeda.test.whatever.values).to include(
        { explicit: true, implicit: true } => 1,
      )
    end
  end
end
