# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "evil/metrics/sidekiq/version"

Gem::Specification.new do |spec|
  spec.name          = "evil-metrics-sidekiq"
  spec.version       = Evil::Metrics::Sidekiq::VERSION
  spec.authors       = ["Andrey Novikov"]
  spec.email         = ["envek@envek.name"]

  spec.summary       = "Extensible Prometheus exporter for monitoring your Sidekiq"
  spec.description   = "Prometheus exporter for easy collecting most important of your Sidekiq metrics"
  spec.homepage      = "https://github.com/evil-metrics/evil-metrics-sidekiq"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "evil-metrics"
  spec.add_dependency "sidekiq"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
