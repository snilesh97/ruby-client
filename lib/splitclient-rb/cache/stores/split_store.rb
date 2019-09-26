# frozen_string_literal: true

module SplitIoClient
  module Cache
    module Stores
      class SplitStore
        attr_reader :splits_repository

        def initialize(splits_repository, api_key, metrics, config, sdk_blocker = nil)
          @splits_repository = splits_repository
          @api_key = api_key
          @metrics = metrics
          @config = config
          @sdk_blocker = sdk_blocker
        end

        def call
          if ENV['SPLITCLIENT_ENV'] == 'test'
            store_splits
          else
            splits_thread

            if defined?(PhusionPassenger)
              PhusionPassenger.on_event(:starting_worker_process) do |forked|
                splits_thread if forked
              end
            end
          end
        end

        private

        def splits_thread
          @config.threads[:split_store] = Thread.new do
            @config.logger.info('Starting splits fetcher service')
            loop do
              store_splits

              sleep(StoreUtils.random_interval(@config.features_refresh_rate))
            end
          end
        end

        def store_splits
          data = splits_since
          segment_names = data[:segment_names]

          # TODO: remove safe navigation (&.) if supporting Ruby 2.2 and below
          data[:splits]&.each do |split|
            add_split_unless_archived(split)
          end

          @splits_repository.set_segment_names(segment_names)
          @splits_repository.set_change_number(data[:till])

          @config.split_logger.log_if_debug(
            "segments seen(#{segment_names.length}): #{segment_names}"
          )

          @sdk_blocker.splits_ready!
        rescue StandardError => error
          @config.log_found_exception(__method__.to_s, error)
        end

        def splits_since(since = @splits_repository.get_change_number)
          splits_api.since(since)
        end

        def add_split_unless_archived(split)
          if Engine::Models::Split.archived?(split)
            @config.split_logger.log_if_debug("Seeing archived split #{split[:name]}")

            remove_archived_split(split)
          else
            store_split(split)
          end
        end

        def remove_archived_split(split)
          @config.logger.debug("removing split from store(#{split})") if @config.debug_enabled

          @splits_repository.remove_split(split)
        end

        def store_split(split)
          @config.logger.debug("storing split (#{split[:name]})") if @config.debug_enabled

          @splits_repository.add_split(split)
        end

        def splits_api
          @splits_api ||= SplitIoClient::Api::Splits.new(@api_key, @metrics, @config)
        end
      end
    end
  end
end
