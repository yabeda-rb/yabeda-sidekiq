# frozen_string_literal: true

RSpec.describe Yabeda::Sidekiq do
  it "has a version number" do
    expect(Yabeda::Sidekiq::VERSION).not_to be nil
  end

  it "configures middlewares" do
    config = Sidekiq.respond_to?(:default_configuration) ? Sidekiq.default_configuration : Sidekiq
    expect(config.client_middleware).to include(have_attributes(klass: Yabeda::Sidekiq::ClientMiddleware))
  end

  describe "plain Sidekiq jobs" do
    it "counts enqueues" do
      expect do
        SamplePlainJob.perform_async
        SamplePlainJob.perform_async
        FailingPlainJob.perform_async
      end.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
          { queue: "default", worker: "SamplePlainJob" } => 2,
          { queue: "default", worker: "FailingPlainJob" } => 1,
        )
    end

    context "when label_for_error_class_on_sidekiq_jobs_failed is set to true" do
      around do |example|
        old_value = described_class.config.label_for_error_class_on_sidekiq_jobs_failed
        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = true

        example.run

        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = old_value
      end

      it "counts failed total and executed total with correct labels", sidekiq: :inline do
        expect do
          SamplePlainJob.perform_async
          SamplePlainJob.perform_async
          begin
            FailingPlainJob.perform_async
          rescue StandardError
            nil
          end
        end.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
            { queue: "default", worker: "FailingPlainJob", error: "FailingPlainJob::SpecialError" } => 1,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
              { queue: "default", worker: "SamplePlainJob" } => 2,
              { queue: "default", worker: "FailingPlainJob" } => 1,
            )
      end

      it "does not add jobs_failed_total error label to labels used for jobs_executed_total", sidekiq: :inline do
        expect do
          SamplePlainJob.perform_async
          SamplePlainJob.perform_async
          begin
            FailingPlainJob.perform_async
          rescue StandardError
            nil
          end
        end.not_to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
            { queue: "default", worker: "FailingPlainJob", error: "FailingPlainJob::SpecialError" } => 1,
          )
      end
    end

    describe "re-routing jobs by middleware" do
      around do |example|
        add_reroute_jobs_middleware
        example.run
        remove_reroute_jobs_middleware
      end

      it "counts enqueues" do
        expect do
          SamplePlainJob.perform_async
          SamplePlainJob.perform_async
          FailingPlainJob.perform_async
        end.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
            { queue: "rerouted_queue", worker: "SamplePlainJob" } => 2,
            { queue: "rerouted_queue", worker: "FailingPlainJob" } => 1,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_rerouted_total).with(
              { from_queue: "default", to_queue: "rerouted_queue", worker: "SamplePlainJob" } => 2,
              { from_queue: "default", to_queue: "rerouted_queue", worker: "FailingPlainJob" } => 1,
            )
      end
    end

    it "measures runtime", sidekiq: :inline do
      expect do
        SamplePlainJob.perform_async
        SamplePlainJob.perform_async
        begin
          FailingPlainJob.perform_async
        rescue StandardError
          nil
        end
      end.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
          { queue: "default", worker: "SamplePlainJob" } => 2,
          { queue: "default", worker: "FailingPlainJob" } => 1,
        ).and \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_success_total).with(
            { queue: "default", worker: "SamplePlainJob" } => 2,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
              { queue: "default", worker: "FailingPlainJob" } => 1,
            ).and \
              measure_yabeda_histogram(Yabeda.sidekiq.job_runtime).with(
                { queue: "default", worker: "SamplePlainJob" } => kind_of(Numeric),
                { queue: "default", worker: "FailingPlainJob" } => kind_of(Numeric),
              )
    end
  end

  describe "ActiveJob jobs" do
    it "counts enqueues" do
      expect { SampleActiveJob.perform_later }.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
          { queue: "default", worker: "SampleActiveJob" } => 1,
        )
    end

    describe "re-routing jobs by middleware" do
      around do |example|
        add_reroute_jobs_middleware
        example.run
        remove_reroute_jobs_middleware
      end

      it "counts enqueues" do
        expect { SampleActiveJob.perform_later }.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_enqueued_total).with(
            { queue: "rerouted_queue", worker: "SampleActiveJob" } => 1,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_rerouted_total).with(
              { from_queue: "default", to_queue: "rerouted_queue", worker: "SampleActiveJob" } => 1,
            )
      end
    end

    context "when label_for_error_class_on_sidekiq_jobs_failed is set to true" do
      around do |example|
        old_value = described_class.config.label_for_error_class_on_sidekiq_jobs_failed
        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = true

        example.run

        described_class.config.label_for_error_class_on_sidekiq_jobs_failed = old_value
      end

      it "counts enqueues and uses the default label for the error class", sidekiq: :inline do
        expect do
          SampleActiveJob.perform_later
          SampleActiveJob.perform_later
          begin
            FailingActiveJob.perform_later
          rescue StandardError
            nil
          end
        end.to \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
            { queue: "default", worker: "FailingActiveJob", error: "FailingActiveJob::SpecialError" } => 1,
          )
      end
    end

    it "measures runtime", sidekiq: :inline do
      expect do
        SampleActiveJob.perform_later
        SampleActiveJob.perform_later
        begin
          FailingActiveJob.perform_later
        rescue StandardError
          nil
        end
      end.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
          { queue: "default", worker: "SampleActiveJob" } => 2,
          { queue: "default", worker: "FailingActiveJob" } => 1,
        ).and \
          increment_yabeda_counter(Yabeda.sidekiq.jobs_success_total).with(
            { queue: "default", worker: "SampleActiveJob" } => 2,
          ).and \
            increment_yabeda_counter(Yabeda.sidekiq.jobs_failed_total).with(
              { queue: "default", worker: "FailingActiveJob" } => 1,
            ).and \
              measure_yabeda_histogram(Yabeda.sidekiq.job_runtime).with(
                { queue: "default", worker: "SampleActiveJob" } => kind_of(Numeric),
                { queue: "default", worker: "FailingActiveJob" } => kind_of(Numeric),
              )
    end
  end

  describe "#yabeda_tags worker method" do
    it "uses custom labels for both sidekiq and application metrics", sidekiq: :inline do
      expect { SampleComplexJob.perform_async }.to \
        increment_yabeda_counter(Yabeda.sidekiq.jobs_executed_total).with(
          { queue: "default", worker: "SampleComplexJob", implicit: true } => 1,
        ).and \
          measure_yabeda_histogram(Yabeda.sidekiq.job_runtime).with(
            { queue: "default", worker: "SampleComplexJob", implicit: true } => kind_of(Numeric),
          ).and \
            increment_yabeda_counter(Yabeda.test.whatever).with(
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
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.queue_latency).with(
          { queue: "default" } => 0.5,
          { queue: "mailers" } => 0.0,
        )
    end

    it "collects queue sizes" do
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.jobs_waiting_count).with(
          { queue: "default" } => 5,
          { queue: "mailers" } => 4,
        )
    end

    it "collects named queues stats", :aggregate_failures do
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.jobs_retry_count).with({} => 1).and \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_dead_count).with({} => 3).and \
            update_yabeda_gauge(Yabeda.sidekiq.jobs_scheduled_count).with({} => 2)
    end

    it "measures maximum runtime of currently running jobs", sidekiq: :inline do
      workers = []
      workers.push(Thread.new { SampleLongRunningJob.perform_async })
      sleep 0.015 # Ruby can sleep less than requested
      workers.push(Thread.new { SampleLongRunningJob.perform_async })
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.running_job_runtime).with(
          { queue: "default", worker: "SampleLongRunningJob" } => (be >= 0.010),
        )

      sleep 0.015 # Ruby can sleep less than requested
      begin
        FailingActiveJob.perform_later
      rescue StandardError
        nil
      end

      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.running_job_runtime).with(
          { queue: "default", worker: "SampleLongRunningJob" } => (be >= 0.020),
        )

      # When all jobs are completed, metric should respond with zero
      workers.map(&:join)
      expect { Yabeda.collect! }.to \
        update_yabeda_gauge(Yabeda.sidekiq.running_job_runtime).with(
          { queue: "default", worker: "SampleLongRunningJob" } => 0.0,
        )
    end
  end

  def add_reroute_jobs_middleware
    ::Sidekiq.configure_server do |config|
      config.client_middleware do |chain|
        chain.insert_before Yabeda::Sidekiq::ClientMiddleware, ReRouteJobsMiddleware
      end
    end
  end

  def remove_reroute_jobs_middleware
    ::Sidekiq.configure_server do |config|
      config.client_middleware do |chain|
        chain.remove ReRouteJobsMiddleware
      end
    end
  end
end
