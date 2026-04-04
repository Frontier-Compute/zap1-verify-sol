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
};

const ABI = [
  "function verifyProofStateless(bytes32 leafHash, bytes32[] calldata siblings, uint256 positions, bytes32 expectedRoot) external view returns (bool)",
  "function isAnchorRegistered(bytes32 root) external view returns (bool, uint64)",
];

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

    const leafHash = "0x" + document.getElementById("leafHash").value.trim();
    const siblingsRaw = document.getElementById("siblings").value.trim().split("\n").filter(Boolean);
    const siblings = siblingsRaw.map(s => "0x" + s.trim());
    const positions = parseInt(document.getElementById("positions").value) || 0;
    const root = "0x" + document.getElementById("root").value.trim();

    const provider = new ethers.providers.JsonRpcProvider(deployment.rpc);
    const contract = new ethers.Contract(deployment.address, ABI, provider);

    // Check anchor registration
    const [registered, zcashHeight] = await contract.isAnchorRegistered(root);

    // Verify proof
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
