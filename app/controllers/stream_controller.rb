class StreamController < ApplicationController
  include ActionController::Live
  include Headers::Credential
  include Headers::Stream

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token

  before_action :set_headers_stream
  before_action :add_allow_credentials_headers

  protected
    def redis
      @redis ||= Redis.new
    end
  # protected
end
