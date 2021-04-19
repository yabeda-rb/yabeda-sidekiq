# Yabeda::[Sidekiq]

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

 - Total number of executed jobs: `sidekiq_jobs_executed_total` -  (segmented by queue and class name)
 - Number of jobs have been finished successfully: `sidekiq_jobs_success_total` (segmented by queue and class name)
 - Number of jobs have been failed: `sidekiq_jobs_failed_total` (segmented by queue and class name)
 - Time of job run: `sidekiq_job_runtime` (seconds per job execution, segmented by queue and class name)
 - Time of the queue latency `sidekiq_queue_latency` (the difference in seconds since the oldest job in the queue was enqueued)
 - Time of the job latency `sidekiq_job_latency` (the difference in seconds since the enqueuing until running job)
 - Number of jobs in queues: `sidekiq_jobs_waiting_count` (segmented by queue)
 - Number of scheduled jobs:`sidekiq_jobs_scheduled_count`
 - Number of jobs in retry set: `sidekiq_jobs_retry_count`
 - Number of jobs in dead set (“morgue”): `sidekiq_jobs_dead_count`
 - Active workers count: `sidekiq_active_processes`
 - Active processes count: `sidekiq_active_workers_count`
 - Maximum runtime of currently executing jobs: `sidekiq_running_job_runtime` (useful for detection of hung jobs, segmented by queue and class name)

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

# Roadmap (TODO or Help wanted)

 - Implement optional segmentation of retry/schedule/dead sets

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
