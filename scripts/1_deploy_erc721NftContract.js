// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.

async function main() {

  const nftName = process.env.NFT_NAME
  const nftSymbol = process.env.NFT_SYMBOL
  const baseTokenURI = process.env.NFT_BASE_URI
  const rootAdmin = process.env.NFT_ADMIN_ADDRESS

  const Erc721NftContract = await ethers.getContractFactory("Erc721NftContract");
  const deployedContract = await Erc721NftContract.deploy(nftName, nftSymbol, baseTokenURI, rootAdmin);

  console.log(
    `Erc721NftContract address: ${deployedContract.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
