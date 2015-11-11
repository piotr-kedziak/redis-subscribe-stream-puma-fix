module Headers::Credential
  extend ActiveSupport::Concern

  protected
    def add_allow_credentials_headers
      # https://developer.mozilla.org/en-US/docs/Web/HTTP/Access_control_CORS#section_5
      #
      # Because we want our front-end to send cookies to allow the API to be authenticated
      # (using 'withCredentials' in the XMLHttpRequest), we need to add some headers so
      # the browser will not reject the response
      response.headers['Access-Control-Allow-Origin'] = request.headers['Origin'] || '*'
      response.headers['Access-Control-Allow-Credentials'] = 'true'
    end

    def options
      head status: 200, :'Access-Control-Allow-Headers' => 'accept, content-type'
    end
  # protected
end
