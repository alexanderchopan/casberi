#!/bin/zsh
# Every mainnet move, simulated (prd §1563), then each mutation, which must be
# CAUGHT (its run fails). Writes mainnet-sim.json, the record, on a clean pass.
# Nothing is signed or sent: see mainnet-sim.mjs.
#   ./run-mainnet-sim.sh
cd "${0:A:h}"
WRITE_RECORD=1 node mainnet-sim.mjs || { echo "MAINNET SIM FAILED"; exit 1; }
tmp=$(mktemp)
for m in devkeys value proof notowner recipient freshgas usdcgas transferto; do
  case $m in
    devkeys|value|proof) s=eth ;;
    notowner) s=ragequit ;;
    recipient) s=withdraw ;;
    freshgas) s=fresh ;;
    usdcgas) s=freshusdc ;;
    transferto) s=transfer ;;
  esac
  if node mainnet-sim.mjs $s --mutate $m > $tmp 2>&1; then
    echo "mutation $m: caught ($(grep -m1 FAILED $tmp | cut -c1-160))"
  else
    echo "mutation $m: SURVIVED"; tail -5 $tmp; rm -f $tmp; exit 1
  fi
done
rm -f $tmp
echo "mainnet simulation: every move lands; 8 of 8 mutations caught"
