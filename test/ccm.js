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
} = require("./contracts/zrxV2");

// Utils
const { assetDataUtils } = require("@0xproject/order-utils");
const { bn, k256, ethToWei, weiToEth, hex } = require("./helpers/helpers");
const BigNum = require('bignumber.js'); // useful bignumber library
const BN = require('bn.js');  // bad bignumber library that web3.utils returns
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));

//TODO: https://github.com/JoinColony/colonyNetwork/blob/develop/test/colony.js

contract("CCM System", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const owner = accounts[0];    // owner of the system contracts
  const admin = accounts[1];    // simulates the admin contract
  const user = accounts[2];     // owner of the collateral position
  const peer = accounts[3];     // recipient of payments
  const keeper = accounts[4];    // keeper / liquidator / biter
  const minter = accounts[5];   // can mint tokens so we have some to play with
  const anyone = accounts[6];   // anyone. represents an outside bad actor / curious guy
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000';

  // Value contract constructor defaults
  const price0 = new BN(ethToWei(100)); // 100 gem / 1 due token
  const has = true;
  
  // system contracts
  let vat;
  let broker;
  let exec;
  let vault;
  let liquidator;
  let proxy;
  let spotter;
  let wrapper;

  // external contracts and contract addresses
  let zrxExchange;
  let zrxProxy;
  let oracle;
  let owedGem;  // owed token contract
  let heldGem;  // held token contract
  let zrxGem;   // ZRX token contract
  let _owed;    // owed token contract address
  let _held;    // held token contract address
  let _zrx;     // ZRX token contract address

  // mapping keys
  let pairKey;                      // keccak256(_owed, _held)
  let acctKey = k256(admin, user);  // keccak256(admin, user)

  const sendDefaults = {from:owner, gas: 6721975, gasPrice: 100000000000}
  ZrxExchangeContract.setProvider(web3.currentProvider);
  ZrxExchangeContract.class_defaults = sendDefaults;
  ZrxProxyContract.setProvider(web3.currentProvider);
  ZrxProxyContract.class_defaults = sendDefaults;


  beforeEach("Instantiate Contracts", async() => {
    // Main contracts
    vat = await VatContract.new({from:owner});
    proxy = await ProxyContract.new({from:owner});
    vault = await VaultContract.new(proxy.address, {from:owner});
    exec = await ExecContract.new(vat.address, vault.address, {from:owner});
    broker = await BrokerContract.new(vat.address, vault.address, {from:owner});
    liquidator = await LiquidatorContract.new(vat.address, broker.address, {from:owner});

    // Tokens
    owedGem = await TokenContract.new({from:minter});
    heldGem = await TokenContract.new({from:minter});
    zrxGem = await TokenContract.new({from:minter});
    await owedGem.mint(user, new BN(ethToWei(100000)), {from:minter});  // mint due tokens
    await heldGem.mint(user, new BN(ethToWei(100000)), {from:minter});  // mint trade tokens
    await zrxGem.mint(user, new BN(ethToWei(100000)), {from:minter});   // mint zrx tokens
    _owed = owedGem.address;
    _held = heldGem.address;
    _zrx = zrxGem.address;

    // Zero Ex Exchange
    const zrxAssetData = assetDataUtils.encodeERC20AssetData(_zrx);
    zrxExchange = await ZrxExchangeContract.new(zrxAssetData, {from:owner});
    zrxProxy = await ZrxProxyContract.new({from:owner});
    // register exchange and proxy with each other
    await zrxProxy.addAuthorizedAddress(zrxExchange.address);
    await zrxExchange.registerAssetProxy(zrxProxy.address);

    // Oracle. This will ultimately be MakerDAO medianizer contract
    oracle = await OracleContract.new(price0, has, {from:owner});

    // Zero Ex Exchange Wrapper
    wrapper = await ZrxWrapperContract.new(
      vault.address, 
      zrxExchange.address, 
      zrxProxy.address, 
      _zrx, 
      {from:owner}
    );

    // The spotter. Takes the medianizer value for pair and pushes it into the Chief
    pairKey = k256(_owed, _held);
    spotter = await SpotterContract.new(broker.address, oracle.address, pairKey, {from:owner});

    // Authorize contracts to interact with each other
    vat.addAuth(exec.address, {from:owner});
    vat.addAuth(broker.address, {from:owner});
    vat.addAuth(liquidator.address, {from:owner});
    vault.addAuth(exec.address, {from:owner});
    vault.addAuth(broker.address, {from:owner});
    broker.addAuth(spotter.address, {from:owner});
    broker.file(hex("wrapper"), wrapper.address, 1);
    proxy.addAuth(vault.address, {from:owner});
    wrapper.addAuth(broker.address, {from:owner});

    // approve trading pair
    exec.file(hex("validTokenPair"), pairKey, 1);

//     // approve trading pair and set spotter address
//     await chief.methods['file(bytes32,bytes32,bool)'](pairKey, hex("use"), true);
//     await chief.methods['file(bytes32,bytes32,address)'](pairKey, hex("spotter"), spotter.address);
  });


  it("Check contract constructors and auths", async() => {

    // Vat
    expect(await vat.owner()).to.equal(owner, "Vat owner incorrect");
    expect(await vat.auths(owner)).to.eq.BN(0, "Vat owner should not be auth");
    expect(await vat.auths(broker.address)).to.eq.BN(1, "Vat broker not auth");
    expect(await vat.auths(liquidator.address)).to.eq.BN(1, "Vat liquidator not auth");
    expect(await vat.auths(exec.address)).to.eq.BN(1, "Vat exec not address");

    // Broker
    expect(await broker.owner()).to.equal(owner, "Broker owner incorrect");
    expect(await broker.auths(spotter.address)).to.eq.BN(1, "Broker spotter not auth");
    expect(await broker.vault()).to.equal(vault.address, "Broker vault address incorrect");
    expect(await broker.vat()).to.equal(vat.address, "Broker vat address incorrect");
    expect(await broker.wrappers(wrapper.address)).to.eq.BN(1, "Broker wrapper not added");

    // Exec
    expect(await exec.owner()).to.equal(owner, "Exec owner incorrect");
    expect(await exec.vault()).to.equal(vault.address, "Exec vault address incorrect");
    expect(await exec.vat()).to.equal(vat.address, "Exec vat address incorrect");
    expect(await exec.validTokenPairs(pairKey)).to.eq.BN(1, "Exec token pair not added");

    // Liquidator
    expect(await liquidator.owner()).to.equal(owner, "Liquidator owner incorrect");
    expect(await liquidator.vat()).to.equal(vat.address, "Liquidator vat address incorrect");
    expect(await liquidator.broker()).to.equal(broker.address, "Liquidator broker address incorrect");

    // Vault
    expect(await vault.owner()).to.equal(owner, "Vault owner incorrect");
    expect(await vault.proxy()).to.equal(proxy.address, "Vault proxy address incorrect");
    expect(await vault.auths(broker.address)).to.eq.BN(1, "Vault broker not auth");
    expect(await vault.auths(exec.address)).to.eq.BN(1, "Vault exec not auth");

    // Proxy
    expect(await proxy.owner()).to.equal(owner, "Proxy owner address incorrect");
    expect(await proxy.auths(vault.address)).to.eq.BN(1, "Proxy vault not auth");

    // Spotter
    expect(await spotter.owner()).to.equal(owner, "Spotter owner incorrect");
    expect(await spotter.oracle()).to.equal(oracle.address, "Spotter oracle address incorrect");
    expect(await spotter.broker()).to.equal(broker.address, "Spotter broker address incorrect");
    expect(await spotter.pair()).to.equal(pairKey, "Spotter pair key incorrect");

    // Wrapper
    expect(await wrapper.owner()).to.equal(owner, "Wrapper owner incorerct");
    expect(await wrapper.auths(broker.address)).to.eq.BN(1, "Wrapper broker not auth");
    expect(await wrapper.vault()).to.equal(vault.address, "Wrapper vault address incorrect");
    expect(await wrapper.exchange()).to.equal(zrxExchange.address, "Wrapper exchange address incorrect");
    expect(await wrapper.zrxProxy()).to.equal(zrxProxy.address, "Wrapper proxy address incorrect");
    expect(await wrapper.zrx()).to.equal(_zrx, "Wrapper ZRX token address incorrect");
    
    // Oracle
    const peek = await oracle.peek();
    expect(bn(peek[0])).to.eq.BN(price0, "Oracle val incorrect");
    expect(peek[1]).to.equal(has, "Oracle has incorrect");
    expect(await oracle.owner()).to.equal(owner, "Oracle owner address incorrect");

    // Tokens
    expect(await owedGem.isMinter(minter), "Due minter incorrect.").to.be.true;
    expect(await heldGem.isMinter(minter), "Gem minter incorrect.").to.be.true;
    
  });

  it("Check stuff", async() => {
    
  });


//   it("Check Chief with no mama params", async() => {
//     const dueTab = ethToWei(10);  // 10 eth
//     const callTime = 86400;       // 1 day
//     //const biteLimit = 1.5;
//     //const biteFee = 0;
//     //const lockAmt = dueTab * biteLimit; 

//     await dueToken.approve(proxy.address, dueTab, {from:user});  // approve proxy

//     // allow tester contract to take dueTab from user
//     await chief.setAllowance(exec, user, dueTab, {from:user});
//     // Open an account without mama params
//     const openTx = await testc.open(dueTab, callTime, user, _due, false);
//     const lastAccrual = (await web3.eth.getBlock(openTx.receipt.blockNumber)).timestamp;

//     let account = {
//       'exec': exec,  
//       'dueToken': _due, 
//       'tradeToken': ZERO_ADDR,
//       'lastAccrual': lastAccrual,
//       'dueTab': dueTab,
//       'dueBalance': dueTab,
//       'tradeBalance': 0,
//       'callTime': callTime,
//       'callTab': 0,
//       'useExecParams': false,
//       'state': 0,
//       'user': user
//     }
    
//     await checkAcct(chief, account);  // Check that the account was opened correctly

//     //await chief.lock(exec, _due, )

//   });

//   it("Check safe function", async() => {
//     const dueTab = ethToWei(10);        // 10 due tokens
//     const tradeBalance = ethToWei(5);   // 5 tradeTokens
//     const tax = 0;
//     const ten = new BigNum(10);
//     const biteLimit = (new BigNum(1.2)).times(ten.pow(27)).toFixed(0);
//     const biteFee = (new BigNum(1.1)).times(ten.pow(27)).toFixed(0)
//     const callTime = 86400;             // 1 day
//     console.log("biteLimit: ", biteLimit.toString())
//     await dueToken.approve(proxy.address, dueTab, {from:user});  // approve proxy
//     await tradeToken.approve(proxy.address, tradeBalance, {from:user});
//     await chief.setAllowance(exec, user, dueTab, {from:user});
//     await testc.open(dueTab, callTime, user, _due, false);
//     await testc.addAccountAsset(tax, biteLimit, biteFee, _trade, user);
//     // console.log("account.tokens[tradeToken]: ", await chief.accountAsset(exec, user, _trade));
//     await chief.lock(accountKey, _trade, tradeBalance, {from:user});

//     const safe = await chief.safe(accountKey);
//     console.log("chief.safe(): ", safe);
//     // console.log("chief.safe() credit: ", safe[0].toString());
//     // console.log("chief.safe() debit:  ", safe[1].toString());

//     console.log("acct uints: ", await chief.accountUints(exec, user));
//   });


//   it("Check oracle stuff", async() => {
//     const dueTab = ethToWei(10);  // 10 eth
//     const callTime = 86400;       // 1 day

//     // Check that scout correctly updates trading pair val
//     await spotter.poke();
//     expect((await chief.tokenPairs(pairKey)).spotPrice).to.eq.BN(price0);

//     // Update medianizer value and check scout functionality
//     // const newVal = val0 * 2;
//     // console.log("is BN?: ", web3.utils.isBN(newVal));
//     // await value.methods['file(bytes32,uint256)'](hex("val"), bn(newVal));
//     // await scout.poke();
//     // console.log("contract val: ", (await chief.pairs(pairKey)).val);
//     // console.log("newVal: ", newVal)
//     // expect((await chief.pairs(pairKey)).val).to.eq.BN(newVal);
//     await dueToken.approve(proxy.address, dueTab, {from:user});  // approve proxy
//     await chief.setAllowance(exec, user, dueTab, {from:user});
//     await testc.open(dueTab, callTime, user, _due, false);

//     // console.log("exchange rate: ", (await chief.tokenPairs(pairKey)).spotPrice.toString()); 
//     // console.log("acctKey: ", accountKey);
//     // console.log("cAcctKey: ", await chief.foo(who, user))
//     // const safe = await chief.safe(accountKey);
//     // console.log("safe()[0]: ", safe[0].toString());
//     // console.log("safe()[1]: ", safe[1].toString());
//     // console.log("safe: ", safe.toString());

//     // console.log(web3.utils.toBN('0000000000000000000000000000000000000000000000008cb5a37afbc6ff00').toString());
//     // console.log(web3.utils.toBN('00000000000000000000000000000000000000000000000700df1485a4b70000').toString());
//   });

});

