# frozen_string_literal: true

require 'securerandom'

module ::DiscourseNostr
  class AuthController < ::ApplicationController
    requires_plugin ::DiscourseNostr::PLUGIN_NAME

    skip_before_action :check_xhr, only: [:challenge, :verify]
    skip_before_action :redirect_to_login_if_required, only: [:challenge, :verify]

    # GET /auth/nostr/challenge
    # Issues a per-session, single-use challenge nonce. Stored server-side in
    # the session and consumed exactly once by /verify. Never trust a challenge
    # the client sends — that is the whole point.
    def challenge
      raise Discourse::InvalidAccess.new('discourse_nostr.errors.disabled') unless SiteSetting.discourse_nostr_enabled

      nonce = SecureRandom.hex(32)
      session[:nostr_challenge] = nonce
      session[:nostr_challenge_issued_at] = Time.now.to_i

      render json: {
        challenge: nonce,
        relay: Discourse.base_url,
        kind: 22242,
        ttl: SiteSetting.nostr_challenge_ttl_seconds
      }
    end

    # POST /auth/nostr/verify
    # Body: { event: <signed NIP-01 event JSON>, profile: {...optional kind:0 fields...} }
    #
    # This endpoint does NOT log the user in directly — it hands the verified
    # pubkey to OmniAuth via a synthetic callback so that ManagedAuthenticator
    # can do user lookup / account linking the standard Discourse way.
    def verify
      raise Discourse::InvalidAccess.new('discourse_nostr.errors.disabled') unless SiteSetting.discourse_nostr_enabled

      issued = session[:nostr_challenge]
      issued_at = session[:nostr_challenge_issued_at].to_i
      raise Discourse::InvalidAccess.new('discourse_nostr.errors.no_challenge') if issued.blank?

      if Time.now.to_i - issued_at > SiteSetting.nostr_challenge_ttl_seconds
        session.delete(:nostr_challenge)
        session.delete(:nostr_challenge_issued_at)
        raise Discourse::InvalidAccess.new('discourse_nostr.errors.challenge_expired')
      end

      raw_event = params.require(:event)
      raw_event = JSON.parse(raw_event) if raw_event.is_a?(String)

      verified = ::DiscourseNostr::EventValidator.verify_login_event!(
        event: raw_event,
        expected_challenge: issued,
        clock_skew_seconds: SiteSetting.nostr_event_clock_skew_seconds
      )

      # Single-use: consume the challenge now that verification succeeded.
      session.delete(:nostr_challenge)
      session.delete(:nostr_challenge_issued_at)

      # Hand off to OmniAuth via session-stashed payload, then redirect into
      # the standard OmniAuth callback that ManagedAuthenticator wires up.
      session[:nostr_verified_pubkey] = verified[:pubkey]
      session[:nostr_profile] = sanitize_profile(params[:profile])

      redirect_to '/auth/nostr/callback'
    end

    private

    def sanitize_profile(profile)
      return {} if profile.blank?
      profile = JSON.parse(profile) if profile.is_a?(String)
      {
        name: profile['name'].to_s[0, 60],
        display_name: profile['display_name'].to_s[0, 60],
        picture: profile['picture'].to_s[0, 2048],
        nip05: profile['nip05'].to_s[0, 254],
        about: profile['about'].to_s[0, 3000]
      }.compact
    end
  end
end
