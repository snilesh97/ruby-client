module SplitIoClient
  class SplitFactory
    ROOT_PROCESS_ID = Process.pid
    SINGLETON_WARN = 'We recommend keeping only one instance of the factory at all times (Singleton pattern) and reusing it throughout your application'
    LOCALHOST_API_KEY = 'localhost'

    include SplitIoClient::Cache::Repositories
    include SplitIoClient::Cache::Stores
    include SplitIoClient::Cache::Senders

    attr_reader :adapter, :client, :manager, :config

    def initialize(api_key, config_hash = {})
      at_exit do
        unless ENV['SPLITCLIENT_ENV'] == 'test'
          if (Process.pid == ROOT_PROCESS_ID)
            @config.logger.info('Split SDK shutdown started...')
            @client.destroy if @client
            stop!
            @config.logger.info('Split SDK shutdown complete')
          end
        end
      end

      @api_key = api_key
      @config = SplitConfig.new(config_hash.merge(localhost_mode: @api_key == LOCALHOST_API_KEY ))

      raise 'Invalid SDK mode' unless valid_mode

      @splits_repository = SplitsRepository.new(@config)
      @segments_repository = SegmentsRepository.new(@config)
      @impressions_repository = ImpressionsRepository.new(@config)
      @events_repository = EventsRepository.new(@config, @api_key)
      @metrics_repository = MetricsRepository.new(@config)
      @sdk_blocker = SDKBlocker.new(@splits_repository, @segments_repository, @config)
      @metrics = Metrics.new(100, @metrics_repository)
      @impression_counter = SplitIoClient::Engine::Common::ImpressionCounter.new
      @impressions_manager = SplitIoClient::Engine::Common::ImpressionManager.new(@config, @impressions_repository, @impression_counter)

      start!

      @client = SplitClient.new(@api_key, @metrics, @splits_repository, @segments_repository, @impressions_repository, @metrics_repository, @events_repository, @sdk_blocker, @config, @impressions_manager)
      @manager = SplitManager.new(@splits_repository, @sdk_blocker, @config)

      validate_api_key

      RedisMetricsFixer.new(@metrics_repository, @config).call

      register_factory
    end

    def start!
      if @config.localhost_mode
        start_localhost_components
      else
        params = { sdk_blocker: @sdk_blocker, metrics: @metrics, impression_counter: @impression_counter }
        SplitIoClient::Engine::SyncManager.new(repositories, @api_key, @config, params).start
      end
    end

    def stop!
      @config.threads.each { |_, t| t.exit }
    end

    def register_factory
      SplitIoClient.load_factory_registry

      number_of_factories = SplitIoClient.split_factory_registry.number_of_factories_for(@api_key)

      if(number_of_factories > 0)
        @config.logger.warn("Factory instantiation: You already have #{number_of_factories} factories with this API Key. #{SINGLETON_WARN}")
      elsif(SplitIoClient.split_factory_registry.other_factories)
        @config.logger.warn('Factory instantiation: You already have an instance of the Split factory.' \
          " Make sure you definitely want this additional instance. #{SINGLETON_WARN}")
      end

      SplitIoClient.split_factory_registry.add(@api_key)
    end

    def valid_mode
      valid_startup_mode = false
      case @config.mode
      when :consumer
        if @config.cache_adapter.is_a? SplitIoClient::Cache::Adapters::RedisAdapter
          if !@config.localhost_mode
            valid_startup_mode = true
          else
            @config.logger.error('Localhost mode cannot be used with Redis. ' \
              'Use standalone mode and Memory adapter instead.')
          end
        else
          @config.logger.error('Consumer mode cannot be used with Memory adapter. ' \
            'Use Redis adapter instead.')
        end
      when :standalone
        if @config.cache_adapter.is_a? SplitIoClient::Cache::Adapters::MemoryAdapter
          valid_startup_mode = true
        else
          @config.logger.error('Standalone mode cannot be used with Redis adapter. ' \
            'Use Memory adapter instead.')
        end
      when :producer
        @config.logger.error('Producer mode is no longer supported. Use Split Synchronizer. ' \
          'See: https://github.com/splitio/split-synchronizer')
      else
        @config.logger.error('Invalid SDK mode selected. ' \
          "Valid modes are 'standalone with memory adapter' and 'consumer with redis adapter'")
      end

      valid_startup_mode
    end

    alias resume! start!

    private

    def validate_api_key
      if(@api_key.nil?)
        @config.logger.error('Factory Instantiation: you passed a nil api_key, api_key must be a non-empty String')
        @config.valid_mode =  false
      elsif (@api_key.empty?)
        @config.logger.error('Factory Instantiation: you passed and empty api_key, api_key must be a non-empty String')
        @config.valid_mode =  false
      end
    end

    def repositories
      repos = {}
      repos[:splits] = @splits_repository
      repos[:segments] = @segments_repository
      repos[:impressions] = @impressions_repository
      repos[:events] = @events_repository
      repos[:metrics] = @metrics_repository

      repos
    end

    def start_localhost_components
      LocalhostSplitStore.new(@splits_repository, @config, @sdk_blocker).call

      # Starts thread which loops constantly and cleans up repositories to avoid memory issues in localhost mode
      LocalhostRepoCleaner.new(@impressions_repository, @metrics_repository, @events_repository, @config).call
    end
  end
end
