# Liveness that actually proves the database is reachable.
#
# The existing "/up" route is a hardcoded proc returning 200 OK, so it answers
# happily while Postgres is gone. auth.foaf.io had the same shape: a health
# action rendering a static hash. That is how a three-day outage
# (2026-09-19 to 2026-09-22) went unnoticed — every external check looked green
# the whole time, and the only real signal was a backup job failing, unwatched.
#
# So this endpoint does the one thing those did not: it talks to the database.
# Unauthenticated on purpose, because a monitor cannot hold a token, and it
# returns no data beyond up or down.
class Api::V1::HealthController < Api::V1::ApiController
  skip_before_action :authenticate!

  def show
    ActiveRecord::Base.connection.select_value('SELECT 1')

    render json: {
      status: 'ok',
      service: 'api.growoperative.app',
      database: 'ok'
    }, status: :ok
  rescue StandardError => e
    # 503 rather than 500: this is "dependency unavailable", and it is the
    # signal a monitor pages on. The class name is enough to tell a connection
    # failure from a timeout without putting connection details in a public
    # response body.
    Rails.logger.error("[health] database unreachable: #{e.class}: #{e.message}")

    render json: {
      status: 'error',
      service: 'api.growoperative.app',
      database: 'unreachable',
      error: e.class.name
    }, status: :service_unavailable
  end
end
