#!/bin/bash
set -euo pipefail

# -------------------------------
# CONFIG
# -------------------------------
DRYRUN="--dry-run" # set to "--dry-run" for testing or set to "" for real payouts
BAKER="tz1eo3APJNdYst3mu7axpyZsJBPEqwxm8Sv1" # Baker address
PAYOUT="tz1Lz19xKSsczwGGZw7VkVkrN1x3xYZyGfts" # Payout address (if payouts come directly from the baker you can set this as "$BAKER"
SIGNER="http://localhost:6732" # Tezos remote/local signer (set to "" if you don't use a signer)
NODE="http://127.0.0.1:8732" # Tezos node RPC
API="https://api.mainnet.tzkt.io/v1" # TZKT api (for testnet you can use "https://api.ghostnet.tzkt.io/v1")

STATEFILE="/var/lib/tezos/payout_state"   # track last paid cycle
FEE_PERCENT=20                            # 20% baker fee
MIN_BAL=100000000                         # 100 tez in mutez

TMP=$(/usr/bin/mktemp)

# -------------------------------
# FETCH LAST COMPLETED CYCLE
# -------------------------------
CYCLE=$(/usr/bin/curl -s "$API/cycles?limit=1&offset=3" | /usr/bin/jq -r '.[0].index')

if [ -z "$CYCLE" ] || [ "$CYCLE" = "null" ]; then
    /usr/bin/echo "Could not determine cycle. Exiting."
    exit 1
fi

if [ -f "$STATEFILE" ] && /usr/bin/grep -qx "$CYCLE" "$STATEFILE"; then
    /usr/bin/echo "Cycle $CYCLE already paid, exiting."
    if [ "$DRYRUN" != "--dry-run" ]; then
        /usr/bin/rm -f "$TMP"
        exit 0
    fi
fi

/usr/bin/echo "Preparing payouts for cycle $CYCLE"

# -------------------------------
# FETCH SPLIT DATA
# -------------------------------
SPLIT=$(/usr/bin/curl -s "$API/rewards/split/$BAKER/$CYCLE")

TOTAL_REWARDS=$(/usr/bin/echo "$SPLIT" | /usr/bin/jq -r '(.attestationRewardsDelegated + .dalAttestationRewardsDelegated +.blockRewardsDelegated) // 0')
if [ -z "$TOTAL_REWARDS" ] || [ "$TOTAL_REWARDS" = "null" ] || [ "$TOTAL_REWARDS" -eq 0 ]; then
    /usr/bin/echo "No rewards found for cycle $CYCLE. Exiting."
    /usr/bin/rm -f "$TMP"
    exit 0
fi

NET_REWARDS=$(/usr/bin/echo "$TOTAL_REWARDS * (100 - $FEE_PERCENT) / 100" | /usr/bin/bc)

TOTAL_BAL=$(/usr/bin/echo "$SPLIT" | jq -r '.externalDelegatedBalance')

/usr/bin/echo "Total rewards before fee: $TOTAL_REWARDS mutez"
/usr/bin/echo "Total rewards after $FEE_PERCENT% fee: $NET_REWARDS mutez"
/usr/bin/echo "Total delegated balance: $TOTAL_BAL"

# -------------------------------
# BUILD TRANSFER LIST
# -------------------------------
/usr/bin/echo "[" > "$TMP"
FIRST=1

/usr/bin/echo "$SPLIT" | /usr/bin/jq -c '.delegators[]' | while read -r DELEGATOR; do
    ADDR=$(/usr/bin/echo "$DELEGATOR" | /usr/bin/jq -r '.address')
    BAL=$(/usr/bin/echo "$DELEGATOR" | /usr/bin/jq -r '.delegatedBalance')

    # eligibility check: must have >= 100 tez and not be payout address
    if [ "$BAL" -ge "$MIN_BAL" ] && [ "$ADDR" != "$PAYOUT" ]; then
        # proportional share
        SHARE=$(/usr/bin/echo "scale=12; $BAL / $TOTAL_BAL" | /usr/bin/bc -l)

        # reward in mutez
        AMOUNT_MUTEZ=$(/usr/bin/echo "$NET_REWARDS * $SHARE - 750" | /usr/bin/bc -l | /usr/bin/cut -d'.' -f1)

        # convert to tez with 6 decimals, always leading 0
        AMOUNT_TEZ=$(/usr/bin/echo "scale=6; $AMOUNT_MUTEZ / 1000000" | /usr/bin/bc -l | /usr/bin/awk '{printf "%0.6f", $0}')

        if [ $FIRST -eq 0 ]; then
            /usr/bin/echo "," >> "$TMP"
        fi
        FIRST=0

        /usr/bin/jq -n --arg dst "$ADDR" --arg amt "$AMOUNT_TEZ" \
          '{destination:$dst, amount:$amt}' >> "$TMP"
    fi
done

/usr/bin/echo "]" >> "$TMP"

/usr/bin/echo "Generated batch file:"
/usr/bin/cat "$TMP"

# -------------------------------
# EXECUTE BATCH (Or DRY-RUN if enabled in the config above)
# -------------------------------
if [ "$SIGNER" != "" ]; then
    NODE="$NODE -R $SIGNER"
fi
/usr/bin/octez-client --endpoint $NODE multiple transfers from $PAYOUT using "$TMP" $DRYRUN

# -------------------------------
# SAVE STATE
# -------------------------------
if [ "$DRYRUN" != "--dry-run" ]; then
    /usr/bin/echo "$CYCLE" > "$STATEFILE"
fi

/usr/bin/rm -f "$TMP"

exit 0
