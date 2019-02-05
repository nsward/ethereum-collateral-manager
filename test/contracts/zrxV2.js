const TruffleContract = require("truffle-contract");

let ExchangeV2JSON = require("@0xproject/migrations/artifacts/2.0.0-testnet/Exchange.json");
let ProxyV2JSON = require("@0xproject/migrations/artifacts/2.0.0-testnet/ERC20Proxy.json");
let ZrxTokenJSON = require("@0xproject/migrations/artifacts/2.0.0-testnet/ZRXToken.json");

ExchangeV2JSON.bytecode = ExchangeV2JSON.compilerOutput.evm.bytecode.object;
ExchangeV2JSON.deployedBytecode = ExchangeV2JSON.compilerOutput.evm.deployedBytecode.object;
ExchangeV2JSON.sourceMap = ExchangeV2JSON.compilerOutput.evm.bytecode.sourceMap;
ExchangeV2JSON.deployedSourceMap = ExchangeV2JSON.compilerOutput.evm.deployedBytecode.sourceMap;
ExchangeV2JSON.abi = ExchangeV2JSON.compilerOutput.abi;

ProxyV2JSON.bytecode = ProxyV2JSON.compilerOutput.evm.bytecode.object;
ProxyV2JSON.deployedBytecode = ProxyV2JSON.compilerOutput.evm.deployedBytecode.object;
ProxyV2JSON.sourceMap = ProxyV2JSON.compilerOutput.evm.bytecode.sourceMap;
ProxyV2JSON.deployedSourceMap = ProxyV2JSON.compilerOutput.evm.deployedBytecode.sourceMap;
ProxyV2JSON.abi = ProxyV2JSON.compilerOutput.abi;

ZrxTokenJSON.bytecode = ZrxTokenJSON.compilerOutput.evm.bytecode.object;
ZrxTokenJSON.deployedBytecode = ZrxTokenJSON.compilerOutput.evm.deployedBytecode.object;
ZrxTokenJSON.sourceMap = ZrxTokenJSON.compilerOutput.evm.bytecode.sourceMap;
ZrxTokenJSON.deployedSourceMap = ZrxTokenJSON.compilerOutput.evm.deployedBytecode.sourceMap;
ZrxTokenJSON.abi = ZrxTokenJSON.compilerOutput.abi;

let ZrxExchangeContract = TruffleContract(ExchangeV2JSON);
let ZrxProxyContract = TruffleContract(ProxyV2JSON);
let ZrxTokenContract = TruffleContract(ZrxTokenJSON);

module.exports = {
  ZrxExchangeContract,
  ZrxProxyContract,
  ZrxTokenContract,
  ExchangeV2JSON,
  ProxyV2JSON,
  ZrxTokenJSON
};