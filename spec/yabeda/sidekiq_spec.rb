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

  describe "collection of Sidekiq statistics" do
    before do
      allow(Sidekiq::Stats).to receive(:new).and_return(
        OpenStruct.new(
          processes_size: 1,
          workers_size: 10,
          retry_size: 1,
          scheduled_size: 2,
          dead_size: 3,
          processed: 42,
          failed: 13,
          queues: { "default" => 5, "mailers" => 4 },
        ),
      )
      allow(Sidekiq::Queue).to receive(:all).and_return(
        [
          OpenStruct.new({ name: "default", latency: 0.5 }),
          OpenStruct.new({ name: "mailers", latency: 0 }),
        ],
      )
    end

    it "collects queue latencies" do
      Yabeda.collectors.each(&:call)

      expect(Yabeda.sidekiq.queue_latency.values).to include(
        { queue: "default" } => 0.5,
        { queue: "mailers" } => 0.0,
      )
    end

    it "collects queue sizes" do
      Yabeda.collectors.each(&:call)

      expect(Yabeda.sidekiq.jobs_waiting_count.values).to include(
        { queue: "default" } => 5,
        { queue: "mailers" } => 4,
      )
    end

    it "collects named queues stats", :aggregate_failures do
      Yabeda.collectors.each(&:call)

      expect(Yabeda.sidekiq.jobs_retry_count.values).to eq({ {} => 1 })
      expect(Yabeda.sidekiq.jobs_dead_count.values).to eq({ {} => 3 })
      expect(Yabeda.sidekiq.jobs_scheduled_count.values).to eq({ {} => 2 })
    end

    it "measures maximum runtime of currently running jobs" do
      Yabeda.sidekiq.running_job_runtime.values.clear # This is a hack
      Yabeda::Sidekiq.jobs_started_at.clear

      Sidekiq::Testing.inline! do
        workers = []
        workers.push(Thread.new { SampleLongRunningJob.perform_async })
        sleep 0.01
        workers.push(Thread.new { SampleLongRunningJob.perform_async })

        Yabeda.collectors.each(&:call)
        expect(Yabeda.sidekiq.running_job_runtime.values).to include(
          { queue: "default", worker: "SampleLongRunningJob" } => (be >= 0.01),
        )

        sleep 0.01
        FailingActiveJob.perform_later rescue nil
        Yabeda.collectors.each(&:call)

        expect(Yabeda.sidekiq.running_job_runtime.values).to include(
          { queue: "default", worker: "SampleLongRunningJob" } => (be >= 0.02),
          { queue: "default", worker: "FailingActiveJob" }     => 0,
        )

        # When all jobs are completed, metric should respond with zero
        workers.map(&:join)
        Yabeda.collectors.each(&:call)
        expect(Yabeda.sidekiq.running_job_runtime.values).to include(
          { queue: "default", worker: "SampleLongRunningJob" } => 0,
          { queue: "default", worker: "FailingActiveJob" }     => 0,
        )
      end
    end
  end
end
