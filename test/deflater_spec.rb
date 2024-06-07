require 'minitest/autorun'

require 'rack/lint'
require 'rack/mock'

require 'rack/brotli'

describe Rack::Brotli do

  def build_response(status, body, accept_encoding, options = {})
    body = [body] if body.respond_to? :to_str
    app = lambda do |env|
      res = [status, options['response_headers'] || {}, body]
      res[1]['content-type'] = 'text/plain' unless res[0] == 304
      res
    end

    request = Rack::MockRequest.env_for('', (options['request_headers'] || {}).merge('HTTP_ACCEPT_ENCODING' => accept_encoding))
    deflater = Rack::Lint.new Rack::Brotli.new(app, options['deflater_options'] || {})

    deflater.call(request)
  end

  ##
  # Constructs response object and verifies if it yields right results
  #
  # [expected_status] expected response status, e.g. 200, 304
  # [expected_body] expected response body
  # [accept_encoding] what Accept-Encoding header to send and expect, e.g.
  #                  'br' - accepts and expects deflate encoding in response
  #                  { 'br' => nil } - accepts `br` but expects no encoding in response
  # [options] hash of request options, i.e.
  #           'app_status' - what status dummy app should return (may be changed by deflater at some point)
  #           'app_body' - what body dummy app should return (may be changed by deflater at some point)
  #           'request_headers' - extra request headers to be sent
  #           'response_headers' - extra response headers to be returned
  #           'deflater_options' - options passed to deflater middleware
  # [block] useful for doing some extra verification
  def verify(expected_status, expected_body, accept_encoding, options = {}, &block)
    accept_encoding, expected_encoding = if accept_encoding.kind_of?(Hash)
                                           [accept_encoding.keys.first, accept_encoding.values.first]
                                         else
                                           [accept_encoding, accept_encoding.dup]
                                         end

    start = Time.now.to_i

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
      body_text = ''.dup
      body.each { |part| body_text << part }

      deflated_body = case expected_encoding
                      when 'br'
                        io = StringIO.new(body_text)
                        string_body = io.string
                        Brotli.inflate(string_body)
                      else
                        body_text
                      end

      deflated_body.must_equal expected_body
    end

    # yield full response verification
    yield(status, headers, body) if block_given?
    body.close if body.respond_to?(:close)
  end

  def inflater
    Brotli
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

  it 'should not update vary response header if it includes * or accept-encoding' do
    verify(200, 'foobar', br_encoding, 'response_headers' => { 'vary' => 'Accept-Encoding' } ) do |status, headers, body|
      headers['vary'].must_equal 'Accept-Encoding'
    end
    verify(200, 'foobar', br_encoding, 'response_headers' => { 'vary' => '*' } ) do |status, headers, body|
      headers['vary'].must_equal '*'
    end
    verify(200, 'foobar', br_encoding, 'response_headers' => { 'vary' => 'Do-Not-Accept-Encoding' } ) do |status, headers, body|
      headers['vary'].must_equal 'Do-Not-Accept-Encoding,Accept-Encoding'
    end
  end

  it 'be able to deflate bodies that respond to each and contain empty chunks' do
    app_body = Object.new
    class << app_body; def each; yield('foo'); yield(''); yield('bar'); end; end

    verify(200, 'foobar', br_encoding, { 'app_body' => app_body }) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'flush deflated chunks to the client as they become ready' do
    app_body = Object.new
    class << app_body; def each; yield('foo'); yield('bar'); end; end

    verify(200, app_body, br_encoding, { 'skip_body_verify' => true }) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })

      buf = ""
      body.each { |part| buf << part }

      inflater.inflate(buf).must_equal 'foobar'
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

      buf = ""
      FakeDisconnect = Class.new(RuntimeError)
      assert_raises(FakeDisconnect) do
        body.each do |part|
          buf << part if part.bytesize > 0
          raise FakeDisconnect
        end
      end
      buf.must_include("foo")
      buf.wont_include("bar")
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

  it 'be able to compress bodies that respond to each' do
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

  it 'be able to compress files' do
    verify(200, File.binread(__FILE__), 'br', { 'app_body' => File.open(__FILE__)}) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })
    end
  end

  it 'flush compressed chunks to the client as they become ready' do
    app_body = Object.new
    class << app_body; def each; yield('foo'); yield('bar'); end; end

    verify(200, app_body, 'br', { 'skip_body_verify' => true }) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })

      buf = ""
      body.each { |part| buf << part }

      inflater.inflate(buf).must_equal 'foobar'
    end
  end

  it 'be able to fallback to no deflation' do
    verify(200, 'Hello world!', 'superbr') do |status, headers, body|
      headers.must_equal({
                           'vary' => 'Accept-Encoding',
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
    not_found_body1 = 'An acceptable encoding for the requested resource / could not be found.'
    not_found_body2 = 'An acceptable encoding for the requested resource /foo/bar could not be found.'
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

    app_body3 = [app_body]
    closed = false
    app_body3.define_singleton_method(:close){closed = true}
    options3 = {
      'app_status' => 200,
      'app_body' => app_body3,
      'request_headers' => {
        'PATH_INFO' => '/'
      }
    }

    verify(406, not_found_body1, 'identity;q=0', options1) do |status, headers, body|
      headers.must_equal({
                           'content-type' => 'text/plain',
                           'content-length' => not_found_body1.length.to_s
                         })
    end

    verify(406, not_found_body2, 'identity;q=0', options2) do |status, headers, body|
      headers.must_equal({
                           'content-type' => 'text/plain',
                           'content-length' => not_found_body2.length.to_s
                         })
    end

    verify(406, not_found_body1, 'identity;q=0', options3) do |status, headers, body|
      headers.must_equal({
                           'content-type' => 'text/plain',
                           'content-length' => not_found_body1.length.to_s
                         })
    end
    closed.must_equal true
  end

  it 'do nothing when no-transform cache-control directive present' do
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

  it 'do nothing when content-encoding already present' do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain',
        'content-encoding' => 'br'
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options)
  end

  it 'deflate when content-encoding is identity' do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain',
        'content-encoding' => 'identity'
      }
    }
    verify(200, 'Hello World!', br_encoding, options)
  end

  it "deflate if content-type matches :include" do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain'
      },
      'deflater_options' => {
        include: %w(text/plain)
      }
    }
    verify(200, 'Hello World!', 'br', options)
  end

  it "deflate if content-type is included it :include" do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain; charset=us-ascii'
      },
      'deflater_options' => {
        include: %w(text/plain)
      }
    }
    verify(200, 'Hello World!', 'br', options)
  end

  it "not deflate if content-type is not set but given in :include" do
    options = {
      'deflater_options' => {
        include: %w(text/plain)
      }
    }
    verify(304, 'Hello World!', { 'br' => nil }, options)
  end

  it "not deflate if content-type do not match :include" do
    options = {
      'response_headers' => {
        'content-type' => 'text/plain'
      },
      'deflater_options' => {
        include: %w(text/json)
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options)
  end

  it "not deflate if content-length is 0" do
    options = {
      'response_headers' => {
        'content-length' => '0'
      },
    }
    verify(200, '', { 'br' => nil }, options)
  end

  it "deflate response if :if lambda evaluates to true" do
    options = {
      'deflater_options' => {
        if: lambda { |env, status, headers, body| true }
      }
    }
    verify(200, 'Hello World!', br_encoding, options)
  end

  it "not deflate if :if lambda evaluates to false" do
    options = {
      'deflater_options' => {
        if: lambda { |env, status, headers, body| false }
      }
    }
    verify(200, 'Hello World!', { 'br' => nil }, options)
  end

  it "check for content-length via :if" do
    response = 'Hello World!'
    response_len = response.length
    options = {
      'response_headers' => {
        'content-length' => response_len.to_s
      },
      'deflater_options' => {
        if: lambda { |env, status, headers, body|
          headers['content-length'].to_i >= response_len
        }
      }
    }

    verify(200, response, 'br', options)
  end

  it 'will honor sync: false to avoid unnecessary flushing' do
    app_body = Object.new
    class << app_body
      def each
        (0..20).each { |i| yield "hello\n" }
      end
    end

    options = {
      'deflater_options' => { sync: false },
      'app_body' => app_body,
      'skip_body_verify' => true,
    }
    verify(200, app_body, br_encoding, options) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })

      buf = ''.dup
      raw_bytes = 0
      body.each do |part|
        raw_bytes += part.bytesize
        buf << inflater.inflate(part)
      end
      expect = "hello\n" * 21
      buf.must_equal expect
      raw_bytes.must_be(:<, expect.bytesize)
    end
  end

  it 'will honor sync: false to avoid unnecessary flushing when deflating files' do
    content = File.binread(__FILE__)
    options = {
      'deflater_options' => { sync: false },
      'app_body' => File.open(__FILE__),
      'skip_body_verify' => true,
    }
    verify(200, content, br_encoding, options) do |status, headers, body|
      headers.must_equal({
                           'content-encoding' => 'br',
                           'vary' => 'Accept-Encoding',
                           'content-type' => 'text/plain'
                         })

      buf = ''.dup
      raw_bytes = 0
      body.each do |part|
        raw_bytes += part.bytesize
        buf << inflater.inflate(part)
      end
      buf.must_equal content
      raw_bytes.must_be(:<, content.bytesize)
    end
  end

  it 'does not close the response body prematurely' do
    app_body = Class.new do
      attr_reader :closed;
      def each; yield('foo'); yield('bar'); end;
      def close; @closed = true; end;
    end.new

    verify(200, 'foobar', br_encoding, { 'app_body' => app_body }) do |status, headers, body|
      assert_nil app_body.closed
    end
  end
end
