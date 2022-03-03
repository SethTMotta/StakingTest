const fs = require('fs');
const mnemonic = fs.readFileSync(".secret").toString().trim();
const bscscanApiKey = fs.readFileSync(".bscscanApiKey").toString().trim();

const HDWalletProvider = require("truffle-hdwallet-provider");

module.exports = {
  networks: {
    develop: {
      provider: () => {
        const wallet = new HDWalletProvider(mnemonic, 'http://127.0.0.1:8545', 0, 2, false)
        return wallet
      },
      port: 8545,
      network_id: 97,

    },
    testnet: {
      provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545`),
      network_id: 97,
      confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true
    },
    bsc: {
      provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed.binance.org/`),
      network_id: 56,
      confirmations: 5,
      timeoutBlocks: 200,
      skipDryRun: true
    },
  },
  mocha: { },
  plugins: ['truffle-plugin-verify'],
  api_keys: { bscscan: bscscanApiKey, },
  compilers: {
    solc: {
      version: "0.8.4",
      docker: false,
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
        evmVersion: "istanbul"
      }
    },
  },
};
