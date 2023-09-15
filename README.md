# Smartcontracts

## Instructions
In the root directory:
- Install dependencies :`npm install` 
- Rename .env.sample file to .env and fill the missing values.
- To compile truffle project: `npx hardhat compile`

##### Deploy ERC721 NFT Contract 
1. Testnet: ` npx hardhat run --network testnet scripts/1_deploy_erc721NftContract.js`
2. Mainnet: `npx hardhat run --network mainnet scripts/1_deploy_erc721NftContract.js`

##### Deploy Marketplace Contract 
1. Testnet: ` npx hardhat run --network testnet scripts/2_deploy_NftMarketplaceContract.js`
2. Mainnet: `npx hardhat run --network mainnet scripts/2_deploy_NftMarketplaceContract.js`