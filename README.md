# sinatra/rate-limiter

A customisable redis backed rate limiter for Sinatra applications.

This rate limiter extension operates on a leaky bucket principle. Each
request that the rate limiter sees logs a new item in the redis store. If
more than the allowable number of requests have been made in the given time
then no new item is logged and the request is aborted. The items stored in
redis include a bucket name and timestamp in their key name. This allows
multiple "buckets" to be used and for variable rate limits to be applied to
different requests using the same bucket. See the _Usage_ section below for
examples demonstrating this.

## Installing

 * Add the gem to your Gemfile

   ```ruby
   source 'https://rubygems.org'
   gem 'sinatra-rate-limiter'
   ```

 * Require and enable it in your app after including Sinatra

   ```ruby
   require 'sinatra'
   require 'sinatra/rate-limiter'

   enable :rate_limiter

   ...
   ```

 * Modular applications must explicitly register the extension, e.g.

   ```ruby
   require 'sinatra/base'
   require 'sinatra/rate-limiter'

   class ModularApp < Sinatra::Base
     register Sinatra::RateLimiter
     enable :rate_limiter

     ...
   end
   ```

## Usage

Use `rate_limit` in the pipeline of any route (i.e. in the route itself, or
in a `before` filter, or in a Padrino controller, etc. `rate_limit` takes
zero to infinite parameters, with the syntax:

  ```
  rate_limit [String], [[<Fixnum>, <Fixnum>], [<Fixnum>, <Fixnum>], ...]
  ```

The `String` optionally defines a named bucket. The following pairs of
`Fixnum`s define `[requests, seconds]`, allowing you to specify how many
requests per seconds are allowed for this route/path.

The following route will be limited to 10 requests per minute and 100
requests per hour:

  ```ruby
  get '/rate-limited' do
    rate_limit 'default', 10, 60, 100, 60*60

    "now you see me"
  end
  ```

The following will apply a limit of 1000 requests per hour using the default
bucket to all routes and stricter individual rate limits with additional
buckets assigned to the remaining routes.

  ```ruby
  set :rate_limiter_default_limits, [1000, 60*60]
  before do
    rate_limit
  end

  get '/' do
    "this route has only the global limit applied"
  end

  get '/rate-limit-1/example-1' do
    rate_limit 'ratelimit1', 2,  5,
                             10, 60 

    "this route is rate limited to 2 requests per 5 seconds and 10 per 60
     seconds in addition to the global limit of 1000 per hour"
  end

  get '/rate-limit-1/example-2' do
    rate_limit 'ratelimit1', 60, 60

    "this route is rate limited to 60 requests per minute using the same
     bucket as '/rate-limit-1'. "

  get '/rate-limit-2' do
    rate_limit 'ratelimit2', 1, 10

    "this route is rate limited to 1 request per 10 seconds"
  end
  ```

N.B. in the last example, be aware that the more specific rate limits do not
override any rate limit already defined during route processing, and the
first rate limit specified in `before` will apply additionally. If you call
`rate_limit` more than once with the same (or no) bucket name, the request
will be double counted in that bucket.

## Configuration

All configuration is optional. If no default limits are specified here,
you must specify limits with each call of `rate_limit`

### Defaults

   ```ruby
   set :rate_limiter_default_limits,   []
   set :rate_limiter_environments,     [:production]
   set :rate_limiter_error_code,       429
   set :rate_limiter_error_template,   nil
   set :rate_limiter_send_headers,     true
   set :rate_limiter_custom_user_id,   nil
   set :rate_limiter_redis_conn,       Redis.new
   set :rate_limiter_redis_namespace,  'rate_limit'
   set :rate_limiter_redis_expires,    24*60*60
   ```

TODO: document each setting here explicitly

## License

MIT license. See [LICENSE](https://github.com/warrenguy/sinatra-rate-limiter/blob/master/LICENSE).

## Author

Warren Guy <warren@guy.net.au>

https://warrenguy.me
