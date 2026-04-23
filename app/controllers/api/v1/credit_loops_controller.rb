class Api::V1::CreditLoopsController < Api::V1::ApiController
  # Superuser-only forensic view of credit-loop cancellations. Backed by the
  # in-app CreditLoopAnalyzer, which pulls raw FOAF state and does all
  # reconstruction locally. FOAF itself remains analytics-agnostic.

  before_action :require_superuser!

  # GET /v1/admin/credit_loops?limit=
  def index
    unless Foaf::Config.shadow_mode?
      return render json: { error: "FOAF shadow mode is not enabled" }, status: 400
    end

    limit = [params.fetch(:limit, 20).to_i, 1].max
    render json: { credloops: CreditLoopAnalyzer.list(limit: limit) }
  end

  # GET /v1/admin/credit_loops/:id
  def show
    unless Foaf::Config.shadow_mode?
      return render json: { error: "FOAF shadow mode is not enabled" }, status: 400
    end

    render json: CreditLoopAnalyzer.detail(params[:id])
  rescue RuntimeError => e
    render json: { error: e.message }, status: :not_found
  end

  private

  def require_superuser!
    return if current_user&.is_superuser?
    render json: { error: "Superuser access required" }, status: 403
  end
end
