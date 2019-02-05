// utils
const { bn, ethToWei } = require('./helpers/testHelpers');
const { deploySystem } = require("./helpers/deploy");

// modules
const BigNum = require('bignumber.js'); // useful bignumber library
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));


contract("CCM System deployment", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const owner = accounts[0];    // owner of the system contracts
  const user = accounts[1];     // owner of the collateral position
  const minter = accounts[2];   // can mint tokens so we have some to play with

  // Value contract constructor defaults
  const price0 = new BigNum(ethToWei(100)); // 100 gem / 1 due token
  const mintAmt = new BigNum(ethToWei(100000));
  
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
  let owedGem;      // owed token contract
  let heldGem;      // held token contract
  let zrxGem;       // ZRX token contract

  // mapping keys
  let pairKey;      // keccak256(_owedGem, _heldGem)


  beforeEach("Instantiate Contracts", async() => {
    contracts = {
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
    } = await deploySystem(owner, user, minter, price0, mintAmt);

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
    expect(await wrapper.zrx()).to.equal(zrxGem.address, "Wrapper ZRX token address incorrect");
    
    // Oracle
    const peek = await oracle.peek();
    expect(bn(peek[0])).to.eq.BN(bn(price0), "Oracle val incorrect");
    expect(peek[1]).to.equal(true, "Oracle has incorrect");
    expect(await oracle.owner()).to.equal(owner, "Oracle owner address incorrect");

    // Tokens
    expect(await owedGem.isMinter(minter), "Owed gem minter incorrect.").to.be.true;
    expect(await heldGem.isMinter(minter), "Held gem minter incorrect.").to.be.true;
    expect(await zrxGem.isMinter(minter), "Zrx Gem minter incorrect.").to.be.true;
    
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