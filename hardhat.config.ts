import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
const dotenv = require('dotenv');

dotenv.config()

const privateKey = process.env.PRIVATE_KEY ? process.env.PRIVATE_KEY : "";

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    ftmtest: {
      url: "https://rpc.testnet.fantom.network",
      accounts: [privateKey]
    },
    eth: {
      url: "https://rpc.mevblocker.io",
      accounts: [privateKey]
    },
    sepolia: {
      url: "https://ethereum-sepolia.publicnode.com",
      accounts: [privateKey]
    },
    optimismmain: {
      url: "https://opt-mainnet.g.alchemy.com/v2/nRz4mGrUbXWEm_tTKlIFbxcn3KCqIO17",
      accounts: [privateKey]
    },
    ethereummain: {
      url: "https://eth-mainnet.g.alchemy.com/v2/xRpnmvup4LCr2mL9lNqqpKnHQJepfeSc",
      accounts: [privateKey]
    },
    basemain: {
      url: "https://base-mainnet.g.alchemy.com/v2/mWNKTlIEj3AujVAvLytXLenxbEGhlhag",
      accounts: [privateKey],
    },
    scrollmain: {
      url: "https://1rpc.io/scroll",
      accounts: [privateKey],
    },
    linea: {
      url: "https://linea.drpc.org",
      accounts: [privateKey],
    },
    avaxmain: {
      url: "https://avalanche.drpc.org",
      accounts: [privateKey]
    },
    avaxtest: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: [privateKey]
    }
  }
};

export default config;
