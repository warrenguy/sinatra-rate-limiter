require 'sinatra/base'
require 'redis'

module Sinatra

  module RateLimiter

    module Helpers

      def rate_limit(*args)
        return unless settings.rate_limiter and settings.rate_limiter_environments.include?(settings.environment)

        bucket, options, limits = parse_args(args)

        limiter = RateLimit.new(bucket, limits)
        limiter.settings  = settings
        limiter.request   = request
        limiter.options   = options

        if error_locals = limits_exceeded?(limits, limiter)
          rate_limit_headers(limits, bucket, limiter) if limiter.options.send_headers
          response.headers['Retry-After'] = error_locals[:try_again]
          halt limiter.options.error_code, error_response(error_locals, limiter)
        end

        redis(limiter).setex([namespace(limiter),user_identifier(limiter),bucket,Time.now.to_f.to_s].join('/'),
                             settings.rate_limiter_redis_expires,
                             request.env['REQUEST_URI'])

        rate_limit_headers(limits, bucket, limiter) if limiter.options.send_headers
      end

      private

      def parse_args(args)
        bucket    = (args.first.class == String) ? args.shift : 'default'
        options   = (args.last.class == Hash)    ? args.pop   : {}
        limits    = (args.size < 1) ? settings.rate_limiter_default_limits : args

        if (limits.size < 1)
          raise ArgumentError, 'No explicit or default limits values provided.'
        elsif (limits.map{|a| a.class}.select{|a| a != Fixnum}.count > 0)
          raise ArgumentError, 'Non-Fixnum parameters supplied. All parameters must be Fixnum except the first which may be a String.'
        elsif ((limits.map{|a| a.class}.size % 2) != 0)
          raise ArgumentError, 'Wrong number of Fixnum parameters supplied.'
        elsif !(bucket =~ /^[a-zA-Z0-9\-]*$/)
          raise ArgumentError, 'Limit name must be a String containing only a-z, A-Z, 0-9, and -.'
        elsif (omap = (options.keys.map{|o| settings.rate_limiter_default_options.keys.include?(o)})).include?(false)
          raise ArgumentError, "Invalid option '#{options.keys[omap.index(false)]}'."
        end

        return [bucket,
                options,
                limits.each_slice(2).map{|a| {requests: a[0], seconds: a[1]}}]
      end

      def redis(limiter)
        settings.rate_limiter_redis_conn
      end

      def namespace(limiter)
        settings.rate_limiter_redis_namespace
      end

      def limit_remaining(limit, limiter)
        limit[:requests] - limiter.history(limit[:seconds]).length
      end

      def limit_reset(limit, limiter)
        limit[:seconds] - (Time.now.to_f - limiter.history(limit[:seconds]).first.to_f).to_i
      end

      def limits_exceeded?(limits, limiter)
        exceeded = limits.select {|limit| limit_remaining(limit, limiter) < 1}.sort_by{|e| e[:seconds]}.last

        if exceeded
          try_again = limit_reset(exceeded, limiter)
          return exceeded.merge({try_again: try_again.to_i})
        end
      end

      def rate_limit_headers(limits, bucket, limiter)
        header_prefix = 'X-Rate-Limit' + (bucket.eql?('default') ? '' : '-' + bucket)
        limit_no = 0 if limits.length > 1
        limits.each do |limit|
          limit_no = limit_no + 1 if limit_no
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Limit']     = limit[:requests]
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Remaining'] = limit_remaining(limit, limiter)
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Reset']     = limit_reset(limit, limiter)
        end
      end

      def error_response(locals, limiter)
        if limiter.options.error_template
          render limiter.options.error_template, locals: locals
        else
          content_type 'text/plain'
          "Rate limit exceeded (#{locals[:requests]} requests in #{locals[:seconds]} seconds). Try again in #{locals[:try_again]} seconds."
        end
      end

      def user_identifier(limiter)
        if limiter.options.identifier.class == Proc
          return limiter.options.identifier.call(request)
        else
          return request.ip
        end
      end

      def get_min_time_prefix(limits)
        now    = Time.now.to_f
        oldest = Time.now.to_f - limits.sort_by{|l| -l[:seconds]}.first[:seconds]

        return now.to_s[0..((now/oldest).to_s.split(/^1\.|[1-9]+/)[1].length)].to_i.to_s
      end

    end

    def self.registered(app)
      app.helpers RateLimiter::Helpers

      app.set :rate_limiter,                  false
      app.set :rate_limiter_environments,     [:production]
      app.set :rate_limiter_default_limits,   [10, 20]  # 10 requests per 20 seconds
      app.set :rate_limiter_redis_conn,       Redis.new
      app.set :rate_limiter_redis_namespace,  'rate_limit'
      app.set :rate_limiter_redis_expires,    24*60*60 # This must be larger than longest limit time period

      app.set :rate_limiter_default_options, {
        error_code:     429,
        error_template: nil,
        send_headers:   true,
        identifier:     Proc.new{ |request| request.ip }
      }
    end

  end

  class RateLimit
    attr_reader :history, :options

    def initialize(bucket, limits)
      @bucket        = bucket
      @limits        = limits
      @time_prefix   = get_min_time_prefix(@limits)
    end

    include Sinatra::RateLimiter::Helpers

    def history(seconds=0)
      redis_history.select{|t| seconds.eql?(0) ? true : t > (Time.now.to_f - seconds)}
    end

    def redis_history
      if @history
        @history
      else
        @history = redis(self).
          keys("#{[namespace(self),user_identifier(self),@bucket].join('/')}/#{@time_prefix}*").
          map{|k| k.split('/')[3].to_f}
      end
    end

    def options=(options)
      @options = OpenStruct.new(settings.rate_limiter_default_options.merge(options))
    end
    def options
      @options
    end

    def settings=(settings)
      @settings = settings
    end
    def settings
      @settings
    end

    def request=(request)
      @request = request
    end
    def request
      @request
    end
  end

  register RateLimiter
end
