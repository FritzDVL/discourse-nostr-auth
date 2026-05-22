# frozen_string_literal: true

require 'rspec'
require 'json'
require 'openssl'
require_relative '../lib/discourse_nostr/bip340_verifier'
require_relative '../lib/discourse_nostr/event_validator'

# Discourse::InvalidAccess is provided by Discourse at runtime. Stub it for
# isolated spec runs that don't boot Rails.
unless defined?(::Discourse)
  module ::Discourse
    class InvalidAccess < StandardError; end
  end
end

# These specs do NOT generate Schnorr signatures (that would require a
# secp256k1 keygen path we don't ship). Instead, every "happy path" test stubs
# DiscourseNostr::BIP340Verifier.verify so we exercise the validator's own
# structural / id-recompute / challenge / kind / timestamp logic exhaustively.
# bip340_verifier_spec.rb separately proves the verifier itself against the
# official BIP-340 vectors.

RSpec.describe DiscourseNostr::EventValidator do
  let(:pubkey) { 'a' * 64 }
  let(:sig)    { 'b' * 128 }
  let(:challenge) { 'deadbeef' * 8 }
  let(:created_at) { Time.now.to_i }

  def event(overrides = {})
    base = {
      'pubkey' => pubkey,
      'created_at' => created_at,
      'kind' => 22242,
      'tags' => [['challenge', challenge]],
      'content' => '',
    }.merge(overrides.reject { |k, _| k.to_s == 'id' || k.to_s == 'sig' })

    canonical = JSON.generate([0, base['pubkey'], base['created_at'], base['kind'], base['tags'], base['content']])
    base['id']  = overrides['id']  || OpenSSL::Digest::SHA256.hexdigest(canonical)
    base['sig'] = overrides['sig'] || sig
    base
  end

  before { allow(DiscourseNostr::BIP340Verifier).to receive(:verify).and_return(true) }

  it 'accepts a well-formed event with matching challenge' do
    res = described_class.verify_login_event!(event: event, expected_challenge: challenge)
    expect(res[:pubkey]).to eq(pubkey)
  end

  it 'rejects wrong kind' do
    expect { described_class.verify_login_event!(event: event('kind' => 1), expected_challenge: challenge) }
      .to raise_error(Discourse::InvalidAccess, /bad_kind/)
  end

  it 'rejects mismatched challenge' do
    e = event('tags' => [['challenge', 'feedface' * 8]])
    expect { described_class.verify_login_event!(event: e, expected_challenge: challenge) }
      .to raise_error(Discourse::InvalidAccess, /bad_challenge/)
  end

  it 'rejects out-of-window timestamp' do
    e = event('created_at' => Time.now.to_i - 3600)
    expect { described_class.verify_login_event!(event: e, expected_challenge: challenge, clock_skew_seconds: 60) }
      .to raise_error(Discourse::InvalidAccess, /bad_timestamp/)
  end

  it 'rejects tampered id' do
    e = event
    e['id'] = '0' * 64
    expect { described_class.verify_login_event!(event: e, expected_challenge: challenge) }
      .to raise_error(Discourse::InvalidAccess, /bad_id/)
  end

  it 'rejects bad signature (verifier returns false)' do
    allow(DiscourseNostr::BIP340Verifier).to receive(:verify).and_return(false)
    expect { described_class.verify_login_event!(event: event, expected_challenge: challenge) }
      .to raise_error(Discourse::InvalidAccess, /bad_signature/)
  end

  it 'rejects extra top-level fields' do
    e = event.merge('extra' => 'no')
    expect { described_class.verify_login_event!(event: e, expected_challenge: challenge) }
      .to raise_error(Discourse::InvalidAccess, /bad_event/)
  end

  it 'rejects malformed pubkey / sig hex' do
    e = event('pubkey' => 'z' * 64)
    expect { described_class.verify_login_event!(event: e, expected_challenge: challenge) }
      .to raise_error(Discourse::InvalidAccess, /bad_event/)
  end
end
