class MsFabric
  # Acquires Entra bearer tokens for a target resource (audience). Service principal
  # (client-credentials) or App Service managed identity — managed identity is used when no
  # client_id/secret were given and an identity endpoint is present.
  class Auth
    def initialize(client_id: nil, client_secret: nil, tenant_id: nil,
                   identity_endpoint: nil, identity_header: nil)
      @client_id = client_id
      @client_secret = client_secret
      @tenant_id = tenant_id
      @identity_endpoint = identity_endpoint
      @identity_header = identity_header
      @cache = {}
    end

    # Bearer token for a resource, cached until 5 min before expiry.
    def token(resource)
      hit = @cache[resource]
      return hit[:value] if hit && Time.now < hit[:expires_at] - 300

      body = service_principal? ? request_sp(resource) : request_msi(resource)
      @cache[resource] = { value: body.fetch("access_token"),
                           expires_at: Time.now + body.fetch("expires_in", 3599).to_i }
      @cache[resource][:value]
    end

    def service_principal? = !@client_id.nil? && !@client_secret.nil?

    private

    def request_sp(resource)
      uri = URI("https://login.microsoftonline.com/#{@tenant_id}/oauth2/v2.0/token")
      req = Net::HTTP::Post.new(uri)
      req.set_form_data(grant_type: "client_credentials", client_id: @client_id,
                        client_secret: @client_secret, scope: "#{resource}/.default")
      send_request(uri, req)
    end

    def request_msi(resource)
      endpoint = @identity_endpoint || ENV["IDENTITY_ENDPOINT"]
      header = @identity_header || ENV["IDENTITY_HEADER"]
      raise AuthError, "no credentials: pass client_id/client_secret/tenant_id, or run where a " \
                       "managed identity endpoint is available" unless endpoint

      uri = URI("#{endpoint}?resource=#{resource}&api-version=2019-08-01")
      req = Net::HTTP::Get.new(uri)
      req["X-IDENTITY-HEADER"] = header
      send_request(uri, req)
    end

    def send_request(uri, req)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      raise AuthError, "token request failed (#{res.code}): #{res.body.to_s[0, 300]}" unless res.code.to_i == 200

      JSON.parse(res.body)
    end
  end
end
