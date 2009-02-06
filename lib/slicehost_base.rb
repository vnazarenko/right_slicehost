
module Rightscale

  class SlicehostBenchmarkingBlock #:nodoc:
    attr_accessor :parser, :service
    def initialize
      # Benchmark::Tms instance for service (Ec2, S3, or SQS) access benchmarking.
      @service = Benchmark::Tms.new()
      # Benchmark::Tms instance for parsing benchmarking.
      @parser = Benchmark::Tms.new()
    end
  end

  class SlicehostNoChange < RuntimeError
  end

  module RightSlicehostInterface
    DEFAULT_SLICEHOST_URL = 'https://api.slicehost.com'

    # Text, if found in an error message returned by Slicehost, indicates that this may be a transient
    # error. Transient errors are automatically retried with exponential back-off.
    # TODO: gather Slicehost errors here
    SLICEHOST_PROBLEMS = [ ]
    @@slicehost_problems = SLICEHOST_PROBLEMS
      # Returns a list of Slicehost responses which are known to be transient problems.
      # We have to re-request if we get any of them, because the problem will probably disappear.
      # By default this method returns the same value as the SLICEHOST_PROBLEMS const.
    def self.slicehost_problems
      @@slicehost_problems
    end

    @@caching = false
    def self.caching
      @@caching
    end
    def self.caching=(caching)
      @@caching = caching
    end

    @@bench = SlicehostBenchmarkingBlock.new
    def self.bench_parser
      @@bench.parser
    end
    def self.bench_slicehost
      @@bench.service
    end

      # Current Slicehost API key
    attr_reader :slicehost_pasword
      # Last HTTP request object
    attr_reader :last_request
      # Last HTTP response object
    attr_reader :last_response
      # Last Slicehost errors list (used by SlicehostErrorHandler)
    attr_accessor :last_errors
      # Logger object
    attr_accessor :logger
      # Initial params hash
    attr_accessor :params
      # RightHttpConnection instance
    attr_reader :connection
      # Cache
    attr_reader :cache


    #
    # Params:
    #   :slicehost_url
    #   :logger
    #   :multi_thread
    #
    def init(slicehost_pasword, params={}) #:nodoc:
      @params = params
      @cache  = {}
      @error_handler = nil
      # deny working without credentials
      if slicehost_pasword.blank?
        raise SlicehostError.new("Slicehost password is required to operate on Slicehost API service")
      end
      @slicehost_pasword = slicehost_pasword
      # parse Slicehost URL
      @params[:slicehost_url] ||= ENV['SLICEHOST_URL'] || DEFAULT_SLICEHOST_URL
      @params[:server]       = URI.parse(@params[:slicehost_url]).host
      @params[:port]         = URI.parse(@params[:slicehost_url]).port
      @params[:service]      = URI.parse(@params[:slicehost_url]).path
      @params[:protocol]     = URI.parse(@params[:slicehost_url]).scheme
      # other params
      @params[:multi_thread] ||= defined?(SLICEHOST_DAEMON)
      @logger = @params[:logger] || (defined?(RAILS_DEFAULT_LOGGER) && RAILS_DEFAULT_LOGGER) || Logger.new(STDOUT)
      @logger.info "New #{self.class.name} using #{@params[:multi_thread] ? 'multi' : 'single'}-threaded mode"
    end

    def on_exception(options={:raise=>true, :log=>true}) # :nodoc:
      raise if $!.is_a?(SlicehostNoChange)
      SlicehostError::on_slicehost_exception(self, options)
    end

    # --------
    # Helpers
    # --------

    # Return +true+ if this instance works in multi_thread mode and +false+ otherwise.
    def multi_thread
      @params[:multi_thread]
    end

    def cgi_escape_params(params) # :nodoc:
      params.map {|k,v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&")
    end

    # ----------------------------------
    # request generation and processing
    # ----------------------------------

    # Generate a handy request hash.
    def generate_request(method, path, params={}) # :nodoc:
      # default request params
      params = cgi_escape_params(params)

      request_url = "#{@params[:service]}/#{path}"
      request_url << "?#{params}" unless params.blank?

      request = method.new(request_url)
      case method.name[/([^:]*)$/] && $1
      when 'Post'
        request['Accept']       = '*/*'
        request['Content-Type'] = 'application/xml'
      when 'Put'
        request['Accept']       = '*/*'
        request['Content-Type'] = 'application/xml'
      else
        request['Accept']  = 'application/xml'
      end

      request.basic_auth(@slicehost_pasword,'')

      { :request  => request,
        :server   => @params[:server],
        :port     => @params[:port],
        :protocol => @params[:protocol] }
    end

    # Perform a request.
    # (4xx and 5xx error handling is being made through SlicehostErrorHandler)
    def request_info(request, parser)  #:nodoc:
      # check single/multi threading mode
      thread = @params[:multi_thread] ? Thread.current : Thread.main
      # create a connection if needed
      thread[:ec2_connection] ||= Rightscale::HttpConnection.new(:exception => SlicehostError, :logger => @logger)
      @connection    = thread[:ec2_connection]
      @last_request  = request[:request]
      @last_response = nil
      # perform a request
      @@bench.service.add!{ @last_response = @connection.request(request) }
      # check response for success...
      if @last_response.is_a?(Net::HTTPSuccess)
        @error_handler = nil
        @@bench.parser.add! { parser.parse(@last_response) }
        return parser.result
      else
        @error_handler ||= SlicehostErrorHandler.new(self, parser, :errors_list => @@slicehost_problems)
        check_result     = @error_handler.check(request)
        if check_result
          @error_handler = nil
          return check_result
        end
        raise SlicehostError.new(@last_errors, @last_response.code)
      end
    rescue
      @error_handler = nil
      raise
    end

    # --------
    # Caching
    # --------

    # Perform a request.
    # Skips a response parsing if caching is used.
    def request_cache_or_info(method, request_hash, parser_class, use_cache=true) #:nodoc:
      # We do not want to break the logic of parsing hence will use a dummy parser to process all the standard
      # steps (errors checking etc). The dummy parser does nothig - just returns back the params it received.
      # If the caching is enabled and hit then throw  SlicehostNoChange.
      # P.S. caching works for the whole images list only! (when the list param is blank)
      response = request_info(request_hash, SlicehostDummyParser.new)
      # check cache
      cache_hits?(method.to_sym, response.body) if use_cache
      parser = parser_class.new(:logger => @logger)
      @@bench.parser.add!{ parser.parse(response) }
      result = block_given? ? yield(parser) : parser.result
      # update parsed data
      update_cache(method.to_sym, :parsed => result) if use_cache
      result
    end

    # Returns +true+ if the describe_xxx responses are being cached
    def caching?
      @params.key?(:cache) ? @params[:cache] : @@caching
    end

    # Check if the slicehost function response hits the cache or not.
    # If the cache hits:
    # - raises an +SlicehostNoChange+ exception if +do_raise+ == +:raise+.
    # - returnes parsed response from the cache if it exists or +true+ otherwise.
    # If the cache miss or the caching is off then returns +false+.
    def cache_hits?(function, response, do_raise=:raise) # :nodoc:
      result = false
      if caching?
        function     = function.to_sym
        response_md5 = MD5.md5(response).to_s
        # well, the response is new, reset cache data
        unless @cache[function] && @cache[function][:response_md5] == response_md5
          update_cache(function, {:response_md5 => response_md5,
                                  :timestamp    => Time.now,
                                  :hits         => 0,
                                  :parsed       => nil})
        else
          # aha, cache hits, update the data and throw an exception if needed
          @cache[function][:hits] += 1
          if do_raise == :raise
            raise(SlicehostNoChange, "Cache hit: #{function} response has not changed since "+
                                  "#{@cache[function][:timestamp].strftime('%Y-%m-%d %H:%M:%S')}, "+
                                  "hits: #{@cache[function][:hits]}.")
          else
            result = @cache[function][:parsed] || true
          end
        end
      end
      result
    end

    def update_cache(function, hash) # :nodoc:
      (@cache[function.to_sym] ||= {}).merge!(hash) if caching?
    end
  end


  # Exception class to signal any Amazon errors. All errors occuring during calls to Amazon's
  # web services raise this type of error.
  # Attribute inherited by RuntimeError:
  #  message    - the text of the error
  class SlicehostError < RuntimeError # :nodoc:

    # either an array of errors where each item is itself an array of [code, message]),
    # or an error string if the error was raised manually, as in <tt>SlicehostError.new('err_text')</tt>
    attr_reader :errors

    # Response HTTP error code
    attr_reader :http_code

    def initialize(errors=nil, http_code=nil)
      @errors      = errors
      @http_code   = http_code
      super(@errors.is_a?(Array) ? @errors.map{|code, msg| "#{code}: #{msg}"}.join("; ") : @errors.to_s)
    end

    # Does any of the error messages include the regexp +pattern+?
    # Used to determine whether to retry request.
    def include?(pattern)
      if @errors.is_a?(Array)
        @errors.each{ |code, msg| return true if code =~ pattern }
      else
        return true if @errors_str =~ pattern
      end
      false
    end

    # Generic handler for SlicehostErrors.
    # object that caused the exception (it must provide last_request and last_response). Supported
    # boolean options are:
    # * <tt>:log</tt> print a message into the log using slicehost.logger to access the Logger
    # * <tt>:puts</tt> do a "puts" of the error
    # * <tt>:raise</tt> re-raise the error after logging
    def self.on_slicehost_exception(slicehost, options={:raise=>true, :log=>true})
 	    # Only log & notify if not user error
      if !options[:raise] || system_error?($!)
        error_text = "#{$!.inspect}\n#{$@}.join('\n')}"
        puts error_text if options[:puts]
          # Log the error
        if options[:log]
          request  = slicehost.last_request  ? slicehost.last_request.path :  '-none-'
          response = slicehost.last_response ? "#{slicehost.last_response.code} -- #{slicehost.last_response.message} -- #{slicehost.last_response.body}" : '-none-'
          slicehost.logger.error error_text
          slicehost.logger.error "Request was:  #{request}"
          slicehost.logger.error "Response was: #{response}"
        end
      end
      raise if options[:raise]  # re-raise an exception
      return nil
    end

    # True if e is an AWS system error, i.e. something that is for sure not the caller's fault.
    # Used to force logging.
    # TODO: Place Slicehost Errors here
    def self.system_error?(e)
 	    !e.is_a?(self) || e.message =~ /InternalError|InsufficientInstanceCapacity|Unavailable/
    end

  end

  class SlicehostErrorHandler # :nodoc:
    # 0-100 (%)
    DEFAULT_CLOSE_ON_4XX_PROBABILITY = 10

    @@reiteration_start_delay = 0.2
    def self.reiteration_start_delay
      @@reiteration_start_delay
    end
    def self.reiteration_start_delay=(reiteration_start_delay)
      @@reiteration_start_delay = reiteration_start_delay
    end

    @@reiteration_time = 5
    def self.reiteration_time
      @@reiteration_time
    end
    def self.reiteration_time=(reiteration_time)
      @@reiteration_time = reiteration_time
    end

    @@close_on_error = true
    def self.close_on_error
      @@close_on_error
    end
    def self.close_on_error=(close_on_error)
      @@close_on_error = close_on_error
    end

    @@close_on_4xx_probability = DEFAULT_CLOSE_ON_4XX_PROBABILITY
    def self.close_on_4xx_probability
      @@close_on_4xx_probability
    end
    def self.close_on_4xx_probability=(close_on_4xx_probability)
      @@close_on_4xx_probability = close_on_4xx_probability
    end

    # params:
    #  :reiteration_time
    #  :errors_list
    #  :close_on_error           = true | false
    #  :close_on_4xx_probability = 1-100
    def initialize(slicehost, parser, params={}) #:nodoc:
      @slicehost     = slicehost
      @parser        = parser           # parser to parse a response
      @started_at    = Time.now
      @stop_at       = @started_at  + (params[:reiteration_time] || @@reiteration_time)
      @errors_list   = params[:errors_list] || []
      @reiteration_delay = @@reiteration_start_delay
      @retries       = 0
      # close current HTTP(S) connection on 5xx, errors from list and 4xx errors
      @close_on_error           = params[:close_on_error].nil? ? @@close_on_error : params[:close_on_error]
      @close_on_4xx_probability = params[:close_on_4xx_probability] || @@close_on_4xx_probability
    end

      # Returns false if
    def check(request)  #:nodoc:
      result           = false
      error_found      = false
      error_match      = nil
      last_errors_text = ''
      response         = @slicehost.last_response
      # log error
      request_text_data = "#{request[:server]}:#{request[:port]}#{request[:request].path}"
      @slicehost.logger.warn("##### #{@slicehost.class.name} returned an error: #{response.code} #{response.message}\n#{response.body} #####")
      @slicehost.logger.warn("##### #{@slicehost.class.name} request: #{request_text_data} ####")

      if response.body && response.body[/<\?xml/]
        error_parser = SliceErrorResponseParser.new
        error_parser.parse(response)
        @slicehost.last_errors = error_parser.errors.map{|e| [response.code, e]}
        last_errors_text = @slicehost.last_errors.flatten.join("\n")
      else
        @slicehost.last_errors = [[response.code, "#{response.message} (#{request_text_data})"]]
        last_errors_text       = response.message
      end

      # now - check the error
      @errors_list.each do |error_to_find|
        if last_errors_text[/#{error_to_find}/i]
          error_found = true
          error_match = error_to_find
          @slicehost.logger.warn("##### Retry is needed, error pattern match: #{error_to_find} #####")
          break
        end
      end
        # check the time has gone from the first error come
      if error_found
        # Close the connection to the server and recreate a new one.
        # It may have a chance that one server is a semi-down and reconnection
        # will help us to connect to the other server
        if @close_on_error
          @slicehost.connection.finish "#{self.class.name}: error match to pattern '#{error_match}'"
        end

        if (Time.now < @stop_at)
          @retries += 1

          @slicehost.logger.warn("##### Retry ##{@retries} is being performed. Sleeping for #{@reiteration_delay} sec. Whole time: #{Time.now-@started_at} sec ####")
          sleep @reiteration_delay
          @reiteration_delay *= 2

          # Always make sure that the fp is set to point to the beginning(?)
          # of the File/IO. TODO: it assumes that offset is 0, which is bad.
          if(request[:request].body_stream && request[:request].body_stream.respond_to?(:pos))
            begin
              request[:request].body_stream.pos = 0
            rescue Exception => e
              @logger.warn("Retry may fail due to unable to reset the file pointer" +
                           " -- #{self.class.name} : #{e.inspect}")
            end
          end
          result = @slicehost.request_info(request, @parser)
        else
          @slicehost.logger.warn("##### Ooops, time is over... ####")
        end
      # aha, this is unhandled error:
      elsif @close_on_error
        # Is this a 5xx error ?
        if @slicehost.last_response.code.to_s[/^5\d\d$/]
          @slicehost.connection.finish "#{self.class.name}: code: #{@slicehost.last_response.code}: '#{@slicehost.last_response.message}'"
        # Is this a 4xx error ?
        elsif @slicehost.last_response.code.to_s[/^4\d\d$/] && @close_on_4xx_probability > rand(100)
          @slicehost.connection.finish "#{self.class.name}: code: #{@slicehost.last_response.code}: '#{@slicehost.last_response.message}', " +
                                 "probability: #{@close_on_4xx_probability}%"
        end
      end
      result
    end
  end

  #-----------------------------------------------------------------

  class RightSaxParserCallback #:nodoc:
    def self.include_callback
      include XML::SaxParser::Callbacks
    end
    def initialize(right_aws_parser)
      @right_aws_parser = right_aws_parser
    end
    def on_start_element(name, attr_hash)
      @right_aws_parser.tag_start(name, attr_hash)
    end
    def on_characters(chars)
      @right_aws_parser.text(chars)
    end
    def on_end_element(name)
      @right_aws_parser.tag_end(name)
    end
    def on_start_document; end
    def on_comment(msg); end
    def on_processing_instruction(target, data); end
    def on_cdata_block(cdata); end
    def on_end_document; end
  end

  class RightSlicehostParser  #:nodoc:
      # default parsing library
    DEFAULT_XML_LIBRARY = 'rexml'
      # a list of supported parsers
    @@supported_xml_libs = [DEFAULT_XML_LIBRARY, 'libxml']

    @@xml_lib = DEFAULT_XML_LIBRARY # xml library name: 'rexml' | 'libxml'
    def self.xml_lib
      @@xml_lib
    end
    def self.xml_lib=(new_lib_name)
      @@xml_lib = new_lib_name
    end

    attr_accessor :result
    attr_reader   :xmlpath
    attr_accessor :xml_lib

    def initialize(params={})
      @xmlpath = ''
      @result  = false
      @text    = ''
      @xml_lib = params[:xml_lib] || @@xml_lib
      @logger  = params[:logger]
      reset
    end
    def tag_start(name, attributes)
      @text = ''
      tagstart(name, attributes)
      @xmlpath += @xmlpath.empty? ? name : "/#{name}"
    end
    def tag_end(name)
      @xmlpath[/^(.*?)\/?#{name}$/]
      @xmlpath = $1
      tagend(name)
    end
    def text(text)
      @text += text
      tagtext(text)
    end
      # Parser method.
      # Params:
      #   xml_text         - xml message text(String) or Net:HTTPxxx instance (response)
      #   params[:xml_lib] - library name: 'rexml' | 'libxml'
    def parse(xml_text, params={})
        # Get response body
      xml_text = xml_text.body unless xml_text.is_a?(String)
      @xml_lib = params[:xml_lib] || @xml_lib
        # check that we had no problems with this library otherwise use default
      @xml_lib = DEFAULT_XML_LIBRARY unless @@supported_xml_libs.include?(@xml_lib)
        # load xml library
      if @xml_lib=='libxml' && !defined?(XML::SaxParser)
        begin
          require 'xml/libxml'
          # is it new ? - Setup SaxParserCallback
          if XML::Parser::VERSION >= '0.5.1.0'
            RightSaxParserCallback.include_callback
          end
        rescue LoadError => e
          @@supported_xml_libs.delete(@xml_lib)
          @xml_lib = DEFAULT_XML_LIBRARY
          if @logger
            @logger.error e.inspect
            @logger.error e.backtrace
            @logger.info "Can not load 'libxml' library. '#{DEFAULT_XML_LIBRARY}' is used for parsing."
          end
        end
      end
        # Parse the xml text
      case @xml_lib
      when 'libxml'
        xml        = XML::SaxParser.new
        xml.string = xml_text
        # check libxml-ruby version
        if XML::Parser::VERSION >= '0.5.1.0'
          xml.callbacks = RightSaxParserCallback.new(self)
        else
          xml.on_start_element{|name, attr_hash| self.tag_start(name, attr_hash)}
          xml.on_characters{   |text|            self.text(text)}
          xml.on_end_element{  |name|            self.tag_end(name)}
        end
        xml.parse
      else
        REXML::Document.parse_stream(xml_text, self)
      end
    end
      # Parser must have a lots of methods
      # (see /usr/lib/ruby/1.8/rexml/parsers/streamparser.rb)
      # We dont need most of them in RightSlicehostParser and method_missing helps us
      # to skip their definition
    def method_missing(method, *params)
        # if the method is one of known - just skip it ...
      return if [:comment, :attlistdecl, :notationdecl, :elementdecl,
                 :entitydecl, :cdata, :xmldecl, :attlistdecl, :instruction,
                 :doctype].include?(method)
        # ... else - call super to raise an exception
      super(method, params)
    end
      # the functions to be overriden by children (if nessesery)
    def reset                     ; end
    def tagstart(name, attributes); end
    def tagend(name)              ; end
    def tagtext(text)             ; end
  end

  # Dummy parser - does nothing
  # Returns the original params back
  class SlicehostDummyParser  # :nodoc:
    attr_accessor :result
    def parse(response)
      @result = response
    end
  end

  class SliceErrorResponseParser < RightSlicehostParser #:nodoc:
    attr_accessor :errors  # array of hashes: error/message
    def tagend(name)
      case name
        when 'error' then @errors << @text
      end
    end
    def reset
      @errors = []
    end
  end
  
end
