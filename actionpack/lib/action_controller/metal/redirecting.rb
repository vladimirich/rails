module ActionController
  class RedirectBackError < AbstractController::Error #:nodoc:
    DEFAULT_MESSAGE = 'No HTTP_REFERER was set in the request to this action, so redirect_to :back could not be called successfully. If this is a test, make sure to specify request.env["HTTP_REFERER"].'

    def initialize(message = nil)
      super(message || DEFAULT_MESSAGE)
    end
  end

  module Redirecting
    extend ActiveSupport::Concern

    include AbstractController::Logger
    include ActionController::UrlFor

    # Redirects the browser to the target specified in +options+. This parameter can be any one of:
    #
    # * <tt>Hash</tt> - The URL will be generated by calling url_for with the +options+.
    # * <tt>Record</tt> - The URL will be generated by calling url_for with the +options+, which will reference a named URL for that record.
    # * <tt>String</tt> starting with <tt>protocol://</tt> (like <tt>http://</tt>) or a protocol relative reference (like <tt>//</tt>) - Is passed straight through as the target for redirection.
    # * <tt>String</tt> not containing a protocol - The current protocol and host is prepended to the string.
    # * <tt>Proc</tt> - A block that will be executed in the controller's context. Should return any option accepted by +redirect_to+.
    #
    # === Examples:
    #
    #   redirect_to action: "show", id: 5
    #   redirect_to post
    #   redirect_to "http://www.rubyonrails.org"
    #   redirect_to "/images/screenshot.jpg"
    #   redirect_to articles_url
    #   redirect_to proc { edit_post_url(@post) }
    #
    # The redirection happens as a "302 Found" header unless otherwise specified using the <tt>:status</tt> option:
    #
    #   redirect_to post_url(@post), status: :found
    #   redirect_to action: 'atom', status: :moved_permanently
    #   redirect_to post_url(@post), status: 301
    #   redirect_to action: 'atom', status: 302
    #
    # The status code can either be a standard {HTTP Status code}[http://www.iana.org/assignments/http-status-codes] as an
    # integer, or a symbol representing the downcased, underscored and symbolized description.
    # Note that the status code must be a 3xx HTTP code, or redirection will not occur.
    #
    # If you are using XHR requests other than GET or POST and redirecting after the
    # request then some browsers will follow the redirect using the original request
    # method. This may lead to undesirable behavior such as a double DELETE. To work
    # around this  you can return a <tt>303 See Other</tt> status code which will be
    # followed using a GET request.
    #
    #   redirect_to posts_url, status: :see_other
    #   redirect_to action: 'index', status: 303
    #
    # It is also possible to assign a flash message as part of the redirection. There are two special accessors for the commonly used flash names
    # +alert+ and +notice+ as well as a general purpose +flash+ bucket.
    #
    #   redirect_to post_url(@post), alert: "Watch it, mister!"
    #   redirect_to post_url(@post), status: :found, notice: "Pay attention to the road"
    #   redirect_to post_url(@post), status: 301, flash: { updated_post_id: @post.id }
    #   redirect_to({ action: 'atom' }, alert: "Something serious happened")
    #
    def redirect_to(options = {}, response_status = {}) #:doc:
      raise ActionControllerError.new("Cannot redirect to nil!") unless options
      raise ActionControllerError.new("Cannot redirect to a parameter hash!") if options.is_a?(ActionController::Parameters)
      raise AbstractController::DoubleRenderError if response_body

      self.status        = _extract_redirect_to_status(options, response_status)
      self.location      = _compute_redirect_to_location(request, options)
      self.response_body = "<html><body>You are being <a href=\"#{ERB::Util.unwrapped_html_escape(location)}\">redirected</a>.</body></html>"
    end

    # Redirects the browser to the page that issued the request if possible,
    # otherwise redirects to provided default fallback location.
    #
    #   redirect_back fallback_location: { action: "show", id: 5 }
    #   redirect_back fallback_location: post
    #   redirect_back fallback_location: "http://www.rubyonrails.org"
    #   redirect_back fallback_location:  "/images/screenshot.jpg"
    #   redirect_back fallback_location:  articles_url
    #   redirect_back fallback_location:  proc { edit_post_url(@post) }
    #
    # All options that can be passed to <tt>redirect_to</tt> are accepted as
    # options and the behavior is indetical.
    def redirect_back(fallback_location:, **args)
      if referer = request.headers["Referer"]
        redirect_to referer, **args
      else
        redirect_to fallback_location, **args
      end
    end

    def _compute_redirect_to_location(request, options) #:nodoc:
      case options
      # The scheme name consist of a letter followed by any combination of
      # letters, digits, and the plus ("+"), period ("."), or hyphen ("-")
      # characters; and is terminated by a colon (":").
      # See http://tools.ietf.org/html/rfc3986#section-3.1
      # The protocol relative scheme starts with a double slash "//".
      when /\A([a-z][a-z\d\-+\.]*:|\/\/).*/i
        options
      when String
        request.protocol + request.host_with_port + options
      when :back
        ActiveSupport::Deprecation.warn(<<-MESSAGE.squish)
          `redirect_to :back` is deprecated and will be removed from Rails 5.1.
          Please use `redirect_back(fallback_location: fallback_location)` where
          `fallback_location` represents the location to use if the request has
          no HTTP referer information.
        MESSAGE
        request.headers["Referer"] or raise RedirectBackError
      when Proc
        _compute_redirect_to_location request, options.call
      else
        url_for(options)
      end.delete("\0\r\n")
    end
    module_function :_compute_redirect_to_location
    public :_compute_redirect_to_location

    private
      def _extract_redirect_to_status(options, response_status)
        if options.is_a?(Hash) && options.key?(:status)
          Rack::Utils.status_code(options.delete(:status))
        elsif response_status.key?(:status)
          Rack::Utils.status_code(response_status[:status])
        else
          302
        end
      end
  end
end
