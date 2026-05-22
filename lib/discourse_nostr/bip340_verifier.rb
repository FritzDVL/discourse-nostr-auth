# frozen_string_literal: true

# Pure-Ruby BIP-340 Schnorr signature verifier over secp256k1.
#
# Reference:
#   https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
#
# This file deliberately depends on nothing outside the Ruby stdlib (OpenSSL
# for SHA-256 only). No native-extension gems. No libsecp256k1. No rbsecp256k1.
# This is the equivalent design choice as inlining EIP-6492 bytecode in the
# sibling SIWE plugin — we own the crypto, no upstream gem can break us on
# the next Discourse base-image bump.
#
# Correctness gate: every BIP-340 official test vector (spec/bip340_verifier_spec.rb)
# MUST pass. The plugin refuses to boot otherwise (see boot_smoke_test.rb).

require 'openssl'

module DiscourseNostr
  module BIP340Verifier
    module_function

    # secp256k1 curve parameters.
    P = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_FFFFFC2F
    N = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_BAAEDCE6_AF48A03B_BFD25E8C_D0364141
    GX = 0x79BE667E_F9DCBBAC_55A06295_CE870B07_029BFCDB_2DCE28D9_59F2815B_16F81798
    GY = 0x483ADA77_26A3C465_5DA4FBFC_0E1108A8_FD17B448_A6855419_9C47D08F_FB10D4B8
    G  = [GX, GY].freeze

    # verify(pubkey, message, signature)
    #   pubkey    — 32 raw bytes (x-only) OR 64-char lowercase hex
    #   message   — 32 raw bytes (the BIP-340 challenge usually hashes the data first;
    #               for NIP-01 events `message` is the 32-byte event id)
    #   signature — 64 raw bytes OR 128-char lowercase hex
    #
    # Returns true / false. Never raises on bad input — returns false.
    def verify(pubkey, message, signature)
      pubkey    = hex_to_bytes(pubkey)    if pubkey.is_a?(String)    && pubkey.length    == 64
      signature = hex_to_bytes(signature) if signature.is_a?(String) && signature.length == 128
      message   = hex_to_bytes(message)   if message.is_a?(String)   && message.length   == 64

      return false unless pubkey.is_a?(String)    && pubkey.bytesize    == 32
      return false unless signature.is_a?(String) && signature.bytesize == 64
      return false unless message.is_a?(String)   && message.bytesize   == 32

      pubkey_int = bytes_to_int(pubkey)
      return false if pubkey_int >= P
      pp = lift_x(pubkey_int)
      return false if pp.nil?

      r = bytes_to_int(signature.byteslice(0, 32))
      s = bytes_to_int(signature.byteslice(32, 32))
      return false if r >= P
      return false if s >= N

      # e = int(tagged_hash("BIP0340/challenge", bytes(r) || bytes(P) || m)) mod n
      e_hash = tagged_hash('BIP0340/challenge',
                           int_to_bytes(r) + int_to_bytes(pubkey_int) + message)
      e = bytes_to_int(e_hash) % N

      # R = s*G - e*P
      s_g  = point_mul(G, s)
      e_p  = point_mul(pp, e)
      neg_e_p = point_negate(e_p)
      r_point = point_add(s_g, neg_e_p)

      return false if r_point.nil?           # point at infinity
      return false unless even_y?(r_point)   # has_even_y(R)
      r_point[0] == r                        # x(R) == r
    rescue StandardError
      false
    end

    # tagged_hash(tag, msg) = SHA256(SHA256(tag) || SHA256(tag) || msg)
    def tagged_hash(tag, msg)
      tag_hash = OpenSSL::Digest::SHA256.digest(tag)
      OpenSSL::Digest::SHA256.digest(tag_hash + tag_hash + msg)
    end

    # lift_x(x): given an x-coord, return the (x, y) with even y, or nil.
    def lift_x(x)
      return nil if x.zero? || x >= P
      c = (mod_pow(x, 3, P) + 7) % P
      y = mod_pow(c, (P + 1) / 4, P)
      return nil unless (y * y) % P == c
      y = P - y if (y & 1) == 1
      [x, y]
    end

    def even_y?(point)
      (point[1] & 1).zero?
    end

    def point_negate(pt)
      return nil if pt.nil?
      [pt[0], (P - pt[1]) % P]
    end

    # Jacobian-free affine point addition over secp256k1. Correct, not fast.
    # secp256k1 has a=0 so the doubling formula simplifies.
    def point_add(a, b)
      return b if a.nil?
      return a if b.nil?
      x1, y1 = a
      x2, y2 = b

      if x1 == x2
        return nil if (y1 + y2) % P == 0   # P + (-P) = infinity
        # Doubling: lam = 3*x1^2 / (2*y1)
        num = (3 * x1 * x1) % P
        den = mod_inv((2 * y1) % P, P)
        lam = (num * den) % P
      else
        num = (y2 - y1) % P
        den = mod_inv((x2 - x1) % P, P)
        lam = (num * den) % P
      end

      x3 = (lam * lam - x1 - x2) % P
      y3 = (lam * (x1 - x3) - y1) % P
      [x3, y3]
    end

    # Double-and-add scalar multiplication. Constant-timeness is not a goal
    # here — this code only ever runs on *public* inputs (pubkey, signature,
    # message). There is no secret scalar to leak.
    def point_mul(pt, k)
      result = nil
      addend = pt
      while k > 0
        result = point_add(result, addend) if (k & 1) == 1
        addend = point_add(addend, addend)
        k >>= 1
      end
      result
    end

    def mod_pow(base, exp, mod)
      base.to_bn.mod_exp(exp, mod).to_i
    end

    # Extended Euclidean modular inverse.
    def mod_inv(a, m)
      a %= m
      raise ZeroDivisionError, 'no inverse' if a.zero?
      lm, hm = 1, 0
      low, high = a, m
      while low > 1
        r = high / low
        nm = hm - lm * r
        new_val = high - low * r
        hm, lm = lm, nm
        high, low = low, new_val
      end
      lm % m
    end

    def int_to_bytes(i)
      hex = i.to_s(16).rjust(64, '0')
      [hex].pack('H*')
    end

    def bytes_to_int(b)
      b.unpack1('H*').to_i(16)
    end

    def hex_to_bytes(hex)
      [hex].pack('H*')
    end
  end
end
