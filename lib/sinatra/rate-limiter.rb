require 'sinatra/base'
require 'redis'

module Sinatra

  module RateLimiter

    module Helpers

      def rate_limit(*args)
        return unless settings.rate_limiter and settings.rate_limiter_environments.include?(settings.environment)

        limit_name, limits = parse_args(args)

        if error_locals = limits_exceeded?(limits, limit_name)
          rate_limit_headers(limits, limit_name)
          response.headers['Retry-After'] = error_locals[:try_again] if settings.rate_limiter_send_headers
          halt settings.rate_limiter_error_code, error_response(error_locals)
        end

        redis.setex([namespace,user_identifier,limit_name,Time.now.to_f.to_s].join('/'),
                    settings.rate_limiter_redis_expires,
                    request.env['REQUEST_URI'])

        rate_limit_headers(limits, limit_name) if settings.rate_limiter_send_headers
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
        end

        limits = args.each_slice(2).to_a.map{|a| {requests: a[0], seconds: a[1]}}

        return [limit_name, limits]
      end

      def redis
        settings.rate_limiter_redis_conn
      end

      def namespace
        settings.rate_limiter_redis_namespace
      end

      def limit_history(limit_name, seconds=0)
        redis.
          keys("#{[namespace,user_identifier,limit_name].join('/')}/*").
          map{|k| k.split('/')[3].to_f}.
          select{|t| seconds.eql?(0) ? true : t > (Time.now.to_f - seconds)}
      end

      def limit_remaining(limit, limit_name)
        limit[:requests] - limit_history(limit_name, limit[:seconds]).length
      end

      def limit_reset(limit, limit_name)
        limit[:seconds] - (Time.now.to_f - limit_history(limit_name, limit[:seconds]).first).to_i
      end

      def limits_exceeded?(limits, limit_name)
        exceeded = limits.select {|limit| limit_remaining(limit, limit_name) < 1}.sort_by{|e| e[:seconds]}.last

        if exceeded
          try_again = limit_reset(exceeded, limit_name)
          return exceeded.merge({try_again: try_again.to_i})
        end
      end

      def rate_limit_headers(limits, limit_name)
        header_prefix = 'X-Rate-Limit' + (limit_name.eql?('default') ? '' : '-' + limit_name)
        limit_no = 0 if limits.length > 1
        limits.each do |limit|
          limit_no = limit_no + 1 if limit_no
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Limit']     = limit[:requests]
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Remaining'] = limit_remaining(limit, limit_name)
          response.headers[header_prefix + (limit_no ? "-#{limit_no}" : '') + '-Reset']     = limit_reset(limit, limit_name)
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
      app.set :rate_limiter_redis_expires,    24*60*60
    end

  end

end
