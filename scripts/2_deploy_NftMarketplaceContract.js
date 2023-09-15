// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.

async function main() {
  
  const rootAdmin = process.env.MARKETPLACE_ADMIN_ADDRESS;
  const PlatformFeePercentage = process.env.PLATFORM_FEE_PERCENTAGE;
  const PlatformFeeReceiver = process.env.PLATFORM_FEE_RECEIVER;

  const MarketplaceContract = await ethers.getContractFactory("NFTMarketPlace");
  const deployedContract = await MarketplaceContract.deploy([PlatformFeeReceiver, PlatformFeePercentage], rootAdmin);

  console.log(
    `MarketplaceContract address: ${deployedContract.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
