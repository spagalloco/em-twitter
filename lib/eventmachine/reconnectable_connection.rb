require 'em-twitter/core_ext/hash'

module EventMachine
  class ReconnectableConnection < EM::Connection

    DEFAULT_RECONNECT_OPTIONS = {
      :network_failure => {
        :start  => 0.25,
        :add    => 0.25,
        :max    => 16
      },
      :application_failure => {
        :start    => 10,
        :multiple => 2
      },
      :auto_reconnect => true,
      :max_reconnects => 320,
      :max_retries    => 10
    }

    attr_accessor :nf_last_reconnect
    attr_accessor :af_last_reconnect
    attr_accessor :reconnect_retries

    def initialize(client, options = {})
      @client = client

      @on_unbind = options.delete(:on_unbind)
      @reconnect_options = DEFAULT_RECONNECT_OPTIONS.deep_merge(options)

      @gracefully_closed = false

      @nf_last_reconnect = nil
      @af_last_reconnect = nil

      @reconnect_retries = 0
      @immediate_reconnect = false
    end

    def stop
      @gracefully_closed = true
      close_connection
    end

    def immediate_reconnect
      @immediate_reconnect = true
      @gracefully_closed = false
      close_connection
    end

    def gracefully_closed?
      @gracefully_closed
    end

    def immediate_reconnect?
      @immediate_reconnect
    end

    def unbind
      schedule_reconnect if @reconnect_options[:auto_reconnect] && !@gracefully_closed
      @on_unbind.call if @on_unbind
    end

    protected

    def schedule_reconnect
      timeout = reconnect_timeout

      @reconnect_retries += 1
      if timeout <= @reconnect_options[:max_reconnects] && @reconnect_retries <= @reconnect_options[:max_retries]
        reconnect_after(timeout)
      else
        @client.max_reconnects_callback.call(timeout, @reconnect_retries) if @client.max_reconnects_callback
      end
    end

    def reconnect_after(timeout)
      @client.reconnect_callback.call(timeout, @reconnect_retries) if @client.reconnect_callback

      if timeout == 0
        @client.reconnect
      else
        EventMachine.add_timer(timeout) do
          @client.reconnect
        end
      end
    end

    def reconnect_timeout
      if immediate_reconnect?
        @immediate_reconnect = false
        return 0
      end

      if network_failure?
        if @nf_last_reconnect
          @nf_last_reconnect += @reconnect_options[:network_failure][:add]
        else
          @nf_last_reconnect = @reconnect_options[:network_failure][:start]
        end
        [@nf_last_reconnect,@reconnect_options[:network_failure][:max]].min
      else
        if @af_last_reconnect
          @af_last_reconnect *= @reconnect_options[:application_failure][:mul]
        else
          @af_last_reconnect = @reconnect_options[:application_failure][:start]
        end
        @af_last_reconnect
      end
    end

    def reset_timeouts
      set_comm_inactivity_timeout @options[:timeout] if @options[:timeout] > 0
      @nf_last_reconnect = @af_last_reconnect = nil
      @reconnect_retries = 0
    end

    def network_failure?
      raise StandardError.new 'You must override this method in your client.'
    end

  end
end