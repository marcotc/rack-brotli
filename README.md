# Rack::Brotli [![Gem Version](https://badge.fury.io/rb/rack-brotli.svg)](https://badge.fury.io/rb/rack-brotli) [![Build Status](https://github.com/marcotc/rack-brotli/actions/workflows/test.yml/badge.svg)](https://github.com/marcotc/rack-brotli/actions/workflows/test.yml)

![Brötli, the Swiss German word for a bread roll, on a Rack with some Ruby decorations](https://github.com/marcotc/rack-brotli/assets/583503/8b4af461-ed2c-4b67-8a94-45b228bd59d4)

`Rack::Brotli` compresses `Rack` responses using [Google's Brotli](https://github.com/google/brotli) compression algorithm.

Brotli generally compresses better than `gzip` for the same CPU cost and is supported by [pretty much everywhere](http://caniuse.com/#feat=brotli).

### Use

Install gem:

    gem install rack-brotli

Requiring `'rack/brotli'` will autoload the `Rack::Brotli` module.

The following example shows what a simple rackup (`config.ru`) file might look like:

```ruby
require 'rack'
require 'rack/brotli'

use Rack::Brotli # Default compression quality is 5

# You can also provide native Brotli compression options:
# use Rack::Brotli, quality: 11

run theapp
```

For a Ruby on Rails application, add to your `config/application.rb`:
```ruby
config.middleware.use Rack::Deflater
# Rack::Brotli goes directly under Rack::Deflater, if Rack::Deflater is present
config.middleware.use Rack::Brotli
```

### Testing

To run the entire test suite, run 

    bundle exec rake test

### Links

* rack-brotli: <http://github.com/marcotc/rack-brotli>
* Brotli for Ruby: <https://github.com/miyucy/brotli>
* Rack: <http://github.com/rack/rack>
