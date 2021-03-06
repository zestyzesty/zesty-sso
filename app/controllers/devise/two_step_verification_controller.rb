class Devise::TwoStepVerificationController < DeviseController
  before_filter :prepare_and_validate, except: [:prompt, :defer]
  skip_before_filter :handle_two_step_verification

  attr_reader :otp_secret_key
  private :otp_secret_key

  def prompt
  end

  def defer
    current_user.defer_two_step_verification
    redirect_to_prior_flow
  end

  def show
    generate_secret
  end

  def update
    mode = current_user.has_2sv? ? :change : :setup
    if verify_code_and_update
      EventLog.record_event(current_user, success_event_for(mode))
      redirect_to_prior_flow notice: I18n.t("devise.two_step_verification.messages.success.#{mode}")
    else
      EventLog.record_event(current_user, failure_event_for(mode))
      flash.now[:invalid_code] = "Sorry that code didn’t work. Please try again."
      render :show, status: :unprocessable_entity
    end
  end

  def otp_secret_key_uri
    issuer = "GOV.UK%20Signon"
    if Rails.application.config.instance_name
      issuer = "#{Rails.application.config.instance_name.titleize}%20#{issuer}"
    end
    "otpauth://totp/#{issuer}:#{current_user.email}?secret=#{@otp_secret_key.upcase}&issuer=#{issuer}"
  end

  private
  def qr_code_data_uri
    qr_code = RQRCode::QRCode.new(otp_secret_key_uri, level: :m)
    qr_code.as_png(size: 180, fill: ChunkyPNG::Color::TRANSPARENT).to_data_url
  end
  helper_method :qr_code_data_uri

  def prepare_and_validate
    redirect_to(:root) && return if current_user.nil?
    @limit = User::MAX_2SV_LOGIN_ATTEMPTS
    if current_user.max_2sv_login_attempts?
      sign_out(current_user)
      render(:max_2sv_login_attempts_reached) && return
    end
  end

  def generate_secret
    @otp_secret_key = ROTP::Base32.random_base32
  end

  def verify_code_and_update
    @otp_secret_key = params[:otp_secret_key]
    totp = ROTP::TOTP.new(@otp_secret_key)
    if totp.verify(params[:code])
      current_user.update_attribute(:otp_secret_key, @otp_secret_key)
      true
    else
      false
    end
  end

  def failure_event_for(mode)
    mode == :setup ? EventLog::TWO_STEP_ENABLE_FAILED : EventLog::TWO_STEP_CHANGE_FAILED
  end

  def success_event_for(mode)
    mode == :setup ? EventLog::TWO_STEP_ENABLED : EventLog::TWO_STEP_CHANGED
  end
end
