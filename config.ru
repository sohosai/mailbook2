require 'bundler'
Bundler.require

require 'rack/protection'

use Rack::Session::Cookie, expire_after: 60*60*24*365, secret: 'hogesohosai'
use Rack::Protection::AuthenticityToken

require './main'

require 'webrick'
WEBrick::Config::HTTP[:DoNotReverseLookup] = true

run Mailbook
