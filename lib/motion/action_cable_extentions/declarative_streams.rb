# frozen_string_literal: true

require "motion"

module Motion
  module ActionCableExtentions
    # Provides a `streaming_from(broadcasts, to:)` API that can be used to
    # declaratively specify what `broadcasts` the channel is interested in
    # receiving and `to` what method they should be routed. Additionally,
    # this module extends the "at most one executor at a time" property that
    # naturally comes with actions to the streams that it sets up as well.
    module DeclarativeStreams
      def initialize(*)
        super

        # Allowing actions to be bound to streams (as this module provides)
        # introduces the possibiliy of multiple threads accessing user code at
        # the same time. Protect user code with a Monitor so we only have to
        # worry about that here.
        @_declarative_stream_monitor = Monitor.new

        # Streams that we are currently interested in
        @_declarative_streams = Set.new

        # The method we are currently routing those streams to
        @_declarative_stream_target = nil

        # Streams that we are setup to listen to. Sadly, there is no public API
        # to stop streaming so this will only grow.
        @_declarative_stream_proxies = Set.new
      end

      # Synchronize all ActionCable entry points (after initialization).
      def subscribe_to_channel(*)
        @_declarative_stream_monitor.synchronize { super }
      end

      def unsubscribe_from_channel(*)
        @_declarative_stream_monitor.synchronize { super }
      end

      def perform_action(*)
        @_declarative_stream_monitor.synchronize { super }
      end

      # Clean up declarative streams when all streams are stopped.
      def stop_all_streams
        super

        @_declarative_streams.clear
        @_declarative_stream_target = nil

        @_declarative_stream_proxies.clear
      end

      # Declaratively routes provided broadcasts to the provided method.
      def streaming_from(broadcasts, to:)
        @_declarative_streams.replace(broadcasts)
        @_declarative_stream_target = to

        @_declarative_streams.each(&method(:_ensure_declarative_stream_proxy))
      end

      def declarative_stream_target
        @_declarative_stream_target
      end

      private

      def _ensure_declarative_stream_proxy(broadcast)
        return unless @_declarative_stream_proxies.add?(broadcast)

        # TODO: Something about this doesn't deal with the coder correctly.
        stream_from(broadcast) do |message|
          _handle_incoming_broadcast_to_declarative_stream(broadcast, message)
        rescue Exception => exception # rubocop:disable Lint/RescueException
          # It is very, very important that we do not allow an exception to
          # escape here as the internals of ActionCable will stop processing
          # the broadcast.

          _handle_exception_in_declarative_stream(broadcast, exception)
        end
      end

      def _handle_incoming_broadcast_to_declarative_stream(broadcast, message)
        @_declarative_stream_monitor.synchronize do
          return unless @_declarative_stream_target &&
            @_declarative_streams.include?(broadcast)

          send(@_declarative_stream_target, broadcast, message)
        end
      end

      def _handle_exception_in_declarative_stream(broadcast, exception)
        logger.error(
          "There was an exception while handling a broadcast to #{broadcast}" \
          "on #{self.class}:\n" \
          "  #{exception.class}: #{exception.message}\n" \
          "#{exception.backtrace.map { |line| "    #{line}" }.join("\n")}"
        )
      end
    end
  end
end
