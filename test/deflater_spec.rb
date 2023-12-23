require 'minitest/autorun'
require 'stringio'
require 'rack/brotli'
require 'rack/lint'
require 'rack/mock'

describe Rack::Brotli do

  def build_response(status, body, accept_encoding, options = {})
    body = [body] if body.respond_to? :to_str
    app = lambda do |env|
      res = [status, options['response_headers'] || {}, body]
      res[1]['content-type'] = 'text/plain' unless res[0] == 304
      res
    end

    request = Rack::MockRequest.env_for('', (options['request_headers'] || {}).merge('HTTP_ACCEPT_ENCODING' => accept_encoding))
    deflater = Rack::Lint.new Rack::Brotli::Deflater.new(app, options['deflater_options'] || {})

    deflater.call(request)
  end

  ##
  # Constructs response object and verifies if it yields right results
  #
  # [expected_status] expected response status, e.g. 200, 304
  # [expected_body] expected response body
  # [accept_encoing] what Accept-Encoding header to send and expect, e.g.
  #                  'br' - accepts and expects br encoding in response
  #                  { 'br' => nil } - accepts br but expects no encoding in response
  # [options] hash of request options, i.e.
  #           'app_status' - what status dummy app should return (may be changed by deflater at some point)
  #           'app_body' - what body dummy app should return (may be changed by deflater at some point)
  #           'request_headers' - extra request headers to be sent
  #           'response_headers' - extra response headers to be returned
  #           'deflater_options' - options passed to deflater middleware
  # [block] useful for doing some extra verification
  def verify(expected_status, expected_body, accept_encoding, options = {}, response_size = nil, &block)
    accept_encoding, expected_encoding = if accept_encoding.kind_of?(Hash)
                                           [accept_encoding.keys.first, accept_encoding.values.first]
                                         else
                                           [accept_encoding, accept_encoding.dup]
                                         end

    # build response
    status, headers, body = build_response(
      options['app_status'] || expected_status,
      options['app_body'] || expected_body,
      accept_encoding,
      options
    )

    # verify status
    status.must_equal expected_status

    # verify body
    unless options['skip_body_verify']
      # Use String.new instead of '' to support environments with strings frozen by default.
      body_text = String.new
      body.each { |part| body_text << part }

      deflated_body = case expected_encoding
                        when 'br'
                          io = StringIO.new(body_text)
                          string_body = io.string
                          string_body.size.must_equal response_size if response_size
                          Brotli.inflate(string_body)
                        else
                          body_text
                      end

      deflated_body.must_equal expected_body
    end

    # yield full response verification
    yield(status, headers, body) if block_given?
  end

  def auto_inflater
    ::Brotli
  end

  def br_encoding
    {'br' => 'br'}
  end

  it 'be able to deflate bodies that respond to each' do
    app_body = Object.new
    class << app_body; def each; yield('foo'); yield('bar'); end; end

    verify(200, 'foobar', br_encoding, { 'app_body' => app_body }) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'flush deflated chunks to the client as they become ready' do
    skip 'TODO Create brotli Ruby gem that accepts stream processing' do
      app_body = Object.new
      class << app_body; def each; yield('foo'); yield('bar'); end; end

      verify(200, app_body, br_encoding, { 'skip_body_verify' => true }) do |status, headers, body|
        headers.must_equal({
                             'content-encoding' => 'br',
                             'vary' => 'Accept-Encoding',
                             'content-type' => 'text/plain'
                           })

        buf = []
        inflater = auto_inflater
        body.each { |part| buf << inflater.inflate(part) }
        buf << inflater.finish

        buf.delete_if { |part| part.empty? }.join.must_equal 'foobar'
      end
    end
  end

  it 'does not raise when a client aborts reading' do
    app_body = Object.new
    class << app_body; def each; yield('foo'); yield('bar'); end; end
    opts = { 'skip_body_verify' => true }
    verify(200, app_body, 'br', opts) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })

      buf = []
      inflater = auto_inflater
      FakeDisconnect = Class.new(RuntimeError)
      assert_raises(FakeDisconnect, "not Zlib::DataError not raised") do
        body.each do |part|
          tmp = inflater.inflate(part)
          buf << tmp if tmp.bytesize > 0
          raise FakeDisconnect
        end
      end
      #inflater.finish
      buf.must_equal(%w(foobar))
    end
  end

  # TODO: This is really just a special case of the above...
  it 'be able to deflate String bodies' do
    verify(200, 'Hello world!', br_encoding) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'be able to br bodies that respond to each' do
    app_body = Object.new
    class << app_body; def each; yield('foo'); yield('bar'); end; end

    verify(200, 'foobar', 'br', { 'app_body' => app_body }) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'flush br chunks to the client as they become ready' do
    skip 'TODO Create brotli Ruby gem that accepts stream processing' do
      app_body = Object.new
      class << app_body; def each; yield('foo'); yield('bar'); end; end

      verify(200, app_body, 'br', { 'skip_body_verify' => true }) do |status, headers, body|
        headers.must_equal({
                             'content-encoding' => 'br',
                             'vary' => 'Accept-Encoding',
                             'content-type' => 'text/plain'
                           })

        buf = []
        inflater = Zlib::Inflate.new(Zlib::MAX_WBITS + 32)
        body.each { |part| buf << inflater.inflate(part) }
        buf << inflater.finish

        buf.delete_if { |part| part.empty? }.join.must_equal 'foobar'
      end
    end
  end

  it 'be able to fallback to no deflation' do
    verify(200, 'Hello world!', 'superzip') do |status, headers, body|
      headers.must_equal({
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'be able to skip when there is no response entity body' do
    verify(304, '', { 'br' => nil }, { 'app_body' => [] }) do |status, headers, body|
      headers.must_equal({})
    end
  end

  it 'handle the lack of an acceptable encoding' do
    app_body = 'Hello world!'
    not_found_body1 = app_body
    not_found_body2 = app_body
    options1 = {
      'app_status' => 200,
      'app_body' => app_body,
      'request_headers' => {
        'PATH_INFO' => '/'
      }
    }
    options2 = {
      'app_status' => 200,
      'app_body' => app_body,
      'request_headers' => {
        'PATH_INFO' => '/foo/bar'
      }
    }

    verify(200, not_found_body1, 'identity;q=0', options1) do |status, headers, body|
      headers.must_equal({
                           'content-type' => 'text/plain'
                         })
    end

    verify(200, not_found_body2, 'identity;q=0', options2) do |status, headers, body|
      headers.must_equal({
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'do nothing when no-transform Cache-Control directive present' do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain',
        'cache-control' => 'no-transform'
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options) do |status, headers, body|
      headers.wont_include 'content-encoding'
    end
  end

  it 'do nothing when Content-Encoding already present' do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain',
        'content-encoding' => 'br'
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options)
  end

  it 'identity when Content-Encoding is identity' do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain',
        'content-encoding' => 'identity'
      }
    }
    verify(200, 'Hello World!', br_encoding, options)
  end

  it "br if content-type matches :include" do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain'
      },
      'deflater_options' => {
        :include => %w(text/plain)
      }
    }
    verify(200, 'Hello World!', 'br', options)
  end

  it "br if content-type is included it :include" do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain; charset=us-ascii'
      },
      'deflater_options' => {
        :include => %w(text/plain)
      }
    }
    verify(200, 'Hello World!', 'br', options)
  end

  it "not br if content-type is not set but given in :include" do
    options = {
      'deflater_options' => {
        :include => %w(text/plain)
      }
    }
    verify(304, 'Hello World!', { 'br' => nil }, options)
  end

  it "not br if content-type do not match :include" do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain'
      },
      'deflater_options' => {
        :include => %w(text/json)
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options)
  end

  it "br response if :if lambda evaluates to true" do
    options = {
      'deflater_options' => {
        :if => lambda { |env, status, headers, body| true }
      }
    }
    verify(200, 'Hello World!', br_encoding, options)
  end

  it "not br if :if lambda evaluates to false" do
    options = {
      'deflater_options' => {
        :if => lambda { |env, status, headers, body| false }
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options)
  end

  it "check for Content-Length via :if" do
    response = 'Hello World!'
    response_len = response.length
    options = {
      'response_headers' => {
        'Content-Length' => response_len.to_s
      },
      'deflater_options' => {
        :if => lambda { |env, status, headers, body|
          headers['Content-Length'].to_i >= response_len
        }
      }
    }

    verify(200, response, 'br', options)
  end

  it "use provided deflate options" do
    response = 'Hello World!' * 2
    options = {
      'deflater_options' => {
        :deflater => {
          mode: :generic, quality: 1, lgwin: 10, lgblock: 24
        }
      }
    }

    verify(200, response, 'br', options, 28)
  end

  it "use sensible default deflate options" do
    response = 'Hello World!' * 2

    verify(200, response, 'br', {}, 19)
  end
end
