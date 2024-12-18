import { ethers } from "hardhat";

async function main() {
  const feeWallet = "0x2cf82658365E6e175608dcd1AF60B0285e50D909";
  const pierMarketplace = await ethers.deployContract("PierMarketplace", [feeWallet]);
  await pierMarketplace.waitForDeployment();
  console.log(
    `PierMarketplace deployed to ${pierMarketplace.target}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
