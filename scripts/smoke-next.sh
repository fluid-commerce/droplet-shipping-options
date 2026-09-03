#!/usr/bin/env bash
#
# Synthetic smoke test against a deployed Next service.
#
#   scripts/smoke-next.sh https://fluid-droplet-name-next-xxxx.a.run.app
#
# Sends no valid signatures, so it needs no secrets and is safe against
# production. Read the limits below before trusting a pass.
#
# WHAT THIS CAN AND CANNOT SHOW
#
# The webhook route fails CLOSED, so an unsigned request must be refused with a
# 401. That is a real assertion: if verification were broken or the route were
# unwrapped, this would come back 200.
#
# The callback route fails OPEN by design — `onAuthFailure: ok` answers 200
# `{"success":true}`, because Fluid blocks a live cart on this response and a
# 401 would break checkout rather than protect it. So an unauthenticated probe
# CANNOT distinguish "verifying correctly and refusing me" from "cannot verify
# anything and refusing everyone". Both look identical from outside. That is
# the point of the design and the blind spot of this script.
#
# What that means in practice: a pass here says the service is up, routed, and
# refusing unsigned webhooks. It does NOT say a genuine Fluid callback would be
# accepted. Only real traffic — or a request signed with a real registration
# token — shows that, which is why the first cutover is an internal
# installation and not a client.
set -uo pipefail

BASE="${1:-}"
[ -n "$BASE" ] || { echo "usage: $0 <base-url>"; exit 2; }
BASE="${BASE%/}"

fail=0
check () {
  local name="$1" expected="$2" got="$3"
  if [ "$got" = "$expected" ]; then
    printf '  ok    %-48s %s\n' "$name" "$got"
  else
    printf '  FAIL  %-48s got %s, want %s\n' "$name" "$got" "$expected"
    fail=$((fail + 1))
  fi
}

code () { curl -s -o /dev/null -m 20 -w '%{http_code}' "$@" 2>/dev/null || echo 000; }
body () { curl -s -m 20 "$@" 2>/dev/null || echo ""; }

echo "Smoke testing $BASE"

check "health" 200 "$(code "$BASE/api/health")"

# Fails closed. This is the assertion that carries weight.
check "webhook without a signature is refused" 401 \
  "$(code -X POST "$BASE/api/webhooks" \
      -H 'content-type: application/json' \
      -d '{"resource":"order","event":"created","company":{"fluid_shop":"smoke"}}')"

# 400, NOT 401. The SDK wrapper reads and JSON.parses the body BEFORE it looks
# at the signature (withFluidWebhook: onInvalidBody fires on a parse failure,
# well above the verification block), so a malformed body is rejected as a bad
# request and never reaches auth. This assertion previously demanded 401 on the
# strength of a comment claiming the opposite order — it would have failed
# against a correctly deployed service.
check "webhook with a malformed body is a bad request" 400 \
  "$(code -X POST "$BASE/api/webhooks" \
      -H 'content-type: application/json' -d 'not json')"

# A bootstrap-eligible event with no signature must also be refused. The shared
# secret is a candidate for these events, not a bypass of verification.
check "unsigned install event is refused" 401 \
  "$(code -X POST "$BASE/api/webhooks" \
      -H 'content-type: application/json' \
      -d '{"name":"droplet_installed","payload":{"company":{"fluid_shop":"smoke"}}}')"

# All four callback routes fail open, so a 200 proves routing and that the route
# is deployed — nothing about verification. Asserted anyway because a 404 or a
# 500 here is a genuine finding: it means the route is missing or throwing, and
# a 404 is exactly what a wrong path in the `callbacks` table produces.
#
# Each is checked against its OWN neutral body, because they differ and the
# difference is what fluid reads:
#   update-cart-shipping     {"success":true,"shipping_options":[]}
#   cart-customer-logged-in  {"success":true}
#   update-cart-email        {"success":true,"valid":true}
#   verify-email-success     {"success":true}
#
# Compared exactly, never with a substring match. `*success*` also matches
# {"success":false} and an HTML error page containing the word — which is
# precisely the kind of green that means nothing.
probe_callback () {
  local path="$1" expected_body="$2"
  local status body_out

  status=$(code -X POST "$BASE$path" \
    -H 'content-type: application/json' -d '{"cart":{"id":1}}')
  check "POST $path answers (routing only)" 200 "$status"

  body_out=$(body -X POST "$BASE$path" \
    -H 'content-type: application/json' -d '{"cart":{"id":1}}')
  if [ "$body_out" = "$expected_body" ]; then
    printf '  ok    %-48s %s\n' "  ...with its neutral body" "$body_out"
  else
    printf '  FAIL  %-48s got %s, want %s\n' "  ...with its neutral body" \
      "$body_out" "$expected_body"
    fail=$((fail + 1))
  fi
}