// // TODO: check order too
// // NOTE: takes _who, _due, _gem, and user from global variables
// // async function checkAcct(chief, acct      who, user, _due, _gem, era, tab, bal, own, zen, ohm, state, mom, opt) {
// async function checkAcct(chief, acct) {
//   const acctUints = await chief.accountUints(acct.exec, acct.user);
//   const acctBools = await chief.accountBools(acct.exec, acct.user);
//   const acctState = await chief.accountState(acct.exec, acct.user);
//   const acctAddresses = await chief.accountAddresses(acct.exec, acct.user);

//   expect(acctUints.lastAccrual).to.eq.BN(acct.lastAccrual, "Acct era wrong");
//   expect(acctUints.dueTab).to.eq.BN(acct.dueTab, "Acct tab wrong");
//   expect(acctUints.dueBalance).to.eq.BN(acct.dueBalance, "Acct bal wrong");
//   expect(acctUints.tradeBalance).to.eq.BN(acct.tradeBalance, "Acct own wrong");
//   expect(acctUints.callTime).to.eq.BN(acct.callTime, "Acct zen wrong");
//   expect(acctUints.callTab).to.eq.BN(acct.callTab, "Acct ohm wrong");
//   expect(acctState).to.eq.BN(acct.state, "Acct state wrong");
//   expect(acctBools).to.equal(acct.useExecParams, "Acct mom wrong");
//   expect(acctAddresses.exec).to.equal(acct.exec, "Acct who wrong");
//   expect(acctAddresses.dueToken).to.equal(acct.dueToken, "Acct due wrong");
//   expect(acctAddresses.tradeToken).to.equal(acct.tradeToken, "Acct gem wrong");
// }

// // becuase web3 utils uses bn.js instead of bignumber.js
// function bn(num) {
//   return web3.utils.toBN(num);
// }

// function k256(addr1, addr2) {
//   return web3.utils.soliditySha3(
//     {type: 'address', value: addr1},
//     {type: 'address', value: addr2}
//   );
// }

// function ethToWei(val) {
//   return web3.utils.toWei(val.toString(), 'ether');
// }

// function weiToEth(val) {
//   return web3.utils.fromWei(val.toString(), 'ether');
// }

// function hex(val) {
//   return web3.utils.toHex(val);
// }