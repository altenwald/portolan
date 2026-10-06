#!/usr/bin/env bash
# Builds and tests every example, checking that the optional dependencies
# of Portolan are really optional. with_ecto serves a local copy of the
# documentation interface, installed with mix portolan.ui.install.
set -euo pipefail

cd "$(dirname "$0")"

for example in minimal with_ecto with_decimal; do
  echo "==> $example"
  (
    cd "$example"
    mix deps.get >/dev/null
    mix hex.audit
    if [ "$example" = with_ecto ]; then mix portolan.ui.install; fi
    mix compile --warnings-as-errors --force
    mix test --warnings-as-errors
  )
done

echo "==> minimal has neither ecto nor decimal"
if (cd minimal && mix deps.tree) | grep -E "ecto|decimal"; then
  echo "minimal depends on ecto or decimal" >&2
  exit 1
fi

echo "==> minimal works as a release"
(
  cd minimal
  MIX_ENV=prod mix release --overwrite --quiet
  export PORT=4123
  _build/prod/rel/minimal/bin/minimal daemon
  trap '_build/prod/rel/minimal/bin/minimal stop' EXIT

  for _ in $(seq 1 30); do
    curl -sf "localhost:$PORT/openapi.json" >/dev/null && break
    sleep 0.5
  done

  curl -sf -X POST "localhost:$PORT/api/notes" -H 'content-type: application/json' \
    -d '{"title":"From a release","tags":["release"]}' | grep -q '"tags":\["release"\]'
  curl -s "localhost:$PORT/api/notes/nope" | grep -q 'must be an integer'
)

echo "All examples passed"
