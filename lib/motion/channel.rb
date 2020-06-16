# frozen_string_literal: true

require "action_cable"

require "motion"
require "motion/channel/action_cable_log_suppression"
require "motion/channel/declarative_streams"
require "motion/channel/logging"

module Motion
  # This class has gotten a bit out of control (especially with the logging).
  # Perhaps the logging and component lifecycle management can be factored out.
  class Channel < ApplicationCable::Channel
    include ActionCableLogSuppression
    include DeclarativeStreams
    include Logging

    def subscribed
      initialize_component

      component.connected
      flush_component

      log_info "Connected"
    rescue => error
      reject

      log_error(error, "An error occurred while connecting the component")
    end

    def unsubscribed
      # unsubscribed will still be called when the subscription is rejected
      return unless component

      component.disconnected
      # no `flush_component` here because the channel is closed

      log_info "Disconnected"
    rescue => error
      log_error(error, "An error occurred while disconnecting the component")
    end

    def process_motion(data)
      name = data.fetch("name")

      log_timing "Proccessed motion #{name}" do
        component.process_motion name, Event.from_raw(data["event"])
      end

      flush_component
    rescue => error
      log_processing_error(error, "the #{name} motion")
    end

    private

    def process_broadcast(broadcast, message)
      log_timing "Proccessed broadcast to #{broadcast}" do
        component.process_broadcast broadcast, message
      end

      flush_component
    rescue => error
      log_processing_error(error, "a broadcast to #{broadcast}")
    end

    attr_reader :component

    def initialize_component
      assert_compatible_client!

      @component = Motion.serializer.deserialize(params.fetch(:state))

      # no `render_component` here because the initial markup was already sent
      setup_broadcasts

      @render_hash = component.render_hash
    end

    def flush_component
      next_render_hash = component.render_hash

      return if !component.awaiting_forced_rerender? &&
        @render_hash == next_render_hash

      render_component
      setup_broadcasts

      @render_hash = next_render_hash
    end

    def setup_broadcasts
      streaming_from(component.broadcasts, to: :process_broadcast)
    end

    def render_component
      transmit(log_timing("Rendered") { renderer.render(component) })
    end

    # Memoize the renderer on the connection so that it can be shared accross
    # all components. `ActionController::Renderer` is already thread-safe and
    # designed to be reused.
    def renderer
      connection.instance_eval do
        @_motion_renderer ||= Motion.build_renderer_for(self)
      end
    end

    # TODO: This is too restrictive. Introduce a protocol version and support
    # older versions of the client that have a compatible protocol.
    def assert_compatible_client!
      return if Motion::VERSION == (client_version = params.fetch(:version))

      raise IncompatibleClientError.new(Motion::VERSION, client_version)
    end
  end
end
