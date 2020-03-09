# frozen_string_literal: true

module SplitIoClient
  module Engine
    class PushManager
      def initialize(config, sse_handler)
        @config = config
        @sse_handler = sse_handler
        @auth_api_client = AuthApiClient.new
      end

      def start_sse(api_key)
        response = @auth_api_client.authenticate(api_key)

        if response.pushEnabled
          @sse_client = @sse_handler.start('www.ably.io', response.token, response.channels)
          schedule_next_token_refresh(token)
        end

        response.pushEnabled
      end

      def stop_sse
        @sse_client.close
      end

      private

      def schedule_next_token_refresh(token)
        # TODO: implement this method
      end
    end
  end
end
