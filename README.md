# ![Yabeda::Sidekiq](./yabeda-sidekiq-logo.png)

Built-in metrics for [Sidekiq] monitoring out of the box! Part of the [yabeda] suite.

Sample Grafana dashboard ID: [11667](https://grafana.com/grafana/dashboards/11667)

## Installation

```ruby
gem 'yabeda-sidekiq'
# Then add monitoring system adapter, e.g.:
# gem 'yabeda-prometheus'
```

And then execute:

    $ bundle

If you're not on Rails then configure Yabeda after your application was initialized:

```ruby
Yabeda.configure!
```

_If you're using Ruby on Rails then Yabeda will configure itself automatically!_

**And that is it!** Sidekiq metrics are being collected!

Additionally, depending on your adapter, you may want to setup metrics export. E.g. for [yabeda-prometheus]:

```ruby
# config/initializers/sidekiq or elsewhere
Sidekiq.configure_server do |_config|
  Yabeda::Prometheus::Exporter.start_metrics_server!
end
```

## Metrics

### Local per-process metrics

Metrics representing state of current Sidekiq worker process and stats of executed or executing jobs:

 - Total number of executed jobs: `sidekiq_jobs_executed_total` -  (segmented by queue and class name)
 - Number of jobs have been finished successfully: `sidekiq_jobs_success_total` (segmented by queue and class name)
 - Number of jobs have been failed: `sidekiq_jobs_failed_total` (segmented by queue and class name)
 - Time of job run: `sidekiq_job_runtime` (seconds per job execution, segmented by queue and class name)
 - Time of the job latency `sidekiq_job_latency` (the difference in seconds since the enqueuing until running job)
 - Maximum runtime of currently executing jobs: `sidekiq_running_job_runtime` (useful for detection of hung jobs, segmented by queue and class name)

### Global cluster-wide metrics

Metrics representing state of the whole Sidekiq installation (queues, processes, etc):

 - Number of jobs in queues: `sidekiq_jobs_waiting_count` (segmented by queue)
 - Time of the queue latency `sidekiq_queue_latency` (the difference in seconds since the oldest job in the queue was enqueued)
 - Number of scheduled jobs:`sidekiq_jobs_scheduled_count`
 - Number of jobs in retry set: `sidekiq_jobs_retry_count`
 - Number of jobs in dead set (“morgue”): `sidekiq_jobs_dead_count`
 - Active processes count: `sidekiq_active_processes`
 - Active servers count: `sidekiq_active_workers_count`

By default all sidekiq worker processes (servers) collects global metrics about whole Sidekiq installation. This can be overridden by setting `collect_cluster_metrics` config key to `true` for non-Sidekiq processes or to `false` for Sidekiq processes (e.g. by setting `YABEDA_SIDEKIQ_COLLECT_CLUSTER_METRICS` env variable to `no`, see other methods in [anyway_config] docs).

### Client metrics

Metrics collected where jobs are being pushed to queues (everywhere):

- Total number of enqueued jobs: `sidekiq_jobs_enqueued_total` (segmented by `queue` and `worker` class name)

- Total number of rerouted jobs: `sidekiq_jobs_rerouted_total` (segmented by origin queue `from_queue`, rerouted queue `to_queue`, and `worker` class name).

  Rerouted jobs are jobs that on enqueue were pushed to different queue from the one specified in worker's `sidekiq_options`, most probably by some middleware.

## Custom tags

You can add additional tags to these metrics by declaring `yabeda_tags` method in your worker.

```ruby
# This block is optional but some adapters (like Prometheus) requires that all tags should be declared in advance
Yabeda.configure do
  default_tag :importance, nil
end

class MyWorker
  include Sidekiq::Worker

  def yabeda_tags(*params) # This method will be called first, before +perform+
    { importance: extract_importance(params) }
  end

  def perform(*params)
    # Your logic here
  end
end
```

## Configuration

Configuration is handled by [anyway_config] gem. With it you can load settings from environment variables (upcased and prefixed with `YABEDA_SIDEKIQ_`), YAML files, and other sources. See [anyway_config] docs for details.

| Config key                                     | Type    | Default                                                 | Description                                                                                                                                        |
|------------------------------------------------|---------|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| `collect_cluster_metrics`                      | boolean | Enabled in Sidekiq worker processes, disabled otherwise | Defines whether this Ruby process should collect and expose metrics representing state of the whole Sidekiq installation (queues, processes, etc). |
| `declare_process_metrics`                      | boolean | Enabled in Sidekiq worker processes, disabled otherwise | Declare metrics that are only tracked inside worker process even outside of them. Useful for multiprocess metric collection.                       |
| `retries_segmented_by_queue`                   | boolean | Disabled                                                | Defines wheter retries are segemented by queue or reported as a single metric                                                                      |
| `label_for_error_class_on_sidekiq_jobs_failed` | boolean | Disabled                                                | Defines whether `error` label should be added to `sidekiq_jobs_failed_total` metric.                                                               |

# Roadmap (TODO or Help wanted)

 - Implement optional segmentation of schedule/dead sets

   It should be disabled by default as it requires to iterate over all jobs in sets and may be very slow on large sets.

 - Maybe add some hooks for ease of plugging in metrics for myriads of Sidekiq plugins?

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yabeda-rb/yabeda-sidekiq.

### Releasing

1. Bump version number in `lib/yabeda/sidekiq/version.rb`

   In case of pre-releases keep in mind [rubygems/rubygems#3086](https://github.com/rubygems/rubygems/issues/3086) and check version with command like `Gem::Version.new(Yabeda::Sidekiq::VERSION).to_s`

2. Fill `CHANGELOG.md` with missing changes, add header with version and date.

3. Make a commit:

   ```sh
   git add lib/yabeda/sidekiq/version.rb CHANGELOG.md
   version=$(ruby -r ./lib/yabeda/sidekiq/version.rb -e "puts Gem::Version.new(Yabeda::Sidekiq::VERSION)")
   git commit --message="${version}: " --edit
   ```

4. Create annotated tag:

   ```sh
   git tag v${version} --annotate --message="${version}: " --edit --sign
   ```

5. Fill version name into subject line and (optionally) some description (list of changes will be taken from changelog and appended automatically)

6. Push it:

   ```sh
   git push --follow-tags
   ```

7. GitHub Actions will create a new release, build and push gem into RubyGems! You're done!

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[Sidekiq]: https://github.com/mperham/sidekiq/ "Simple, efficient background processing for Ruby"
[yabeda]: https://github.com/yabeda-rb/yabeda
[yabeda-prometheus]: https://github.com/yabeda-rb/yabeda-prometheus
[anyway_config]: https://github.com/palkan/anyway_config "Configuration library for Ruby gems and applications"
