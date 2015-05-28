require 'sinatra/base'
require 'redis'

module Sinatra

  module RateLimiter

    module Helpers

      def rate_limit(*args)
        return unless settings.rate_limiter and settings.rate_limiter_environments.include?(settings.environment)

        limit_name, limits = parse_args(args)

        limiter = RateLimit.new(limit_name, limits)
        limiter.settings = settings
        limiter.request  = request

        if error_locals = limits_exceeded?(limits, limiter)
          rate_limit_headers(limits, limit_name, limiter)
          response.headers['Retry-After'] = error_locals[:try_again] if settings.rate_limiter_send_headers
          halt settings.rate_limiter_error_code, error_response(error_locals)
        end

        redis.setex([namespace,user_identifier,limit_name,Time.now.to_f.to_s].join('/'),
                    settings.rate_limiter_redis_expires,
                    request.env['REQUEST_URI'])

        rate_limit_headers(limits, limit_name, limiter) if settings.rate_limiter_send_headers
      end

      private

      def parse_args(args)
        limit_name = args.map{|a| a.class}.first.eql?(String) ? args.shift : 'default'
        args = settings.rate_limiter_default_limits if args.size < 1

        if (args.size < 1)
          raise ArgumentError, 'No explicit or default limits values provided.'
        elsif (args.map{|a| a.class}.select{|a| a != Fixnum}.count > 0)
          raise ArgumentError, 'Non-Fixnum parameters supplied. All parameters must be Fixnum except the first which may be a String.'
        elsif ((args.map{|a| a.class}.size % 2) != 0)
          raise ArgumentError, 'Wrong number of Fixnum parameters supplied.'
        elsif !(limit_name =~ /^[a-zA-Z0-9\-]*$/)
          raise ArgumentError, 'Limit name must be a String containing only a-z, A-Z, 0-9, and -.'
        end

        return [limit_name,
                args.each_slice(2).map{|a| {requests: a[0], seconds: a[1]}}]
      end

      def redis
        settings.rate_limiter_redis_conn
      end

      def namespace
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

      def rate_limit_headers(limits, limit_name, limiter)
        header_prefix = 'X-Rate-Limit' + (limit_name.eql?('default') ? '' : '-' + limit_name)
        limit_no = 0 if limits.length > 1
        limits.each do |limit|
          limit_no = limit_no + 1 if limit_no
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Limit']     = limit[:requests]
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Remaining'] = limit_remaining(limit, limiter)
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Reset']     = limit_reset(limit, limiter)
        end
      end

      def error_response(locals)
        if settings.rate_limiter_error_template
          render settings.rate_limiter_error_template, locals: locals
        else
          content_type 'text/plain'
          "Rate limit exceeded (#{locals[:requests]} requests in #{locals[:seconds]} seconds). Try again in #{locals[:try_again]} seconds."
        end
      end

      def user_identifier
        if settings.rate_limiter_custom_user_id.class == Proc
          return settings.rate_limiter_custom_user_id.call(request)
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
      app.set :rate_limiter_default_limits,   []  # 10 requests per minute: [{requests: 10, seconds: 60}] 
      app.set :rate_limiter_environments,     [:production]
      app.set :rate_limiter_error_code,       429 # http://tools.ietf.org/html/rfc6585
      app.set :rate_limiter_error_template,   nil # locals: requests, seconds, try_again
      app.set :rate_limiter_send_headers,     true
      app.set :rate_limiter_custom_user_id,   nil # Proc.new { Proc.new{ |request| request.ip } }
                                                  # must be wrapped with another Proc because Sinatra
                                                  # evaluates Procs in settings when reading them.
      app.set :rate_limiter_redis_conn,       Redis.new
      app.set :rate_limiter_redis_namespace,  'rate_limit'
      app.set :rate_limiter_redis_expires,    24*60*60 # This must be larger than longest limit time period
    end

  end

  class RateLimit
    attr_reader :history

    def initialize(limit_name, limits)
      @limit_name    = limit_name
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
        @history = redis.
          keys("#{[namespace,user_identifier,@limit_name].join('/')}/#{@time_prefix}*").
          map{|k| k.split('/')[3].to_f}
      end
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
