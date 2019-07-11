# Rack::Brotli [![Build Status](https://travis-ci.org/marcotc/rack-brotli.svg?branch=master)](https://travis-ci.org/marcotc/rack-brotli)

`Rack::Brotli` compresses `Rack` responses using [Google's Brotli](https://github.com/google/brotli) compression algorithm.

Brotli generally compresses better than `gzip` for the same CPU cost and is supported by [Chrome, Firefox, IE and Opera](http://caniuse.com/#feat=brotli).

### Use

Install gem:

    gem install rack-brotli

Requiring `'rack/brotli'` will autoload `Rack::Brotli` module. The following example shows what a simple rackup
(`config.ru`) file might look like:

```ruby
require 'rack'
require 'rack/brotli'

use Rack::Brotli

run theapp
```

### Testing

To run the entire test suite, run 

    rake test

### Links

* rack-brotli on GitHub:: <http://github.com/marcotc/rack-brotli>
* Rack:: <http://rack.rubyforge.org/>
* Rack On GitHub:: <http://github.com/rack/rack>
