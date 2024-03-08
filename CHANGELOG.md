# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.12.0 - 2024-03-08

### Added

- Optional capture of error class for failed jobs counter.

  Set `label_for_error_class_on_sidekiq_jobs_failed` to `true` to add `error` label to `sidekiq_jobs_failed_total` metric.

  Pull request [#34](https://github.com/yabeda-rb/yabeda-sidekiq/pull/34) by [@niborg]

### Changed

- Stop including development-related files into packaged gem to avoid confusing users or software tools. [@Envek]

## 0.11.0 - 2024-02-07

### Added

- `retries_segmented_by_queue` configuration setting to allow segmentation of retry count by queue.

  It is disabled by default as it requires to iterate over all jobs in the retry set and may be very slow if number of retries is huge.

  Pull request [#32](https://github.com/yabeda-rb/yabeda-sidekiq/pull/32) by [@SxDx]

## 0.10.0 - 2022-10-25

### Added

- New metric `sidekiq_jobs_rerouted_total_count` to measure jobs that on enqueue were pushed to different queue from the one specified in worker's `sidekiq_options`. See [#30](https://github.com/yabeda-rb/yabeda-sidekiq/pull/30). [@LukinEgor]

### Fixed

- In `sidekiq_jobs_enqueued_total_count` track real queue that job was pushed into, not the one specified in `sidekiq_options` (sometimes they may be different). See [#30](https://github.com/yabeda-rb/yabeda-sidekiq/pull/30). [@LukinEgor]

## 0.9.0 - 2022-09-26

### Added

- Configuration setting to declare worker in-process metrics outside workers.

  It can be needed for official Prometheus client in multi-process mode where separate process expose metrics from Sidekiq worker processes.

- `most_recent` aggregation for all cluster-wide gauges.

  It is also needed for official Prometheus client in multi-process mode to reduce number of time series.

## 0.8.2 - 2022-09-14

### Added

- Ability to programmatically change gem settings by calling writer methods on `Yabeda::Sidekiq.config`. [@Envek]

  Usage is quite limited though as you need to do it before `Yabeda.configure!` is called.

## 0.8.1 - 2021-08-24

### Fixed

 - Compatibility with Sidekiq 6.2.2+ due to renamings in Sidekiq's undocumented API that yabeda-sidekiq uses. See [mperham/sidekiq#4971](https://github.com/mperham/sidekiq/discussions/4971). [@Envek]

## 0.8.0 - 2021-05-12

### Added

 - `sidekiq_running_job_runtime` metric that tracks maximum runtime of currently running jobs. It may be useful for detection of hung jobs. See [#17](https://github.com/yabeda-rb/yabeda-sidekiq/pull/17). [@dsalahutdinov], [@Envek]

 - Setting `collect_cluster_metrics` allowing to force enable or disable collection of global (whole Sidekiq installaction-wide) metrics. See [#20](https://github.com/yabeda-rb/yabeda-sidekiq/pull/20). [@mrexox]

    By default all sidekiq worker processes (servers) collects global metrics about whole Sidekiq installation.
    Client processes (everything else that is not Sidekiq worker) by default doesn't.

    With this config you can override this behavior:
    - force disable if you don't want multiple Sidekiq workers to report the same numbers (that causes excess load to both Redis and monitoring)
    - force enable if you want non-Sidekiq process to collect them (like dedicated metric exporter process)

## 0.7.0 - 2020-07-15

### Changed

 - Tags from `yabeda_tags` method are applied to all metrics collected inside a job, not only sidekiq-specific. See [#14](https://github.com/yabeda-rb/yabeda-sidekiq/issues/14). @Envek

## 0.6.0 - 2020-07-15

### Added

 - Ability to override or add tags for every job via `yabeda_tags` method. @Envek

## 0.5.0 - 2020-02-20

### Added

 - New `sidekiq_job_latency` histogram to track latency statistics of different job classes. [#9](https://github.com/yabeda-rb/yabeda-sidekiq/pull/9) by [@asusikov]

### Changed

 - **BREAKING CHANGE!** Renamed `sidekiq_jobs_latency` gauge to `sidekiq_queue_latency` to better describe its purpose and differentiate with the new histogram. [#9](https://github.com/yabeda-rb/yabeda-sidekiq/pull/9) by [@asusikov]

## 0.2.0 - 2020-01-14

### Changed

 - Added `tags` option to metric declarations for compatibility with yabeda and yabeda-prometheus 0.2. @Envek

## 0.1.4 - 2019-10-07

### Added

 - Require of core yabeda gem [#4](https://github.com/yabeda-rb/yabeda-sidekiq/pull/4). [@dsalahutdinov]

## 0.1.3 - 2018-10-25

### Fixed

 - Require of core yabeda gem [#1](https://github.com/yabeda-rb/yabeda-sidekiq/issues/1). @Envek

## 0.1.2 - 2018-10-17

### Changed

 - Renamed evil-metrics-sidekiq gem to yabeda-sidekiq. @Envek

## 0.1.1 - 2018-10-05

### Changed

 - Automatic add client and server middlewares to Sidekiq. @Envek

## 0.1.0 - 2018-10-03

 - Initial release of evil-metrics-sidekiq gem. @Envek

[@Envek]: https://github.com/Envek "Andrey Novikov"
[@dsalahutdinov]: https://github.com/dsalahutdinov "Salahutdinov Dmitry"
[@asusikov]: https://github.com/asusikov "Alexander Susikov"
[@mrexox]: https://github.com/mrexox "Valentine Kiselev"
[@LukinEgor]: https://github.com/LukinEgor "Egor Lukin"
[@SxDx]: https://github.com/SxDx "René Koller"
[@niborg]: https://github.com/niborg "Nick Knipe"
