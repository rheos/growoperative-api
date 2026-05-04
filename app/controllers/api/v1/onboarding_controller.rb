class Api::V1::OnboardingController < Api::V1::ApiController
  # Job 11: master plan §1 / §Atomic accept/onboarding recovery.
  # `POST /v1/onboarding` and `GET /v1/onboarding/status` are the v1
  # contract for app-side onboarding. Phase 3 will move auth invitation
  # acceptance to auth.foaf.io; this controller stays as the
  # Growoperative-side adapter.

  # POST /v1/onboarding
  # Body: { invitation_code, user_type? }
  # Returns the v1 envelope ({ token, identity }) on success, with a
  # top-level `onboarding` block describing the terminal status.
  def create
    code = params[:invitation_code] || params[:invited_code] || params.dig(:onboarding, :invitation_code)
    if code.blank?
      render json: { error: 'invitation_code is required' }, status: :bad_request
      return
    end

    result = OnboardingService.new(
      user: current_user,
      invitation_code: code,
      requested_user_type: params[:user_type] || params.dig(:onboarding, :user_type),
    ).call

    render_result(result)
  end

  # GET /v1/onboarding/status?invitation_code=…
  # The pollable form of the same data — used by the saga's
  # session-restore path when an onboarding is mid-flight.
  def status
    code = params[:invitation_code] || params[:invited_code]
    invitation = Invitation.find_by(invitation_code: code) if code.present?

    if invitation.nil?
      render json: { error: 'invitation_not_found' }, status: :not_found
      return
    end

    render json: status_payload(invitation), status: :ok
  end

  private

  def render_result(result)
    case result.status
    when 'completed'
      render json: UserSerializer.new(result.user).serializable_hash.merge(
        token: JwtGenerationService.new(result.user).token,
        identity: identity_payload(result.user),
        onboarding: status_payload(result.invitation),
      ), status: :ok
    when 'rejected'
      # Terminal: 422 + structured rejection_code so UI can show the
      # right "couldn't accept your invite" surface and NOT auto-retry.
      render json: {
        error: result.error_message || 'onboarding_rejected',
        onboarding: status_payload(result.invitation),
      }, status: :unprocessable_entity
    when 'failed'
      # Retryable: 500 so the saga's retry policy fires. `failed` state
      # is recorded so subsequent GET /v1/onboarding/status reflects it.
      render json: {
        error: result.error_message || 'onboarding_failed',
        onboarding: result.invitation ? status_payload(result.invitation) : nil,
      }, status: :internal_server_error
    else
      render json: {
        error: result.error_message || 'onboarding_pending',
        onboarding: result.invitation ? status_payload(result.invitation) : nil,
      }, status: :accepted
    end
  end

  def status_payload(invitation)
    {
      invitation_code: invitation.invitation_code,
      app_onboarding_status: invitation.app_onboarding_status,
      app_onboarding_rejection_code: invitation.app_onboarding_rejection_code,
      app_onboarding_completed_at: invitation.app_onboarding_completed_at&.iso8601,
      target_app: 'growoperative',
    }
  end
end
