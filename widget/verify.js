const CONTRACTS = {
  sepolia: {
    address: "0x3fD65055A8dC772C848E7F227CE458803005C87F",
    rpc: "https://ethereum-sepolia-rpc.publicnode.com",
    chainId: 11155111,
  },
  arbitrum: {
    address: "0x9D0B26010C9a7a2a8509Fd1a3407B741d9C10e3a",
    rpc: "https://arb1.arbitrum.io/rpc",
    chainId: 42161,
  },
  base: {
    address: "0x3fD65055A8dC772C848E7F227CE458803005C87F",
    rpc: "https://mainnet.base.org",
    chainId: 8453,
  },
  hyperliquid: {
    address: "0x3fD65055A8dC772C848E7F227CE458803005C87F",
    rpc: "https://rpc.hyperliquid.xyz/evm",
    chainId: 999,
  },
  near: {
    programId: "zap1anchor.testnet",
    rpc: "https://rpc.testnet.near.org",
    type: "near",
  },
};

const ABI = [
  "function verifyProofStateless(bytes32 leafHash, bytes32[] calldata siblings, uint256 positions, bytes32 expectedRoot) external view returns (bool)",
  "function isAnchorRegistered(bytes32 root) external view returns (bool, uint64)",
];

function hexToBytes(hex) {
  const clean = hex.replace(/^0x/, "");
  const bytes = [];
  for (let i = 0; i < clean.length; i += 2) {
    bytes.push(parseInt(clean.substr(i, 2), 16));
  }
  return bytes;
}

async function verifyNear(deployment, root) {
  const rootBytes = hexToBytes(root);
  const args = JSON.stringify({ root: rootBytes });
  const argsB64 = btoa(args);
  const resp = await fetch(deployment.rpc, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "query",
      params: {
        request_type: "call_function",
        finality: "final",
        account_id: deployment.programId,
        method_name: "is_anchor_registered",
        args_base64: argsB64,
      },
    }),
  });
  const json = await resp.json();
  if (json.error) throw new Error(json.error.message || JSON.stringify(json.error));
  const resultBytes = json.result.result;
  const resultStr = String.fromCharCode(...resultBytes);
  return JSON.parse(resultStr);
}

async function verify() {
  const el = document.getElementById("result");
  el.style.display = "block";
  el.className = "";
  el.textContent = "Verifying...";

  try {
    const chain = document.getElementById("chain").value;
    const deployment = CONTRACTS[chain];
    if (!deployment) {
      el.textContent = "Chain not deployed yet.";
      el.className = "fail";
      return;
    }

    const root = "0x" + document.getElementById("root").value.trim();

    if (deployment.type === "near") {
      const [registered, zcashHeight] = await verifyNear(deployment, root);

      let output = "";
      output += registered ? "ANCHOR REGISTERED\n\n" : "ANCHOR NOT FOUND\n\n";
      output += "Root: " + root + "\n";
      output += "Anchor registered: " + registered + "\n";
      if (registered) output += "Zcash height: " + zcashHeight + "\n";
      output += "Chain: " + chain + "\n";
      output += "Contract: " + deployment.programId + "\n";
      output += "\nNote: NEAR verifies anchor registration only. Proof verification runs on EVM chains.\n";

      el.textContent = output;
      el.className = registered ? "ok" : "fail";
      return;
    }

    const leafHash = "0x" + document.getElementById("leafHash").value.trim();
    const siblingsRaw = document.getElementById("siblings").value.trim().split("\n").filter(Boolean);
    const siblings = siblingsRaw.map(s => "0x" + s.trim());
    const positions = parseInt(document.getElementById("positions").value) || 0;

    const provider = new ethers.providers.JsonRpcProvider(deployment.rpc);
    const contract = new ethers.Contract(deployment.address, ABI, provider);

    const [registered, zcashHeight] = await contract.isAnchorRegistered(root);
    const valid = await contract.verifyProofStateless(leafHash, siblings, positions, root);

    let output = "";
    output += valid ? "PROOF VALID\n\n" : "PROOF INVALID\n\n";
    output += "Leaf: " + leafHash + "\n";
    output += "Root: " + root + "\n";
    output += "Anchor registered: " + registered + "\n";
    if (registered) output += "Zcash height: " + zcashHeight.toString() + "\n";
    output += "Chain: " + chain + "\n";
    output += "Contract: " + deployment.address + "\n";

    el.textContent = output;
    el.className = valid ? "ok" : "fail";
  } catch (err) {
    el.textContent = "Error: " + (err.message || err);
    el.className = "fail";
  }
}
