# frozen_string_literal: true

require 'json'
require 'openssl'

module DiscourseNostr
  # Strict NIP-01 / NIP-42 event validator.
  #
  # Order of checks is intentional: cheap structural checks first, then id
  # recompute, then the expensive signature verification last. The signature
  # check ALWAYS runs before any DB lookup — see auth_controller.rb. There is
  # no path that links a Discourse account to a pubkey before
  # verify_login_event! returns successfully.
  module EventValidator
    REQUIRED_FIELDS = %w[id pubkey created_at kind tags content sig].freeze
    LOGIN_KIND = 22242
    HEX64 = /\A[0-9a-f]{64}\z/.freeze
    HEX128 = /\A[0-9a-f]{128}\z/.freeze

    module_function

    # Returns { pubkey:, created_at:, id: } on success. Raises Discourse::InvalidAccess otherwise.
    def verify_login_event!(event:, expected_challenge:, clock_skew_seconds: 60)
      raise_invalid('bad_event') unless event.is_a?(Hash)

      # Strict parsing: reject events with extra top-level fields beyond NIP-01.
      extra = event.keys.map(&:to_s) - REQUIRED_FIELDS
      raise_invalid('bad_event') unless extra.empty?

      id         = event['id']
      pubkey     = event['pubkey']
      created_at = event['created_at']
      kind       = event['kind']
      tags       = event['tags']
      content    = event['content']
      sig        = event['sig']

      raise_invalid('bad_event') unless id.is_a?(String)     && id =~ HEX64
      raise_invalid('bad_event') unless pubkey.is_a?(String) && pubkey =~ HEX64
      raise_invalid('bad_event') unless sig.is_a?(String)    && sig =~ HEX128
      raise_invalid('bad_event') unless created_at.is_a?(Integer)
      raise_invalid('bad_event') unless kind.is_a?(Integer)
      raise_invalid('bad_event') unless tags.is_a?(Array) && tags.all? { |t| t.is_a?(Array) && t.all? { |s| s.is_a?(String) } }
      raise_invalid('bad_event') unless content.is_a?(String)

      raise_invalid('bad_kind') unless kind == LOGIN_KIND

      now = Time.now.to_i
      raise_invalid('bad_timestamp') if (now - created_at).abs > clock_skew_seconds

      challenge_tag = tags.find { |t| t[0] == 'challenge' }
      raise_invalid('bad_challenge') unless challenge_tag && challenge_tag[1] == expected_challenge

      # Recompute id and compare. NIP-01 §3 canonical serialization:
      # [0, pubkey, created_at, kind, tags, content]  — JSON-encoded, UTF-8.
      canonical = JSON.generate([0, pubkey, created_at, kind, tags, content])
      computed_id = OpenSSL::Digest::SHA256.hexdigest(canonical)
      raise_invalid('bad_id') unless computed_id == id.downcase

      # Schnorr signature verification. Runs LAST. No DB has been touched yet.
      ok = ::DiscourseNostr::BIP340Verifier.verify(pubkey, id, sig)
      raise_invalid('bad_signature') unless ok

      { pubkey: pubkey.downcase, created_at: created_at, id: id.downcase }
    end

    def raise_invalid(key)
      raise Discourse::InvalidAccess.new("discourse_nostr.errors.#{key}")
    end
  end
end
