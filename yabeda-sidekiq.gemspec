# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "yabeda/sidekiq/version"

Gem::Specification.new do |spec|
  spec.name          = "yabeda-sidekiq"
  spec.version       = Yabeda::Sidekiq::VERSION
  spec.authors       = ["Andrey Novikov"]
  spec.email         = ["envek@envek.name"]

  spec.summary       = "Extensible Prometheus exporter for monitoring your Sidekiq"
  spec.description   = "Prometheus exporter for easy collecting most important of your Sidekiq metrics"
  spec.homepage      = "https://github.com/yabeda-rb/yabeda-sidekiq"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "anyway_config", ">= 1.3", "< 3"
  spec.add_dependency "sidekiq"
  spec.add_dependency "yabeda", "~> 0.6"

  spec.add_development_dependency "activejob", ">= 6.0"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
