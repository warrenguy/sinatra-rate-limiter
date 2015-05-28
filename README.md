# sinatra/rate-limiter

A customisable redis backed rate limiter for Sinatra applications.

## Installing

 * Add the gem to your Gemfile

   ```ruby
   source 'https://rubygems.org'
   gem 'sinatra-rate-limiter'
   ```

 * Require and enable it in your app after including Sinatra

   ```ruby
   require 'sinatra/rate-limiter'
   enable :rate_limiter
   ```

## Usage

Use `rate_limit` in the pipeline of any route (i.e. in the route itself, or
in a `before` filter, or in a Padrino controller, etc. `rate_limit` takes
zero to infinite parameters, with the syntax:

  ```rate_limit [String], [[<Fixnum>, <Fixnum>], [<Fixnum>, <Fixnum>], ...]```

The `String` optionally defines a name for this rate limiter, allowing you
to have multiple rate limits within your app. The following pairs of
`Fixnum`s define `[requests, seconds]`, allowing you to specify how many
requests per seconds this rate limiter allows.

The following route will be limited to 10 requests per minute and 100
requests per hour:

  ```ruby
  get '/rate-limited' do
    rate_limit 'default', 10, 60, 100, 60*60

    "now you see me"
  end
  ```

The following will apply an unnamed limit of 1000 requests per hour to all
routes and stricter individual rate limits to two particular routes:

  ```ruby
  set :rate_limiter_default_limits, [1000, 60*60]
  before do
    rate_limit
  end

  get '/' do
    "this route has the global limit applied"
  end

  get '/rate-limit-1' do
    rate_limit 'ratelimit1', 2,  5,
                             10, 60 

    "this route is rate limited to 2 requests per 5 seconds and 10 per 60 seconds"
  end

  get '/rate-limit-2' do
    rate_limit 'ratelimit2', 1, 10

    "this route is rate limited to 1 request per 10 seconds"
  end
  ```

N.B. in the last example, be aware that the more specific rate limits do not
override any rate limit already defined during route processing, and the
global rate limit will apply additionally. If you call `rate_limit` more than
once with the same (or no) name, it will be double counted.

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
