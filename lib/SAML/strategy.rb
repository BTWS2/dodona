require 'omniauth'
require_relative 'attributes.rb'
require_relative 'settings.rb'

# Original at:
# https://github.com/omniauth/omniauth-saml/blob/master/lib/omniauth/strategies/saml.rb

module OmniAuth
  module Strategies
    class SAML
      include OmniAuth::Strategy

      def self.inherited(subclass)
        OmniAuth::Strategy.included(subclass)
      end

      # User requests to sign in with SAML.
      def request_phase
        # Build a new request.
        saml_auth_request = OneLogin::RubySaml::Authrequest.new

        # Amend the settings.
        with_settings do |settings|
          # Redirect the user to the federated sign-in page.
          redirect saml_auth_request.create(settings)
        end
      rescue RuntimeError
        fail!(:invalid_response, $!)
      end

      # User has signed in at IDP and is returned to Dodona.
      def callback_phase
        raw_response = request.params.symbolize_keys[:SAMLResponse]
        raise OneLogin::RubySaml::ValidationError.new("SAML response missing") unless raw_response

        with_settings do |settings|
          # Handle the response.
          handle_response(raw_response, settings) do
            # yield the response to the omniauth controller.
            super
          end
        end
      rescue OneLogin::RubySaml::ValidationError
        fail!(:invalid_response, $!)
      end

      # Configure the information hash.
      info do
        # Map the raw attributes to the civilised names.
        OmniAuth::Strategies::SAML::Attributes.resolve(@attributes)
      end

      # Configure the uid.
      uid do
        info['username'] || @name_id
      end

      extra { {provider_id: @provider&.id} }

      def on_callback_path?
        # Intercept requests sent to /users/saml/auth and forward those to the
        # callback.
        super || current_path == '/users/saml/auth'
      end

      private

      def handle_response(raw, settings)
        # Parse the raw response.
        opts = response_options.merge(settings: settings)
        parsed_response = OneLogin::RubySaml::Response.new(raw, opts)
        parsed_response.soft = false

        # Find the provider
        @provider = find_provider(parsed_response)
        prov_settings = OmniAuth::Strategies::SAML::Settings.for_provider(@provider)
        parsed_response.settings.idp_cert = prov_settings[:idp_cert]

        # Validate the response.
        parsed_response.is_valid?

        # Set the attributes.
        @name_id = parsed_response.name_id
        @session_index = parsed_response.sessionindex
        @attributes = parsed_response.attributes
        @saml_response = parsed_response

        # Return to the omniauth controller.
        yield
      end

      def find_provider(response)
        # Consider the issuer as the entity id.
        Provider.find_by(entity_id: response.issuers.first)
      end

      def response_options
        opts = options.select { |k, _| OneLogin::RubySaml::Response::AVAILABLE_OPTIONS.include?(k.to_sym) }
        opts.inject({}) do |nh, (k, v)|
          nh[k.to_sym] = v
          nh
        end
        opts
      end

      def with_settings
        yield OneLogin::RubySaml::Settings.new options
      end
    end
  end
end

OmniAuth.config.add_camelization 'saml', 'SAML'
