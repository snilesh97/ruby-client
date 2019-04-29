module SplitIoClient
  class SplitManager
    #
    # Creates a new split manager instance that connects to split.io API.
    #
    # @param api_key [String] the API key for your split account
    #
    # @return [SplitIoManager] split.io client instance
    def initialize(api_key, adapter = nil, splits_repository = nil, sdk_blocker, config)
      @localhost_mode_features = []
      @splits_repository = splits_repository
      @adapter = adapter
      @sdk_blocker = sdk_blocker
      @config = config
      @validators = Validators.new(config)
    end

    #
    # method to get the split list from the client
    #
    # @returns [object] array of splits
    def splits
      return [] if !@config.valid_mode || @splits_repository.nil?

      if !ready?
        @config.logger.error("splits: the SDK is not ready, the operation cannot be executed")
        return []
      end

      @splits_repository.splits.each_with_object([]) do |(name, split), memo|
        split_view = build_split_view(name, split)

        next if split_view[:name] == nil

        memo << split_view unless Engine::Models::Split.archived?(split)
      end
    end

    #
    # method to get the list of just split names. Ideal for ietrating and calling client.get_treatment
    #
    # @returns [object] array of split names (String)
    def split_names
      return [] if !@config.valid_mode || @splits_repository.nil?

      if !ready?
        @config.logger.error("split_names: the SDK is not ready, the operation cannot be executed")
        return []
      end

      @splits_repository.split_names
    end

    #
    # method to get a split view
    #
    # @returns a split view
    def split(split_name)
      return unless @config.valid_mode && @splits_repository && @validators.valid_split_parameters(split_name)

      if !ready?
        @config.logger.error("split: the SDK is not ready, the operation cannot be executed")
        return
      end

      sanitized_split_name= split_name.to_s.strip

      if split_name.to_s != sanitized_split_name
        @config.logger.warn("split: split_name #{split_name} has extra whitespace, trimming")
        split_name = sanitized_split_name
      end

      split = @splits_repository.get_split(split_name)

      if ready? && split.nil?
        @config.logger.warn("split: you passed #{split_name} " \
          'that does not exist in this environment, please double check what Splits exist in the web console')
      end

      return if split.nil? || Engine::Models::Split.archived?(split)

      build_split_view(split_name, split)
    end

    def block_until_ready(time = nil)
      @sdk_blocker.block(time) if @sdk_blocker && !@sdk_blocker.ready?
    end

    private

    def build_split_view(name, split)
      return {} unless split

      begin
        treatments = split[:conditions]
          .detect { |c| c[:conditionType] == 'ROLLOUT' }[:partitions]
          .map { |partition| partition[:treatment] }
      rescue StandardError
        treatments = []
      end

        {
          name: name,
          traffic_type_name: split[:trafficTypeName],
          killed: split[:killed],
          treatments: treatments,
          change_number: split[:changeNumber],
          configs: split[:configurations] || {}
        }
    end

    # move to blocker, alongside block until ready to avoid duplication
    def ready?
      return @sdk_blocker.ready? if @sdk_blocker
      true
    end
  end
end
