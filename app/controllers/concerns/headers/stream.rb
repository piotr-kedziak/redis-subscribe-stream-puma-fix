module Headers::Stream
  extend ActiveSupport::Concern

  protected
    def set_headers_stream
      response.headers["Content-Type"] = "text/event-stream"
    end
  # protected
end
