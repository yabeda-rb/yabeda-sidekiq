# Yabeda::[Sidekiq]

Built-in metrics for [Sidekiq] monitoring out of the box! Part of the [yabeda] suite.

## Installation

```ruby
gem 'yabeda-sidekiq'
# Then add monitoring system adapter, e.g.:
# gem 'yabeda-prometheus'
```

And then execute:

    $ bundle

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
 - Time of the queue latency `sidekiq_jobs_latency` (the difference in seconds since the oldest job in the queue was enqueued)
 - Number of pending jobs in queues: `sidekiq_jobs_size` (segmented by queue)
 - Number of jobs in queues: `sidekiq_jobs_waiting_count` (segmented by queue)
 - Number of scheduled jobs:`sidekiq_jobs_scheduled_count`
 - Number of jobs in retry set: `sidekiq_jobs_retry_count`
 - Number of jobs in dead set (“morgue”): `sidekiq_jobs_dead_count`
 - Active workers count: `sidekiq_active_processes`
 - Active processes count: `sidekiq_active_workers_count`

# Roadmap (TODO or Help wanted)

 - Implement optional segmentation of retry/schedule/dead sets

   It should be disabled by default as it requires to iterate over all jobs in sets and may be very slow on large sets.

 - Maybe add some hooks for ease of plugging in metrics for myriads of Sidekiq plugins?

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yabeda-rb/yabeda-sidekiq.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

[Sidekiq]: https://github.com/mperham/sidekiq/ "Simple, efficient background processing for Ruby"
[yabeda]: https://github.com/yabeda-rb/yabeda
[yabeda-prometheus]: https://github.com/yabeda-rb/yabeda-prometheus
