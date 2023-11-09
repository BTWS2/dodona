require_relative '../../../lib/LTI/jwk'
require_relative '../../../lib/LTI/messages'

module SetLtiMessage
  extend ActiveSupport::Concern

  include LTI::JWK
  include LTI::Messages

  def set_lti_message
    @lti_message = parse_message(params[:id_token], params[:provider_id])
    @lti_launch = @lti_message.is_a?(LTI::Messages::Types::ResourceLaunchRequest)
    helpers.locale = @lti_message&.launch_presentation_locale if @lti_message&.launch_presentation_locale.present?
  rescue JSON::JWK::Set::KidNotFound => _e
    flash.now[:error] = t('layout.messages.kid')
  end

  def set_lti_provider
    @provider = Provider::Lti.find(params[:provider_id]) if params[:provider_id].present?
  end
end
