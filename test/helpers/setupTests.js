// System contracts
const VatContract = artifacts.require("../contracts/Vat");
const BrokerContract = artifacts.require("../contracts/Broker");
const ExecContract = artifacts.require("../contracts/Exec");
const VaultContract = artifacts.require("../contracts/Vault");
const ProxyContract = artifacts.require("../contracts/Proxy");
const SpotterContract = artifacts.require("../contracts/Spotter");
const LiquidatorContract = artifacts.require("../contracts/Liquidator.sol");
const ZrxWrapperContract = artifacts.require("../contracts/ZrxExchangeWrapper");

// External contracts
const OracleContract = artifacts.require("../contracts/Oracle");
const TokenContract = artifacts.require("../contracts/ERC20Mintable");
const { 
  ZrxExchangeContract, 
  ZrxProxyContract 
} = require("../contracts/zrxV2");

// Utils
const { assetDataUtils } = require('@0xproject/order-utils');
const { bn, k256, hex } = require('./web3Helpers');

async function deploySystem(owner, user, minter, price0, mintAmt) {

  // Main contracts
  let vat = await VatContract.new({from:owner});
  let proxy = await ProxyContract.new({from:owner});
  let vault = await VaultContract.new(proxy.address, {from:owner});
  let exec = await ExecContract.new(vat.address, vault.address, {from:owner});
  let broker = await BrokerContract.new(vat.address, vault.address, {from:owner});
  let liquidator = await LiquidatorContract.new(vat.address, broker.address, {from:owner});

  // prepare zero ex contracts for deployment
  const sendDefaults = {from:owner, gas: 6721975, gasPrice: 100000000000}
  ZrxExchangeContract.setProvider(web3.currentProvider);
  ZrxExchangeContract.class_defaults = sendDefaults;
  ZrxProxyContract.setProvider(web3.currentProvider);
  ZrxProxyContract.class_defaults = sendDefaults;

  // Tokens
  let owedGem = await TokenContract.new({from:minter});
  let heldGem = await TokenContract.new({from:minter});
  let zrxGem = await TokenContract.new({from:minter});
  await owedGem.mint(user, bn(mintAmt), {from:minter}); // mint due tokens
  await heldGem.mint(user, bn(mintAmt), {from:minter}); // mint trade tokens
  await zrxGem.mint(user,  bn(mintAmt), {from:minter}); // mint zrx tokens

  // Zero Ex Exchange
  const zrxAssetData = assetDataUtils.encodeERC20AssetData(zrxGem.address);
  let zrxExchange = await ZrxExchangeContract.new(zrxAssetData, {from:owner});
  let zrxProxy = await ZrxProxyContract.new({from:owner});
  // register exchange and proxy with each other
  await zrxProxy.addAuthorizedAddress(zrxExchange.address);
  await zrxExchange.registerAssetProxy(zrxProxy.address);

  // Oracle. This will ultimately be MakerDAO medianizer contract
  let oracle = await OracleContract.new(price0, true, {from:owner});

  // Zero Ex Exchange Wrapper
  let wrapper = await ZrxWrapperContract.new(
    vault.address, 
    proxy.address,
    zrxExchange.address, 
    zrxProxy.address, 
    zrxGem.address, 
    {from:owner}
  );

  // The spotter. Takes the medianizer value for pair and pushes it into the Chief
  let pairKey = k256(owedGem.address, heldGem.address);
  let spotter = await SpotterContract.new(broker.address, oracle.address, pairKey, {from:owner});

  // Authorize contracts to interact with each other
  vat.addAuth(exec.address, {from:owner});
  vat.addAuth(broker.address, {from:owner});
  vat.addAuth(liquidator.address, {from:owner});
  vault.addAuth(exec.address, {from:owner});
  vault.addAuth(broker.address, {from:owner});
  broker.addAuth(spotter.address, {from:owner});
  broker.file(hex("wrapper"), wrapper.address, 1, {from:owner});
  proxy.addAuth(vault.address, {from:owner});
  proxy.addAuth(wrapper.address, {from:owner});
  wrapper.addAuth(broker.address, {from:owner});

  // approve trading pair
  exec.file(hex("validTokenPair"), pairKey, 1, {from:owner});

  return { 
    vat,
    proxy,
    vault,
    exec,
    broker,
    liquidator,
    owedGem,
    heldGem,
    zrxGem,
    zrxExchange,
    zrxProxy,
    oracle,
    wrapper,
    spotter,
    pairKey
  };
}

module.exports = { deploySystem }


