# frozen_string_literal: true

require 'rspec'
require 'omniauth'
require_relative '../lib/omniauth/strategies/nostr'

RSpec.describe OmniAuth::Strategies::Nostr do
  let(:app) { ->(_env) { [200, {}, ['ok']] } }
  let(:pubkey) { 'f' * 64 }

  def env_with_session(session)
    {
      'rack.session' => session,
      'omniauth.params' => {},
      'PATH_INFO' => '/auth/nostr/callback',
      'REQUEST_METHOD' => 'GET',
    }
  end

  it 'fails when no verified pubkey is in session' do
    strategy = described_class.new(app)
    strategy.call!(env_with_session({}))
    # OmniAuth fail! sets env['omniauth.error'] indirectly; here we just want
    # to assert it didn't crash and didn't expose a uid.
    expect(strategy.uid).to be_nil
  end

  it 'builds auth hash from session payload' do
    strategy = described_class.new(app)
    session = {
      'nostr_verified_pubkey' => pubkey,
      'nostr_profile' => { 'name' => 'alice', 'display_name' => 'Alice', 'picture' => 'https://example/a.png' },
    }
    strategy.call!(env_with_session(session))
    expect(strategy.uid).to eq(pubkey)
    expect(strategy.info[:name]).to eq('Alice')
  end
end
