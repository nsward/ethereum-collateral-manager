const ChiefContract = artifacts.require('../contracts/Chief');
const VaultContract = artifacts.require('../contracts/Vault');
const ProxyContract = artifacts.require('../contracts/Proxy');
const ScoutContract = artifacts.require("../contracts/Scout.sol");
const TokenContract = artifacts.require("openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol");
const ValueContract = artifacts.require("../contracts/Value.sol");
const TesterContract = artifacts.require('../contracts/test/Tester');

// const BigNum = require('bignumber.js');
const BN = require('bn.js');  // bad bignumber library that web3.utils returns
const chai = require('chai');
const bnChai = require('bn-chai');

const { expect } = chai;
chai.use(bnChai(web3.utils.BN));

//TODO: https://github.com/JoinColony/colonyNetwork/blob/develop/test/colony.js

contract("Chief", function(accounts) {
  // Test addresses
  const boss = accounts[0];     // owner of the system contracts
  const user = accounts[1];     // owner of the collateral position
  const peer = accounts[2];     // recipient of payments
  const jerk = accounts[3];     // anyone. represents an outside bad actor / curious guy
  const testBoss = accounts[4]; // owner of the testc.
  const minter = accounts[5];   // can mint tokens so we have some to play with
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

  // Value contract constructor defaults
  const val0 = new BN(ethToWei(100)); // 100 gem / 1 due token
  console.log("val0: ", val0.toString());
  console.log("val0.mul(2): ", val0*2);
  const has = true;
  
  // contracts
  let chief;
  let vault;
  let proxy;
  let scout;
  let value;
  let testc;  // test contract. Simulates the collateral manager
  let who;    // managing contract address
  let due;    // due token contract
  let gem;    // gem token contract
  let _due;   // due token contract address
  let _gem;   // gem token contract address

  let pairKey;   // keccak256(_due, _gem)
  let acctKey;

    // Rep.USD
    // $10.21 / 1 REP
    // medianizer returns:         10139189884700000000
    // pit.ilks[ilk].spot: 5964229343941176470588235294

    // Eth.USd
    // $129.69 / 1 Eth
    // medianizer returns: 

  beforeEach("Instantiate Contracts", async() => {
    // Main contracts
    vault = await VaultContract.new({from:boss});
    proxy = await ProxyContract.new(vault.address, {from:boss});
    chief = await ChiefContract.new(vault.address, {from:boss});
    await vault.init(chief.address, proxy.address); // Set vault auth addresses

    // Tokens
    due = await TokenContract.new({from:minter});
    gem = await TokenContract.new({from:minter});
    await due.mint(user, new BN(ethToWei(100000)), {from:minter}); // mint due tokens
    _due = due.address;
    _gem = gem.address;

    // Value. This will ultimately be MakerDAO medianizer contract
    value = await ValueContract.new(val0, has, {from:boss});

    // The scout. Takes the medianizer value for pair and pushes it into the Chief
    pairKey = web3.utils.soliditySha3({t:'address', v:_due}, {t:'address', v:_gem});
    scout = await ScoutContract.new(chief.address, value.address, pairKey, {from:boss});

    // approve trading pair and set scout
    await chief.methods['file(bytes32,bytes32,bool)'](pairKey, hex("use"), true);
    await chief.methods['file(bytes32,bytes32,address)'](pairKey, hex("scout"), scout.address);

    // Contract for testing. Simulates the collateral manager
    testc = await TesterContract.new(chief.address, {from:testBoss});
    who = testc.address;
    acctKey = web3.utils.soliditySha3({t:'address', v:who}, {t:'address', v:user});
  });


  it("Check contract constructors", async() => {
    // Chief
    // expect(await chief.proxy()).to.equal(proxy.address, "Chief proxy incorrect.");
    expect(await chief.vault()).to.equal(vault.address, "Chief vault incorrect.");
    expect(await chief.owner()).to.equal(boss, "Chief owner incorrect.");
    const pair = await chief.pairs(pairKey);
    expect(pair.use, "trading pair not approved").to.be.true;
    expect(pair.scout).to.equal(scout.address, "trading pair scout incorect")

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
    expect(await scout.chief()).to.equal(chief.address, "Scout chief incorrect");
    expect(await scout.value()).to.equal(value.address, "Scout Value incorrect");
    expect(await scout.pair()).to.equal(pairKey, "Scout pair incorrect");
    expect(await scout.owner()).to.equal(boss, "Scout owner is incorrect");
    
    // Value
    const peek = await value.peek();
    expect(bn(peek[0])).to.eq.BN(val0, "Value val incorrect");
    expect(peek[1]).to.equal(has, "Value has incorrect");
    expect(await value.wards(boss)).to.eq.BN(1, "Value auth incorrect");

    // Tokens
    expect(await due.isMinter(minter), "Due minter incorrect.").to.be.true;
    expect(await gem.isMinter(minter), "Gem minter incorrect.").to.be.true;
    
  });


  it("Check Chief with no mama params", async() => {
    const tab = ethToWei(10); // 10 eth
    const zen = 86400;        // 1 day

    await due.approve(proxy.address, tab, {from:user});  // approve proxy

    // Open an account without mama params
    const openTx = await testc.open(tab, zen, user, _due, false);
    const era = (await web3.eth.getBlock(openTx.receipt.blockNumber)).timestamp;

    const acct = {
      'who': who,  
      'due': _due, 
      'gem': ZERO_ADDR,
      'era': era,
      'tab': tab,
      'bal': tab,
      'own': 0,
      'zen': zen,
      'ohm': 0,
      'mom': false,
      'opt': false,
      'state': 0,
      'user': user
    }
    
    await checkAcct(chief, acct);

  });


  it("Check oracle stuff", async() => {
    const tab = ethToWei(10); // 10 eth
    const zen = 86400;        // 1 day

    // Check that scout correctly updates trading pair val
    await scout.poke();
    expect((await chief.pairs(pairKey)).val).to.eq.BN(val0);

    // Update medianizer value and check scout functionality
    // const newVal = val0 * 2;
    // console.log("is BN?: ", web3.utils.isBN(newVal));
    // await value.methods['file(bytes32,uint256)'](hex("val"), bn(newVal));
    // await scout.poke();
    // console.log("contract val: ", (await chief.pairs(pairKey)).val);
    // console.log("newVal: ", newVal)
    // expect((await chief.pairs(pairKey)).val).to.eq.BN(newVal);
    await due.approve(proxy.address, tab, {from:user});  // approve proxy
    await testc.open(tab, zen, user, _due, false);

    console.log("exchange rate: ", (await chief.pairs(pairKey)).val.toString()); 
    console.log("acctKey: ", acctKey);
    // console.log("cAcctKey: ", await chief.foo(who, user))
    const safe = await chief.safe(acctKey);
    console.log("safe()[0]: ", safe[0].toString());
    console.log("safe()[1]: ", safe[1].toString());
    // console.log("safe: ", safe.toString());

    // console.log(web3.utils.toBN('0000000000000000000000000000000000000000000000008cb5a37afbc6ff00').toString());
    // console.log(web3.utils.toBN('00000000000000000000000000000000000000000000000700df1485a4b70000').toString());
  });

});

