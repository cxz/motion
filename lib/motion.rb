# frozen_string_literal: true

require "motion/version"
require "motion/errors"

module Motion
  autoload :Channel, "motion/channel"
  autoload :Component, "motion/component"
  autoload :Configuration, "motion/configuration"
  autoload :Element, "motion/element"
  autoload :Event, "motion/event"
  autoload :MarkupTransformer, "motion/markup_transformer"
  autoload :Railtie, "motion/railtie"
  autoload :Serializer, "motion/serializer"
  autoload :TestHelpers, "motion/test_helpers"

  def self.configure(&block)
    raise AlreadyConfiguredError if @config

    @config = Configuration.new(&block)
  end

  def self.config
    @config ||= Configuration.default
  end

  singleton_class.alias_method :configuration, :config

  def self.serializer
    @serializer ||= Serializer.new
  end

  def self.markup_transformer
    @markup_transformer ||= MarkupTransformer.new
  end

  def self.build_renderer_for(websocket_connection)
    config.renderer_for_connection_proc.call(websocket_connection)
  end
end

require "motion/railtie" if defined?(Rails)
