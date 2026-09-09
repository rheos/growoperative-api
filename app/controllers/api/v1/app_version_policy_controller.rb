class Api::V1::AppVersionPolicyController < Api::V1::ApiController
  skip_before_action :authenticate!, only: [:show]

  MIN_IOS_BUILD = 'MinimumIosBuildNumber'
  MIN_ANDROID_BUILD = 'MinimumAndroidVersionCode'
  UPDATE_MESSAGE = 'RequiredUpdateMessage'

  def show
    render json: policy_payload, status: :ok
  end

  def admin_show
    return render json: { message: 'You are not allowed' }, status: :unauthorized unless current_user.is_superuser?

    render json: policy_payload, status: :ok
  end

  def update
    return render json: { message: 'You are not allowed' }, status: :unauthorized unless current_user.is_superuser?

    set_integer(MIN_IOS_BUILD, params[:minimum_ios_build])
    set_integer(MIN_ANDROID_BUILD, params[:minimum_android_version_code])
    set_string(UPDATE_MESSAGE, params[:message])

    render json: policy_payload, status: :ok
  end

  private

  def policy_payload
    {
      minimum_ios_build: setting_int(MIN_IOS_BUILD),
      minimum_android_version_code: setting_int(MIN_ANDROID_BUILD),
      message: setting_string(UPDATE_MESSAGE).presence || default_message,
      ios_store_url: 'https://apps.apple.com/app/id6767721866',
      android_store_url: 'https://play.google.com/store/apps/details?id=io.growoperative.app'
    }
  end

  def setting_int(name)
    GlobalSetting.find_by(setting: name)&.value.to_i
  end

  def setting_string(name)
    GlobalSetting.find_by(setting: name)&.string_value.to_s
  end

  def set_integer(name, value)
    return if value.nil?

    setting = GlobalSetting.find_or_initialize_by(setting: name)
    setting.value = value.to_i
    setting.save!
  end

  def set_string(name, value)
    return if value.nil?

    setting = GlobalSetting.find_or_initialize_by(setting: name)
    setting.string_value = value.to_s
    setting.save!
  end

  def default_message
    'This version of GrowOperative is no longer compatible. Please update to continue.'
  end
end
