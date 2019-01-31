const ChiefContract = artifacts.require('../contracts/Chief');
const VaultContract = artifacts.require('../contracts/Vault');
const ProxyContract = artifacts.require('../contracts/Proxy');
const SpotterContract = artifacts.require("../contracts/Spotter.sol");
const OracleContract = artifacts.require("../contracts/Oracle.sol");
const TesterContract = artifacts.require('../contracts/testing/Tester');
const TokenContract = artifacts.require("openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol");

const BigNum = require('bignumber.js');
const BN = require('bn.js');  // bad bignumber library that web3.utils returns
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));

//TODO: https://github.com/JoinColony/colonyNetwork/blob/develop/test/colony.js

contract("Chief", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const boss = accounts[0];     // owner of the system contracts
  const user = accounts[1];     // owner of the collateral position
  const peer = accounts[2];     // recipient of payments
  const jerk = accounts[3];     // anyone. represents an outside bad actor / curious guy
  const testBoss = accounts[4]; // owner of the testc.
  const minter = accounts[5];   // can mint tokens so we have some to play with
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

  // Value contract constructor defaults
  const price0 = new BN(ethToWei(100)); // 100 gem / 1 due token
  const has = true;
  
  // contracts
  let chief;
  let vault;
  let proxy;
  let spotter;
  let oracle;
  let testc;      // test contract. Simulates the collateral manager
  let exec;       // managing contract address
  let dueToken;   // due token contract
  let tradeToken; // trade token contract
  let _due;       // due token contract address
  let _trade;     // trade token contract address

  let pairKey;    // keccak256(_due, _gem)
  let accountKey;

  beforeEach("Instantiate Contracts", async() => {
    // Main contracts
    vault = await VaultContract.new({from:boss});
    proxy = await ProxyContract.new(vault.address, {from:boss});
    chief = await ChiefContract.new(vault.address, {from:boss});

    // Set vault auth addresses
    await vault.file(hex("chief"), chief.address);
    await vault.file(hex("proxy"), proxy.address);

    // Tokens
    dueToken = await TokenContract.new({from:minter});
    tradeToken = await TokenContract.new({from:minter});
    await dueToken.mint(user, new BN(ethToWei(100000)), {from:minter}); // mint due tokens
    await tradeToken.mint(user, new BN(ethToWei(100000)), {from:minter}); // mint trade tokens
    _due = dueToken.address;
    _trade = tradeToken.address;

    // Value. This will ultimately be MakerDAO medianizer contract
    oracle = await OracleContract.new(price0, has, {from:boss});

    // The scout. Takes the medianizer value for pair and pushes it into the Chief
    pairKey = getHash(_due, _trade);
    spotter = await SpotterContract.new(chief.address, oracle.address, pairKey, {from:boss});

    // approve trading pair and set spotter address
    await chief.methods['file(bytes32,bytes32,bool)'](pairKey, hex("use"), true);
    await chief.methods['file(bytes32,bytes32,address)'](pairKey, hex("spotter"), spotter.address);

    // Contract for testing. Simulates the collateral manager
    testc = await TesterContract.new(chief.address, {from:testBoss});
    exec = testc.address;
    accountKey = getHash(exec, user);
  });


  it("Check contract constructors", async() => {
    // Chief
    // expect(await chief.proxy()).to.equal(proxy.address, "Chief proxy incorrect.");
    expect(await chief.vault()).to.equal(vault.address, "Chief vault incorrect.");
    expect(await chief.owner()).to.equal(boss, "Chief owner incorrect.");
    const pair = await chief.tokenPairs(pairKey);
    expect(pair.use, "trading pair not approved").to.be.true;
    expect(pair.spotter).to.equal(spotter.address, "trading pair scout incorect")

    // Vault
    expect(await vault.chief()).to.equal(chief.address, "Vault chief incorrect.");
    expect(await vault.proxy()).to.equal(proxy.address, "Vault proxy incorrect.");
    expect(await vault.owner()).to.equal(boss, "Vault owner incorrect.");

    // Proxy
    expect(await proxy.vault()).to.equal(vault.address, "Proxy vault incorrect.");

    // Tester
    expect(await testc.chief()).to.equal(chief.address, "Testc vault incorrect.");
    expect(await testc.owner()).to.equal(testBoss, "Testc owner incorrect.");

    // Scout
    expect(await spotter.chief()).to.equal(chief.address, "Scout chief incorrect");
    expect(await spotter.oracle()).to.equal(oracle.address, "Scout Value incorrect");
    expect(await spotter.pair()).to.equal(pairKey, "Scout pair incorrect");
    expect(await spotter.owner()).to.equal(boss, "Scout owner is incorrect");
    
    // Value
    const peek = await oracle.peek();
    expect(bn(peek[0])).to.eq.BN(price0, "Value val incorrect");
    expect(peek[1]).to.equal(has, "Value has incorrect");
    expect(await oracle.wards(boss)).to.eq.BN(1, "Value auth incorrect");

    // Tokens
    expect(await dueToken.isMinter(minter), "Due minter incorrect.").to.be.true;
    expect(await tradeToken.isMinter(minter), "Gem minter incorrect.").to.be.true;
    
  });


  it("Check Chief with no mama params", async() => {
    const dueTab = ethToWei(10);  // 10 eth
    const callTime = 86400;       // 1 day
    //const biteLimit = 1.5;
    //const biteFee = 0;
    //const lockAmt = dueTab * biteLimit; 

    await dueToken.approve(proxy.address, dueTab, {from:user});  // approve proxy

    // allow tester contract to take dueTab from user
    await chief.setAllowance(exec, user, dueTab, {from:user});
    // Open an account without mama params
    const openTx = await testc.open(dueTab, callTime, user, _due, false);
    const lastAccrual = (await web3.eth.getBlock(openTx.receipt.blockNumber)).timestamp;

    let account = {
      'exec': exec,  
      'dueToken': _due, 
      'tradeToken': ZERO_ADDR,
      'lastAccrual': lastAccrual,
      'dueTab': dueTab,
      'dueBalance': dueTab,
      'tradeBalance': 0,
      'callTime': callTime,
      'callTab': 0,
      'useExecParams': false,
      'state': 0,
      'user': user
    }
    
    await checkAcct(chief, account);  // Check that the account was opened correctly

    //await chief.lock(exec, _due, )

  });

  it("Check safe function", async() => {
    const dueTab = ethToWei(10);        // 10 due tokens
    const tradeBalance = ethToWei(5);   // 5 tradeTokens
    const tax = 0;
    const ten = new BigNum(10);
    const biteLimit = (new BigNum(1.2)).times(ten.pow(27)).toFixed(0);
    const biteFee = (new BigNum(1.1)).times(ten.pow(27)).toFixed(0)
    const callTime = 86400;             // 1 day
    console.log("biteLimit: ", biteLimit.toString())
    await dueToken.approve(proxy.address, dueTab, {from:user});  // approve proxy
    await tradeToken.approve(proxy.address, tradeBalance, {from:user});
    await chief.setAllowance(exec, user, dueTab, {from:user});
    await testc.open(dueTab, callTime, user, _due, false);
    await testc.addAccountAsset(tax, biteLimit, biteFee, _trade, user);
    // console.log("account.tokens[tradeToken]: ", await chief.accountAsset(exec, user, _trade));
    await chief.lock(accountKey, _trade, tradeBalance, {from:user});

    const safe = await chief.safe(accountKey);
    console.log("chief.safe(): ", safe);
    // console.log("chief.safe() credit: ", safe[0].toString());
    // console.log("chief.safe() debit:  ", safe[1].toString());

    console.log("acct uints: ", await chief.accountUints(exec, user));
  });


  it("Check oracle stuff", async() => {
    const dueTab = ethToWei(10);  // 10 eth
    const callTime = 86400;       // 1 day

    // Check that scout correctly updates trading pair val
    await spotter.poke();
    expect((await chief.tokenPairs(pairKey)).spotPrice).to.eq.BN(price0);

    // Update medianizer value and check scout functionality
    // const newVal = val0 * 2;
    // console.log("is BN?: ", web3.utils.isBN(newVal));
    // await value.methods['file(bytes32,uint256)'](hex("val"), bn(newVal));
    // await scout.poke();
    // console.log("contract val: ", (await chief.pairs(pairKey)).val);
    // console.log("newVal: ", newVal)
    // expect((await chief.pairs(pairKey)).val).to.eq.BN(newVal);
    await dueToken.approve(proxy.address, dueTab, {from:user});  // approve proxy
    await chief.setAllowance(exec, user, dueTab, {from:user});
    await testc.open(dueTab, callTime, user, _due, false);

    // console.log("exchange rate: ", (await chief.tokenPairs(pairKey)).spotPrice.toString()); 
    // console.log("acctKey: ", accountKey);
    // console.log("cAcctKey: ", await chief.foo(who, user))
    // const safe = await chief.safe(accountKey);
    // console.log("safe()[0]: ", safe[0].toString());
    // console.log("safe()[1]: ", safe[1].toString());
    // console.log("safe: ", safe.toString());

    // console.log(web3.utils.toBN('0000000000000000000000000000000000000000000000008cb5a37afbc6ff00').toString());
    // console.log(web3.utils.toBN('00000000000000000000000000000000000000000000000700df1485a4b70000').toString());
  });

});

