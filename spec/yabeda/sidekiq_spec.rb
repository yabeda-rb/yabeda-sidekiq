# frozen_string_literal: true

RSpec.describe Yabeda::Sidekiq do
  it "has a version number" do
    expect(Yabeda::Sidekiq::VERSION).not_to be_nil
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
    def gauge_updates(gauge)
      Yabeda::TestAdapter.instance.gauges.fetch(gauge)
    end

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

    context "when filter_queues_by_current_process is enabled" do
      around do |example|
        old_value = described_class.config.filter_queues_by_current_process
        described_class.config.filter_queues_by_current_process = true
        example.run
      ensure
        described_class.config.filter_queues_by_current_process = old_value
      end

      before do
        allow(described_class).to receive(:process_queue_names).and_return(%w[default critical])
        allow(Sidekiq::Queue).to receive(:new) { |name| OpenStruct.new(name: name, latency: name == "default" ? 0.5 : 0) }
      end

      it "collects queue sizes only for queues of the current process" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_waiting_count).with(
            { queue: "default" } => 5,
            { queue: "critical" } => 0,
          )
        expect(gauge_updates(Yabeda.sidekiq.jobs_waiting_count).keys).to contain_exactly({ queue: "default" }, { queue: "critical" })
      end

      it "collects queue latencies only for queues of the current process" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.queue_latency).with(
            { queue: "default" } => 0.5,
            { queue: "critical" } => 0,
          )
        expect(gauge_updates(Yabeda.sidekiq.queue_latency).keys).to contain_exactly({ queue: "default" }, { queue: "critical" })
        expect(Sidekiq::Queue).not_to have_received(:all)
      end
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
        update_yabeda_gauge(Yabeda.sidekiq.jobs_retry_count).with(1).and \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_dead_count).with(3).and \
            update_yabeda_gauge(Yabeda.sidekiq.jobs_scheduled_count).with(2)
    end

    it "does not iterate job sets when segmentation is disabled" do
      allow(Sidekiq::RetrySet).to receive(:new).and_call_original
      allow(Sidekiq::DeadSet).to receive(:new).and_call_original
      allow(Sidekiq::ScheduledSet).to receive(:new).and_call_original

      Yabeda.collect!

      expect(Sidekiq::RetrySet).not_to have_received(:new)
      expect(Sidekiq::DeadSet).not_to have_received(:new)
      expect(Sidekiq::ScheduledSet).not_to have_received(:new)
    end

    context "when job sets are segmented by queue" do
      around do |example|
        config = described_class.config
        previous = [
          config.retries_segmented_by_queue,
          config.dead_segmented_by_queue,
          config.scheduled_segmented_by_queue,
        ]
        configurators = Yabeda.configurators.to_a

        config.retries_segmented_by_queue = true
        config.dead_segmented_by_queue = true
        config.scheduled_segmented_by_queue = true
        reconfigure_yabeda(configurators)

        example.run
      ensure
        config.retries_segmented_by_queue, config.dead_segmented_by_queue, config.scheduled_segmented_by_queue = previous
        reconfigure_yabeda(configurators)
      end

      before do
        allow(Sidekiq::RetrySet).to receive(:new).and_return(
          [{ "queue" => "default" }, { "queue" => "default" }],
        )
        allow(Sidekiq::DeadSet).to receive(:new).and_return(
          [{ "queue" => "mailers" }, { "queue" => "removed_queue" }],
        )
        allow(Sidekiq::ScheduledSet).to receive(:new).and_return(
          [{ "queue" => "default" }],
        )
      end

      it "declares retry, dead, and scheduled gauges with a queue tag" do
        expect(Yabeda.sidekiq.jobs_retry_count.tags).to eq(%i[queue])
        expect(Yabeda.sidekiq.jobs_dead_count.tags).to eq(%i[queue])
        expect(Yabeda.sidekiq.jobs_scheduled_count.tags).to eq(%i[queue])
      end

      it "publishes per-queue counts and zero-fills known queues" do
        expect { Yabeda.collect! }.to \
          update_yabeda_gauge(Yabeda.sidekiq.jobs_retry_count).with(
            { queue: "default" } => 2,
            { queue: "mailers" } => 0,
          ).and \
            update_yabeda_gauge(Yabeda.sidekiq.jobs_dead_count).with(
              { queue: "default" } => 0,
              { queue: "mailers" } => 1,
              { queue: "removed_queue" } => 1,
            ).and \
              update_yabeda_gauge(Yabeda.sidekiq.jobs_scheduled_count).with(
                { queue: "default" } => 1,
                { queue: "mailers" } => 0,
              )
      end

      it "publishes per-queue counts only for queues of the current process when filtering is enabled" do
        described_class.config.filter_queues_by_current_process = true
        allow(described_class).to receive(:process_queue_names).and_return(%w[default critical])
        allow(Sidekiq::Queue).to receive(:new) { |name| OpenStruct.new(name: name, latency: 0) }

        Yabeda.collect!

        expect(gauge_updates(Yabeda.sidekiq.jobs_retry_count)).to eq({ queue: "default" } => 2, { queue: "critical" } => 0)
        expect(gauge_updates(Yabeda.sidekiq.jobs_dead_count)).to eq({ queue: "default" } => 0, { queue: "critical" } => 0)
        expect(gauge_updates(Yabeda.sidekiq.jobs_scheduled_count)).to eq({ queue: "default" } => 1, { queue: "critical" } => 0)
      ensure
        described_class.config.filter_queues_by_current_process = false
      end
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

  def reconfigure_yabeda(configurators)
    Yabeda.reset!
    Yabeda.register_adapter(:test, Yabeda::TestAdapter.instance)
    configurators.each { |(_group, block)| Yabeda.configure(&block) }
    Yabeda.configure!
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

  describe ".process_queue_names" do
    if Sidekiq.respond_to?(:default_configuration)
      it "returns unique queues of all capsules" do
        allow(Sidekiq.default_configuration).to receive(:capsules).and_return(
          "default" => instance_double(Sidekiq::Capsule, queues: %w[critical critical default]),
          "single" => instance_double(Sidekiq::Capsule, queues: %w[single default]),
        )

        expect(described_class.process_queue_names).to eq(%w[critical default single])
      end
    elsif Sidekiq.respond_to?(:[])
      it "returns unique configured queues (Sidekiq 6.5)" do
        allow(Sidekiq).to receive(:[]).and_call_original
        allow(Sidekiq).to receive(:[]).with(:queues).and_return(%w[critical critical default])

        expect(described_class.process_queue_names).to eq(%w[critical default])
      end
    else
      it "returns unique configured queues (Sidekiq 5.x – 6.4)" do
        allow(Sidekiq).to receive(:options).and_return(queues: %w[critical critical default])

        expect(described_class.process_queue_names).to eq(%w[critical default])
      end
    end
  end
end
