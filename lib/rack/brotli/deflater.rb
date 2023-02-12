require "brotli"
require 'rack/utils'

module Rack::Brotli
  # This middleware enables compression of http responses.
  #
  # Currently supported compression algorithms:
  #
  #   * br
  #
  # The middleware automatically detects when compression is supported
  # and allowed. For example no transformation is made when a cache
  # directive of 'no-transform' is present, or when the response status
  # code is one that doesn't allow an entity body.
  class Deflater
    ##
    # Creates Rack::Brotli middleware.
    #
    # [app] rack app instance
    # [options] hash of deflater options, i.e.
    #           'if' - a lambda enabling / disabling deflation based on returned boolean value
    #                  e.g use Rack::Brotli, :if => lambda { |env, status, headers, body| body.map(&:bytesize).reduce(0, :+) > 512 }
    #           'include' - a list of content types that should be compressed
    #           'deflater' - Brotli compression options
    def initialize(app, options = {})
      @app = app

      @condition = options[:if]
      @compressible_types = options[:include]
      @deflater_options = { quality: 5 }.merge(options[:deflater] || {})
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers = Rack::Headers.new(headers)

      unless should_deflate?(env, status, headers, body)
        return [status, headers, body]
      end

      request = Rack::Request.new(env)

      encoding = Rack::Utils.select_best_encoding(%w(br),
                                            request.accept_encoding)

      return [status, headers, body] unless encoding

      # Set the Vary HTTP header.
      vary = headers["Vary"].to_s.split(",").map(&:strip)
      unless vary.include?("*") || vary.include?("Accept-Encoding")
        headers["Vary"] = vary.push("Accept-Encoding").join(",")
      end

      case encoding
      when "br"
        headers['Content-Encoding'] = "br"
        headers.delete(Rack::CONTENT_LENGTH)
        [status, headers, BrotliStream.new(body, @deflater_options)]
      when nil
        message = "An acceptable encoding for the requested resource #{request.fullpath} could not be found."
        bp = Rack::BodyProxy.new([message]) { body.close if body.respond_to?(:close) }
        [406, {Rack::CONTENT_TYPE => "text/plain", Rack::CONTENT_LENGTH => message.length.to_s}, bp]
      end
    end

    class BrotliStream
      include Rack::Utils

      def initialize(body, options)
        @body = body
        @options = options
      end

      def each(&block)
        @writer = block
        # Use String.new instead of '' to support environments with strings frozen by default.
        buffer = String.new
        @body.each { |part|
          buffer << part
        }
        yield ::Brotli.deflate(buffer, @options)
      ensure
        @writer = nil
      end

      def close
        @body.close if @body.respond_to?(:close)
      end
    end
    
    private

    def should_deflate?(env, status, headers, body)
      # Skip compressing empty entity body responses and responses with
      # no-transform set.
      if Rack::Utils::STATUS_WITH_NO_ENTITY_BODY.include?(status) ||
          headers[Rack::CACHE_CONTROL].to_s =~ /\bno-transform\b/ ||
         (headers['Content-Encoding'] && headers['Content-Encoding'] !~ /\bidentity\b/)
        return false
      end

      # Skip if @compressible_types are given and does not include request's content type
      return false if @compressible_types && !(headers.has_key?(Rack::CONTENT_TYPE) && @compressible_types.include?(headers[Rack::CONTENT_TYPE][/[^;]*/]))

      # Skip if @condition lambda is given and evaluates to false
      return false if @condition && !@condition.call(env, status, headers, body)

      true
    end
  end
end
