class Api::V1::FoafController < Api::V1::ApiController
  # Authenticated endpoints for end-user FOAF reads. Inherits authenticate!
  # from ApiController so calls are scoped to current_user — unlike the
  # unauthenticated DebugController endpoints which are dev/test only.

  before_action :load_trustline, only: [:show_trustline, :trustline_events]

  # GET /v1/foaf/trustlines
  # Bulk reconcile for all of current_user's trustlines.
  # Same shape as the (admin-only) bulk debug reconcile, but scoped.
  def index
    unless Foaf::Config.foaf_write_enabled?
      return render json: { error: "FOAF publishing is not enabled" }, status: 400
    end

    tls = Trustline.where(is_active: true)
      .where("user_a_id = :id OR user_b_id = :id", id: current_user.id)
    rows = tls.map { |tl| Foaf::AuditService.reconcile_trustline(tl) }

    render json: {
      summary: {
        total: rows.size,
        matches: rows.count { |r| r[:match] == true },
        discrepancies: rows.count { |r| r[:match] == false },
        unlinked: rows.count { |r| r[:match].nil? },
      },
      trustlines: rows,
    }
  end

  # GET /v1/foaf/trustlines/:id
  # Per-trustline reconcile data (app-side vs FOAF-side comparison).
  def show_trustline
    unless Foaf::Config.foaf_write_enabled?
      return render json: { error: "FOAF publishing is not enabled" }, status: 400
    end

    render json: Foaf::AuditService.reconcile_trustline(@trustline)
  end

  # GET /v1/foaf/trustlines/:id/events
  # FOAF event log for this trustline (audit ledger row shape).
  def trustline_events
    unless Foaf::Config.foaf_write_enabled?
      return render json: { error: "FOAF publishing is not enabled" }, status: 400
    end

    render json: Foaf::AuditService.events_for_trustline(@trustline, viewer: current_user)
  end

  private

  def load_trustline
    @trustline = Trustline.find(params[:id])
    unless @trustline.user_a_id == current_user.id || @trustline.user_b_id == current_user.id
      render json: { error: "You don't have access to this trustline" }, status: :forbidden
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Trustline not found" }, status: :not_found
  end
end