// TODO: check order too
// NOTE: takes _who, _due, _gem, and user from global variables
// async function checkAcct(chief, acct      who, user, _due, _gem, era, tab, bal, own, zen, ohm, state, mom, opt) {
async function checkAcct(chief, acct) {
  const acctUints = await chief.acctUints(acct.who, acct.user);
  const acctBools = await chief.acctBools(acct.who, acct.user);
  const acctState = await chief.acctState(acct.who, acct.user);
  const acctAddresses = await chief.acctAddresses(acct.who, acct.user);

  expect(acctUints.era).to.eq.BN(acct.era, "Acct era wrong");
  expect(acctUints.tab).to.eq.BN(acct.tab, "Acct tab wrong");
  expect(acctUints.bal).to.eq.BN(acct.bal, "Acct bal wrong");
  expect(acctUints.own).to.eq.BN(acct.own, "Acct own wrong");
  expect(acctUints.zen).to.eq.BN(acct.zen, "Acct zen wrong");
  expect(acctUints.ohm).to.eq.BN(acct.ohm, "Acct ohm wrong");
  expect(acctState).to.eq.BN(acct.state, "Acct state wrong");
  expect(acctBools.mom).to.equal(acct.mom, "Acct mom wrong");
  expect(acctBools.opt).to.equal(acct.opt, "Acct mom wrong");
  expect(acctAddresses.who).to.equal(acct.who, "Acct who wrong");
  expect(acctAddresses.due).to.equal(acct.due, "Acct due wrong");
  expect(acctAddresses.gem).to.equal(acct.gem, "Acct gem wrong");
}

// becuase web3 utils uses bn.js instead of bignumber.js
function bn(num) {
  return web3.utils.toBN(num);
}

function getBlockTime() {

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

// function hex(val) {
//   const _hex = web3.utils.toHex(val);
//   console.log("val.length: ", _hex.length);
//   return web3.utils.padRight(_hex, 42 - _hex.length);
// }