probe_callback /api/callbacks/update-cart-shipping \
  '{"success":true,"shipping_options":[]}'
probe_callback /api/callbacks/cart-customer-logged-in '{"success":true}'
probe_callback /api/callbacks/update-cart-email '{"success":true,"valid":true}'
probe_callback /api/callbacks/verify-email-success '{"success":true}'

# The assertions above prove the service REFUSES what it should. They cannot
# prove it ACCEPTS what it should: deploy with FLUID_WEBHOOK_AUTH_TOKEN absent
# or wrong and every one of them still passes, while every genuine signed
# install and uninstall is also refused. So if the secret is available, send a
# correctly signed lifecycle event and require it NOT to be a 401.
#
#   FLUID_WEBHOOK_AUTH_TOKEN=... scripts/smoke-next.sh https://...
#
# 401 means verification is rejecting real Fluid traffic. Anything else — 202,
# 204, even a 500 from the handler — proves the signature was accepted, which is
# the only thing this check is about.
if [ -n "${FLUID_WEBHOOK_AUTH_TOKEN:-}" ]; then
  # `droplet.uninstalled`, NOT `droplet.installed`, and this matters.
  #
  # A signed install would WRITE: handleDropletInstalled only bails early when a
  # configured droplet uuid fails to match, and when none is configured it warns
  # and carries on — creating a `companies` row named "Smoke" with
  # `authentication_token: "smoke"` in whatever database the service is pointed
  # at. A smoke test must not be able to do that.
  #
  # Uninstall is also a bootstrap event, so it proves exactly the same thing
  # about the signature, but `handleDropletUninstalled` resolves the company
  # first and returns when it finds none. With a DRI that matches nothing, it is
  # provably write-free.
  BODY='{"resource":"droplet","event":"uninstalled","company":{"droplet_installation_uuid":"dri_smoke_probe_no_such_installation"}}'
  TS=$(date +%s)
  SIG=$(printf '%s.%s' "$TS" "$BODY" \
    | openssl dgst -sha256 -hmac "$FLUID_WEBHOOK_AUTH_TOKEN" \
    | sed 's/^.*= //')
  SIGNED=$(code -X POST "$BASE/api/webhooks" \
    -H 'content-type: application/json' \
    -H "X-Fluid-Timestamp: $TS" \
    -H "X-Fluid-Signature: $SIG" \
    -d "$BODY")
  if [ "$SIGNED" = "401" ]; then
    printf '  FAIL  %-48s %s\n' "signed lifecycle webhook is accepted" "$SIGNED"
    fail=$((fail + 1))
  else
    printf '  ok    %-48s %s\n' "signed lifecycle webhook is accepted" "$SIGNED"
  fi
else
  printf '  SKIP  %-48s %s\n' "signed lifecycle webhook is accepted" \
    "set FLUID_WEBHOOK_AUTH_TOKEN to check"
fi

echo
if [ "$fail" -gt 0 ]; then
  echo "$fail check(s) failed — do not repoint any installation at this service."
  exit 1
fi
if [ -n "${FLUID_WEBHOOK_AUTH_TOKEN:-}" ]; then
  echo "Passed. The service refuses unsigned webhooks AND accepts a signed one."
else
  echo "Passed, but only the refusal half was checked — nothing here proves a"
  echo "genuine signed webhook would be accepted. Re-run with"
  echo "FLUID_WEBHOOK_AUTH_TOKEN set before repointing anything."
fi
echo "This does NOT establish that a signed callback would be accepted;"
echo "cut an internal installation over first and watch it."
