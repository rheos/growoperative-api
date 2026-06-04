module Api::V1
  # Job 49 — railsbackend proxy for foaf-auth's /v1/oauth/* endpoints.
  # The app talks to railsbackend for everything; this forwards OAuth
  # calls verbatim to auth.foaf.io / dauth.foaf.io. Same pattern as
  # SessionsController#create proxying /v1/sessions to auth.foaf.io.
  #
  # Bearer token (when present) passes through so the Bearer-authed
  # endpoints (GET /v1/oauth/links, DELETE /v1/oauth/links/:provider)
  # work — auth.foaf.io verifies it against its own JWKS.
  class OAuthProxyController < ApiController
    skip_before_action :authenticate!

    def providers
      forward_get('/v1/oauth/providers')
    end

    def start
      forward_post("/v1/oauth/#{params[:provider]}/start", json_body)
    end

    def callback
      forward_post("/v1/oauth/#{params[:provider]}/callback", json_body)
    end

    def apple_native
      forward_post('/v1/oauth/apple/native', json_body)
    end

    def links_index
      forward_get('/v1/oauth/links', bearer: bearer_token)
    end

    def links_complete
      forward_post('/v1/oauth/links/complete', json_body)
    end

    def links_destroy
      forward_delete("/v1/oauth/links/#{params[:provider]}", bearer: bearer_token)
    end

    private

    def json_body
      params.except(:controller, :action, :provider).to_unsafe_h
    end

    def bearer_token
      request.headers['Authorization'].to_s.sub(/\ABearer\s+/, '').presence
    end

    def forward_get(path, bearer: nil)
      status, body = AuthFoafClient.new.get_json(path, bearer: bearer)
      render_downstream(status, body)
    end

    def forward_post(path, body_hash)
      status, body = AuthFoafClient.new.post_json(path, body_hash, bearer: bearer_token)
      render_downstream(status, body)
    end

    def forward_delete(path, bearer:)
      # Net::HTTP::Delete works through request_json too — re-use it
      # through a thin shim. AuthFoafClient doesn't expose a delete_json
      # helper today, so we drop down to request_json directly.
      client = AuthFoafClient.new
      uri = URI.join(AuthFoafClient.base_url, path)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      req = Net::HTTP::Delete.new(uri.request_uri)
      req['Accept'] = 'application/json'
      req['Authorization'] = "Bearer #{bearer}" if bearer
      res = http.request(req)
      parsed = res.body.present? ? (JSON.parse(res.body) rescue { 'raw' => res.body }) : {}
      render_downstream(Integer(res.code), parsed)
    end

    def render_downstream(status, body)
      if status == 204
        head :no_content
      else
        render json: body, status: status
      end
    end
  end
end
