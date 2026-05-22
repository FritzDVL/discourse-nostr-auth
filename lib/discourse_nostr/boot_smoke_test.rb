# frozen_string_literal: true

module DiscourseNostr
  # Boot-time smoke test. The plugin refuses to start if the BIP-340 verifier
  # cannot verify a known-good signature and reject a known-bad one. This is
  # the cheapest possible insurance against a refactor silently breaking the
  # crypto path. The full BIP-340 official test vector suite runs in
  # spec/bip340_verifier_spec.rb under CI.
  module BootSmokeTest
    # BIP-340 official test vector index 0 (pure verify side):
    #   https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv
    GOOD_PUBKEY  = 'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9'
    GOOD_MESSAGE = '0000000000000000000000000000000000000000000000000000000000000000'
    GOOD_SIG     = 'e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215' \
                   '25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0'

    module_function

    def run!
      ok_good = ::DiscourseNostr::BIP340Verifier.verify(GOOD_PUBKEY, GOOD_MESSAGE, GOOD_SIG)
      raise 'discourse-nostr-auth: BIP-340 smoke test FAILED (good vector rejected). Refusing to boot.' unless ok_good

      # Flip one bit of the signature; must be rejected.
      bad_sig = GOOD_SIG.dup
      bad_sig[0] = bad_sig[0] == 'e' ? 'f' : 'e'
      ok_bad = ::DiscourseNostr::BIP340Verifier.verify(GOOD_PUBKEY, GOOD_MESSAGE, bad_sig)
      raise 'discourse-nostr-auth: BIP-340 smoke test FAILED (bad signature accepted). Refusing to boot.' if ok_bad

      true
    end
  end
end
