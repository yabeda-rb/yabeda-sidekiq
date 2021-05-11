# frozen_string_literal: true

require "anyway"

module Yabeda
  module Sidekiq
    class Config < ::Anyway::Config
      config_name :yabeda_sidekiq

      attr_config collect_general_metrics: true
      attr_config collect_server_metrics: ::Sidekiq.server?
    end
  end
end
