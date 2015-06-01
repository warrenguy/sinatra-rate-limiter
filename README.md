# sinatra/rate-limiter

A customisable redis backed rate limiter for Sinatra applications.

This rate limiter extension operates on a leaky bucket principle. Each
request that the rate limiter sees logs a new item in the redis store. If
more than the allowable number of requests have been made in the given time
then no new item is logged and the request is aborted. The items stored in
redis include a bucket name and timestamp in their key name. This allows
multiple "buckets" to be used and for variable rate limits to be applied to
different requests using the same bucket.

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

### Defining rate limits

Use `rate_limit` in the pipeline of any route (i.e. in the route itself, or
in a `before` filter, or in a Padrino controller, etc. `rate_limit` takes
zero to infinite parameters, with the syntax:

  ```
  rate_limit [BucketName], [[<Requests>, <Seconds>], ...], [[<Key>: <Value>], ...]
  ```

The `String` optionally defines a named bucket. The following pairs of
`Fixnum`s define `[requests, seconds]`, allowing you to specify how many
requests per seconds are allowed for this route/path. Finally overrides for
the globally defined default options can be provided.

See the _Examples_ section below for usage examples.

### Error handling

When a rate limit is exceeded, the exception `Sinatra::RateLimiter::Exceeded`
is thrown. By default, this sends an response code `429` with an informative
plain text error message. You can use Sinatra's error handling to customise
this. E.g.:

  ```
  error Sinatra::RateLimiter::Exceeded do
    status 400
    content_type :json

    {error: { message: env['sinatra.error'].message } }.to_json
  end
  ```

As well as the default error message being available in
`env['sinatra.error'].message`, `the env['sinatra.error.rate_limiter']`
object contains three values for the exceeded limit:

 * `.requests` Integer of the number of requests allowed
 * `.seconds` Integer of the number of seconds the request limit applies to
 * `.try_again` Integer the number of seconds until the limit resets

## Configuration

All configuration is optional. If no default limits are specified here,
you must specify limits with each call of `rate_limit`

### Defaults

   ```ruby
   set :rate_limiter_environments,     [:production]
   set :rate_limiter_default_limits,   [10, 20]
   set :rate_limiter_redis_conn,       Redis.new
   set :rate_limiter_redis_namespace,  'rate_limit'
   set :rate_limiter_redis_expires,    24*60*60

   set :rate_limiter_default_options, {
     send_headers:   true,
     header_prefix:  'Rate-Limit',
     identifier:     Proc.new{ |request| request.ip }
   }
   ```

#### `rate_limiter_environments` (Array)

An Array of Rack environments to enable the rate limiter for.

#### `rate_limiter_default_limits` (Array)

Default limit parameters.

#### `rate_limiter_redis_conn` (Redis)

Redis connection definition (e.g. global variable pointing at your already
defined Redis connection, or a ConnectionPool, etc).

#### `rate_limiter_redis_namespace` (String)

The Redis namespace to use. All keys stored in the Redis store will be
prefixed with this string plus a forward-slash (`/`).

#### `rate_limiter_redis_expires` (Integer)

How long keys live in the Redis store for. This must be longer than any
limiter's longest 'seconds' parameter.

#### `rate_limiter_default_options` (Hash)

Default options provided to each call of `rate_limit`

##### `send_headers` (Boolean)

Whether or not to send `Rate-Limit-*` headers to the client with each
request.

Three headers are sent per defined limit:

 * `Rate-Limit-Limit` the number of requests allowed per period
 * `Rate-Limit-Remaining` the number of requests left in the current period
 * `Rate-Limit-Reset` the number of seconds remaining until the limit resets

If a bucket name is defined, it will be included in the header in the format
`Rate-Limit-Bucketname-*`. If more than one limit is defined, a number will
also be added to differentiate them, e.g `Rate-Limit-1-*`, `Rate-Limit-2-*`,
`Rate-Limit-Bucketname-1-*`, etc.

Additionally, a `Retry-After` header is sent containing the number of
seconds remaining until the limit resets.

##### `header_prefix` (String)

Prefix for HTTP headers sent to client. Default is `Rate-Limit` (per 
[RFC 6648](https://tools.ietf.org/html/rfc6648) deprecating the `X-` prefix)
however some users may wish or need to send `X-Rate-Limit` or some other
arbitrary header prefix instead.

##### `identifier` (Proc)

A `Proc` taking exactly one parameter (`request`) which returns a String
identifying the client for the purposes of rate limiting. Defaults to the
clients IP address (from `request.ip`) but you could use the value of a 
cookie, a session ID, username, or anything else accessible from Sinatra's
`request` object.

## Examples

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
buckets assigned to the remaining routes. It identifiers the client by the
value of the cookie `userid` instead of by IP address.

  ```ruby
  set :rate_limiter_default_limits,  [1000, 60*60]
  set :rate_limiter_default_options, send_headers: true,
                                     identifier: Proc.new{|request| request.cookies['userid']}

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
    rate_limit 'ratelimit2', 1, 10, send_headers: false

    "this route is rate limited to 1 request per 10 seconds, and won't send
     any headers"
  end
  ```

N.B. in the last example, be aware that the more specific rate limits do not
override any rate limit already defined during route processing, and the
first rate limit specified in `before` will apply additionally. If you call
`rate_limit` more than once with the same (or no) bucket name, the request
will be double counted in that bucket.

## License

MIT license. See [LICENSE](https://github.com/warrenguy/sinatra-rate-limiter/blob/master/LICENSE).

## Author

Warren Guy <warren@guy.net.au>

https://warrenguy.me
