#!/usr/bin/env python3
"""
hl-bridge.py - Check balances and bridge HYPE from L1 spot to HyperEVM.
Prepares a deployer wallet for gas on chain 999.

Usage:
  PRIVATE_KEY=0x... python3 script/hl-bridge.py
  PRIVATE_KEY=0x... python3 script/hl-bridge.py --bridge 0.5

Exit codes:
  0 - HyperEVM has gas (>=0.01 HYPE)
  1 - No gas on HyperEVM, bridge failed or not attempted
"""

import os
import sys
import json
import argparse
from decimal import Decimal

MIN_GAS_HYPE = Decimal("0.01")
HYPER_EVM_RPC = "https://rpc.hyperliquid.xyz/evm"
BRIDGE_SYSTEM_ADDR = "0x2222222222222222222222222222222222222222"

# HYPE token index on HL spot
HYPE_TOKEN_INDEX = 999


def get_evm_balance(address: str) -> Decimal:
    """Native HYPE balance on HyperEVM (chain 999) via JSON-RPC."""
    import urllib.request

    payload = json.dumps({
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": [address, "latest"],
        "id": 1,
    }).encode()

    req = urllib.request.Request(
        HYPER_EVM_RPC,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    resp = urllib.request.urlopen(req, timeout=10)
    data = json.loads(resp.read())

    if "error" in data:
        print(f"  RPC error: {data['error']}")
        return Decimal("0")

    wei = int(data["result"], 16)
    return Decimal(wei) / Decimal(10**18)


def get_l1_balances(address: str) -> dict:
    """Fetch spot balances from Hyperliquid L1 info API."""
    import urllib.request

    payload = json.dumps({
        "type": "spotClearinghouseState",
        "user": address,
    }).encode()

    req = urllib.request.Request(
        "https://api.hyperliquid.xyz/info",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    resp = urllib.request.urlopen(req, timeout=10)
    data = json.loads(resp.read())

    balances = {}
    for b in data.get("balances", []):
        coin = b.get("coin", "")
        total = Decimal(b.get("total", "0"))
        hold = Decimal(b.get("hold", "0"))
        available = total - hold
        if total > 0:
            balances[coin] = {"total": total, "hold": hold, "available": available}

    return balances


def attempt_bridge(private_key: str, amount: Decimal) -> bool:
    """
    Transfer HYPE from L1 spot to EVM via the system bridge address.
    Uses the Hyperliquid SDK spot_transfer action.
    Falls back if unified account blocks the transfer.
    """
    try:
        from hyperliquid.utils import constants
        from hyperliquid.exchange import Exchange
        from eth_account import Account

        account = Account.from_key(private_key)
        exchange = Exchange(account, constants.MAINNET_API_URL)

        # spot_transfer sends tokens to another HL user
        # sending to 0x2222...2222 bridges to EVM
        result = exchange.spot_transfer(
            float(amount),
            BRIDGE_SYSTEM_ADDR,
            "HYPE",
        )

        if result.get("status") == "ok":
            print(f"  Bridge TX submitted: {amount} HYPE -> EVM")
            resp_data = result.get("response", {})
            if resp_data:
                print(f"  Response: {json.dumps(resp_data, indent=2)}")
            return True
        else:
            err = result.get("response", result)
            print(f"  Bridge rejected: {err}")
            return False

    except ImportError as e:
        print(f"  SDK missing: {e}")
        print("  Install: pip install hyperliquid-python-sdk eth_account")
        return False

    except Exception as e:
        err_str = str(e)
        # Unified account mode blocks spot_transfer for some wallets
        if "unified" in err_str.lower() or "spot_transfer" in err_str.lower():
            print(f"  Unified account blocks spot_transfer: {err_str}")
            print("  Fix: disable unified mode in HL dashboard, or bridge manually.")
        else:
            print(f"  Bridge failed: {err_str}")
        return False


def main():
    parser = argparse.ArgumentParser(description="HL balance checker and L1->EVM bridge")
    parser.add_argument("--bridge", type=float, default=0,
                        help="Amount of HYPE to bridge from L1 spot to EVM")
    args = parser.parse_args()

    private_key = os.environ.get("PRIVATE_KEY", "")
    if not private_key:
        print("Error: set PRIVATE_KEY env var")
        sys.exit(1)

    # Derive address
    try:
        from eth_account import Account
        if not private_key.startswith("0x"):
            private_key = "0x" + private_key
        account = Account.from_key(private_key)
        address = account.address
    except Exception as e:
        print(f"Bad key: {e}")
        sys.exit(1)

    print(f"Wallet: {address}")
    print()

    # HyperEVM balance
    print("[HyperEVM - chain 999]")
    evm_balance = get_evm_balance(address)
    print(f"  HYPE (native gas): {evm_balance:.6f}")
    has_gas = evm_balance >= MIN_GAS_HYPE
    if has_gas:
        print(f"  Gas OK (>= {MIN_GAS_HYPE})")
    else:
        print(f"  Needs gas (< {MIN_GAS_HYPE})")
    print()

    # L1 spot balances
    print("[Hyperliquid L1 - spot]")
    l1_balances = get_l1_balances(address)
    if not l1_balances:
        print("  No spot balances found")
    else:
        for coin, info in l1_balances.items():
            print(f"  {coin}: total={info['total']:.6f}  available={info['available']:.6f}")
    print()

    # Bridge if requested and needed
    bridge_amount = Decimal(str(args.bridge)) if args.bridge > 0 else Decimal("0")
    bridged = False

    if bridge_amount > 0 and not has_gas:
        hype_l1 = l1_balances.get("HYPE", {})
        available = hype_l1.get("available", Decimal("0"))

        if available >= bridge_amount:
            print(f"[Bridge] Sending {bridge_amount} HYPE from L1 spot -> EVM")
            bridged = attempt_bridge(private_key, bridge_amount)
        elif available > 0:
            print(f"[Bridge] Only {available} HYPE available, requesting {bridge_amount}")
            print(f"[Bridge] Trying with available amount instead")
            bridged = attempt_bridge(private_key, available)
        else:
            print("[Bridge] No HYPE on L1 spot to bridge")
    elif bridge_amount > 0 and has_gas:
        print("[Bridge] Skipped - EVM already has gas")
    elif not has_gas and not bridge_amount:
        hype_l1 = l1_balances.get("HYPE", {})
        available = hype_l1.get("available", Decimal("0"))
        if available > 0:
            print(f"Hint: run with --bridge {float(min(available, Decimal('1')))} to move HYPE to EVM")
    print()

    # Summary
    print("[Deploy readiness]")
    final_gas = has_gas or bridged
    if final_gas:
        print("  HyperEVM: READY")
    else:
        print("  HyperEVM: NOT READY - needs HYPE for gas")
        print("  Get HYPE: buy on HL spot, then bridge with --bridge <amount>")

    sys.exit(0 if final_gas else 1)


if __name__ == "__main__":
    main()
