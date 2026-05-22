# frozen_string_literal: true

require 'omniauth'

module OmniAuth
  module Strategies
    # Minimal OmniAuth strategy for Nostr.
    #
    # The real verification has already happened in DiscourseNostr::AuthController
    # before this strategy is invoked. The controller stashes the verified
    # pubkey (and optional profile metadata) into the Rack session, then
    # redirects to `/auth/nostr/callback`, which lands here.
    #
    # This strategy's only job is to package that session payload as a standard
    # OmniAuth auth hash so Discourse's ManagedAuthenticator can do user
    # lookup / account linking like any other provider. It does NOT re-verify
    # the signature, because the session payload is server-trusted at this
    # point — re-verifying would just be a cache miss.
    class Nostr
      include OmniAuth::Strategy

      option :name, 'nostr'

      # No request phase UI — the widget posts to /auth/nostr/verify directly,
      # and that controller is what redirects into the callback phase.
      def request_phase
        redirect '/'
      end

      def callback_phase
        pubkey = session.delete('nostr_verified_pubkey') || session.delete(:nostr_verified_pubkey)
        profile = session.delete('nostr_profile') || session.delete(:nostr_profile) || {}

        if pubkey.nil? || pubkey.to_s.empty?
          return fail!(:invalid_credentials)
        end

        @uid = pubkey.to_s.downcase

        display = profile['display_name'].presence || profile[:display_name].presence ||
                  profile['name'].presence       || profile[:name].presence ||
                  "nostr:#{@uid[0, 12]}"

        @info = {
          name: display,
          nickname: (profile['name'] || profile[:name] || @uid[0, 12]).to_s,
          image: (profile['picture'] || profile[:picture]).to_s,
          description: (profile['about'] || profile[:about]).to_s
        }

        @extra = { raw_info: { pubkey: @uid, profile: profile, nip05: profile['nip05'] || profile[:nip05] } }

        super
      end

      uid { @uid }
      info { @info || {} }
      extra { @extra || {} }
    end
  end
end

OmniAuth.config.add_camelization('nostr', 'Nostr')
