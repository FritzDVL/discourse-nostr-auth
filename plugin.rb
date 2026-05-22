# frozen_string_literal: true

# name: discourse-nostr-auth
# about: Sign in with Nostr (NIP-07 today, NIP-46 planned). Pure-Ruby BIP-340 verifier, no native gems.
# version: 0.1.0
# author: FritzDVL
# url: https://github.com/FritzDVL/discourse-nostr-auth
# required_version: 2.7.0

# ---------------------------------------------------------------------------
# DISCOURSE PLUGIN INSTALL DISCIPLINE — Ruby 3.4 / Discourse base image
# 2.0.20260209-1300. Hard-won rules carried over from the sibling SIWE plugin.
#
#   1. Discourse's plugin `gem` DSL is `gem(name, version, opts={})`. A literal
#      version string MUST be the 2nd argument — `gem 'foo', require: false`
#      (no version) raises "Illformed requirement" at boot. Every gem line
#      below carries an explicit pinned version, even if it looks redundant.
#
#   2. Discourse runs `gem install --ignore-dependencies`. Every transitive
#      dependency must be declared explicitly in install order, including ones
#      that used to be Ruby default gems before 3.4 (e.g. `base64`).
#
#   3. Native-extension gems may need a `before_code` block in app.yml if
#      extconf.rb needs system libraries not present in the base image. This
#      plugin DELIBERATELY uses zero native-extension gems for crypto — the
#      BIP-340 Schnorr verifier is pure Ruby (see lib/discourse_nostr/bip340_verifier.rb).
#      No `before_code` hook is required in app.yml.
#
#   4. Pin every version. Resolver surprises on base-image bumps cost more
#      than the noise of pinned versions in a diff.
# ---------------------------------------------------------------------------

# No external gems are required for v1. JSON, OpenSSL, SecureRandom are all
# in the Ruby stdlib (and already loaded by Discourse). Schnorr verification
# is pure Ruby. WebSocket profile fetching happens in the browser widget, not
# on the server.

enabled_site_setting :discourse_nostr_enabled

register_asset 'stylesheets/discourse-nostr-auth.scss'
register_asset 'javascripts/nostr.iife.js'

require_relative 'lib/discourse_nostr/bip340_verifier'
require_relative 'lib/discourse_nostr/event_validator'
require_relative 'lib/discourse_nostr/boot_smoke_test'
require_relative 'lib/omniauth/strategies/nostr'

# Boot-time smoke test: refuse to start if the BIP-340 verifier ever regresses
# against the official test vectors. Non-negotiable security guarantee.
DiscourseNostr::BootSmokeTest.run!

class ::NostrAuthenticator < ::Auth::ManagedAuthenticator
  def name
    'nostr'
  end

  def register_middleware(omniauth)
    omniauth.provider :nostr
  end

  def enabled?
    SiteSetting.discourse_nostr_enabled
  end

  # Nostr identities have no email. Discourse should not try to verify one.
  def primary_email_verified?(auth_token)
    false
  end

  def can_revoke?
    true
  end
end

auth_provider authenticator: ::NostrAuthenticator.new,
              icon: 'key',
              full_screen_login: true

after_initialize do
  module ::DiscourseNostr
    PLUGIN_NAME = 'discourse-nostr-auth'

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseNostr
    end
  end

  require_relative 'app/controllers/discourse_nostr/auth_controller'

  Discourse::Application.routes.append do
    mount ::DiscourseNostr::Engine, at: '/auth/nostr'
  end

  DiscourseNostr::Engine.routes.draw do
    get  '/challenge' => 'auth#challenge'
    post '/verify'    => 'auth#verify'
  end
end
