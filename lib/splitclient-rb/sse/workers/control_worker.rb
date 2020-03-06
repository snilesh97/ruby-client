# frozen_string_literal: true

module SplitIoClient
  module SSE
    module Workers
      class ControlWorker
        def initialize(config)
          @config = config
        end

        def start
          perform_thread
          perform_passenger_forked if defined?(PhusionPassenger)
        end

        def stop
          @config.threads[:segment_update_worker].exit
        end

        private

        def perform
          # TODO: IMPLEMENT THIS METHOD.
        end

        def perform_thread
          @config.threads[:segment_update_worker] = Thread.new do
            perform
          end
        end

        def perform_passenger_forked
          PhusionPassenger.on_event(:starting_worker_process) { |forked| perform_thread if forked }
        end
      end
    end
  end
end
