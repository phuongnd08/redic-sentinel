require "redic"
require "redis"

class Redic::Client
  DEFAULT_FAILOVER_RECONNECT_WAIT_SECONDS = 0.1

  class_eval do
    attr_reader :current_sentinel
    attr_reader :uri

    def initialize_with_sentinel(url, timeout, options)
      options = options.try(:dup) || {} # Don't touch my options
      @options = options
      @master_name = fetch_option(options, :master_name)
      @master_password = fetch_option(options, :master_password)
      @sentinels_options = _parse_sentinel_options(fetch_option(options, :sentinels))
      @failover_reconnect_timeout = fetch_option(options, :failover_reconnect_timeout)
      @failover_reconnect_wait = fetch_option(options, :failover_reconnect_wait) ||
                                 DEFAULT_FAILOVER_RECONNECT_WAIT_SECONDS

      Thread.new { watch_sentinel } if sentinel? && !fetch_option(options, :async)

      initialize_without_sentinel(url, timeout)
    end

    alias initialize_without_sentinel initialize
    alias initialize initialize_with_sentinel

    def establish_connection_with_sentinel
      if sentinel?
        auto_retry_with_timeout do
          discover_master
          establish_connection_without_sentinel
        end
      else
        establish_connection_without_sentinel
      end
    end

    alias establish_connection_without_sentinel establish_connection
    alias establish_connection establish_connection_with_sentinel

    def sentinel?
      !!(@master_name && @sentinels_options)
    end

    def auto_retry_with_timeout(&block)
      deadline = @failover_reconnect_timeout.to_i + Time.now.to_f
      begin
        block.call
      rescue Errno::ECONNREFUSED, Errno::EHOSTDOWN, Errno::EHOSTUNREACH => e
        raise if Time.now.to_f > deadline
        sleep @failover_reconnect_wait
        retry
      end
    end

    def new_sentinel(sentinel_options)
      Redis.new(sentinel_options)
    end

    def try_next_sentinel
      sentinel_options = @sentinels_options.shift
      @sentinels_options.push sentinel_options

      @logger.debug "Trying next sentinel: #{sentinel_options[:host]}:#{sentinel_options[:port]}" if @logger && @logger.debug?
      @current_sentinel = new_sentinel(sentinel_options)
    end

    def refresh_sentinels_list
      current_sentinel.sentinel("sentinels", @master_name).each do |response|
        @sentinels_options << {:host => response[3], :port => response[5]}
      end
      @sentinels_options.uniq! {|h| h.values_at(:host, :port) }
    end

    def switch_master(host, port)
      @uri = URI.parse("redis://#{host}:#{port}/")
    end

    def discover_master
      attempts = 0
      while true
        attempts += 1
        try_next_sentinel

        begin
          master_host, master_port = current_sentinel.sentinel("get-master-addr-by-name", @master_name)
          if master_host && master_port
            # An ip:port pair
            switch_master(master_host, master_port)
            refresh_sentinels_list
            break
          end
        rescue Redis::CommandError => e
          raise e unless e.message.include?("IDONTKNOW")
        rescue Redis::CannotConnectError, Redis::ConnectionError, Errno::EHOSTDOWN, Errno::EHOSTUNREACH => e
          # failed to connect to current sentinel server
        end

        raise "Cannot connect to master (too many attempts)" if attempts > @sentinels_options.count
      end
    end

    def call_with_readonly_protection(*args, &block)
      readonly_protection_with_timeout(:call_without_readonly_protection, *args, &block)
    end

    alias call_without_readonly_protection call
    alias call call_with_readonly_protection

    def watch_sentinel
      while true
        puts "Acquire new sentinel"
        sentinel = new_sentinel(@sentinels_options[0])

        begin
          puts "Subscribe sentinel"
          sentinel.psubscribe("*") do |on|
            on.pmessage do |pattern, channel, message|
              puts "New message"
              puts "#{pattern} #{channel} #{message}"
              next if channel != "+switch-master"

              master_name, old_host, old_port, new_host, new_port = message.split(" ")

              next if master_name != @master_name

              switch_master(new_host, new_port)

              @logger.debug "Failover: #{old_host}:#{old_port} => #{new_host}:#{new_port}" if @logger && @logger.debug?

              @connection = nil
            end
          end
        rescue Errno::ECONNREFUSED, Errno::EHOSTDOWN, Errno::EHOSTUNREACH
          puts "Cannot connect to sentinel"
          try_next_sentinel
          sleep 1
        end
      end
    end

  private
    def reconnect
      @connection = nil
      connect {}
    end

    def readonly_protection_with_timeout(method, *args, &block)
      deadline = @failover_reconnect_timeout.to_i + Time.now.to_f
      send(method, *args, &block)
    rescue StandardError => e
      if e.message.include? "READONLY You can't write against a read only slave."
        reconnect
        raise if Time.now.to_f > deadline
        sleep @failover_reconnect_wait
        retry
      else
        raise
      end
    end

    def fetch_option(options, key)
      options.delete(key) || options.delete(key.to_s)
    end

    def _parse_sentinel_options(options)
      return if options.nil?

      sentinel_options = []
      options.each do |opts|
        opts = opts[:url] if opts.is_a?(Hash) && opts.key?(:url)
        case opts
        when Hash
          sentinel_options << opts
        else
          uri = URI.parse(opts)
          sentinel_options << {
            :host => uri.host,
            :port => uri.port
          }
        end
      end
      sentinel_options
    end
  end
end
