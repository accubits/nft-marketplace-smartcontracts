// require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ethers");
require("dotenv").config();

const MAINNET_RPC_URL = process.env.RPC_URL_MAINNET;
const MAINNET_CHAIN_ID = process.env.CHAIN_ID_MAINNET;

const TESTNET_RPC_URL = process.env.RPC_URL_TESTNET;
const TESTNET_CHAIN_ID = process.env.CHAIN_ID_TESTNET;

const ADMIN_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    testnet: {
      url: TESTNET_RPC_URL,
      accounts: [ADMIN_PRIVATE_KEY],
      chainId: Number(TESTNET_CHAIN_ID)
    },
    mainnet: {
      url: MAINNET_RPC_URL,
      accounts: [ADMIN_PRIVATE_KEY],
      chainId: Number(MAINNET_CHAIN_ID)
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY
  }
};