// TODO: check order too
// NOTE: takes _who, _due, _gem, and user from global variables
// async function checkAcct(chief, acct      who, user, _due, _gem, era, tab, bal, own, zen, ohm, state, mom, opt) {
async function checkAcct(chief, acct) {
  const acctUints = await chief.accountUints(acct.exec, acct.user);
  const acctBools = await chief.accountBools(acct.exec, acct.user);
  const acctState = await chief.accountState(acct.exec, acct.user);
  const acctAddresses = await chief.accountAddresses(acct.exec, acct.user);

  expect(acctUints.lastAccrual).to.eq.BN(acct.lastAccrual, "Acct era wrong");
  expect(acctUints.dueTab).to.eq.BN(acct.dueTab, "Acct tab wrong");
  expect(acctUints.dueBalance).to.eq.BN(acct.dueBalance, "Acct bal wrong");
  expect(acctUints.tradeBalance).to.eq.BN(acct.tradeBalance, "Acct own wrong");
  expect(acctUints.callTime).to.eq.BN(acct.callTime, "Acct zen wrong");
  expect(acctUints.callTab).to.eq.BN(acct.callTab, "Acct ohm wrong");
  expect(acctState).to.eq.BN(acct.state, "Acct state wrong");
  expect(acctBools).to.equal(acct.useExecParams, "Acct mom wrong");
  expect(acctAddresses.exec).to.equal(acct.exec, "Acct who wrong");
  expect(acctAddresses.dueToken).to.equal(acct.dueToken, "Acct due wrong");
  expect(acctAddresses.tradeToken).to.equal(acct.tradeToken, "Acct gem wrong");
}

// becuase web3 utils uses bn.js instead of bignumber.js
function bn(num) {
  return web3.utils.toBN(num);
}

function getBlockTime() {

}

function getHash(addr1, addr2) {
  return web3.utils.soliditySha3(
    {type: 'address', value: addr1},
    {type: 'address', value: addr2}
  );
}

function ethToWei(val) {
  return web3.utils.toWei(val.toString(), 'ether');
}

function weiToEth(val) {
  return web3.utils.fromWei(val.toString(), 'ether');
}

function hex(val) {
  return web3.utils.toHex(val);
}