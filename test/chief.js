const ChiefContract = artifacts.require('../contracts/Chief');
const VaultContract = artifacts.require('../contracts/Vault');
const ProxyContract = artifacts.require('../contracts/Proxy');
const TesterContract = artifacts.require('../contracts/test/Tester');
const TokenContract = artifacts.require('../contracts/test/ERC20Mintable.sol');
const BigNum = require('bignumber.js');
const BN = require('bn.js');  // bad bignumber library that web3.utils returns

const chai = require('chai');
const bnChai = require('bn-chai');
//TODO: https://github.com/JoinColony/colonyNetwork/blob/develop/test/colony.js
chai.use(bnChai(web3.utils.BN));

contract("Chief", function(accounts) {
  let vault;
  let proxy;
  let chief;
  let testc;
  
  const boss = accounts[0];     // owner of the system contracts
  const user = accounts[1];     // owner of the collateral position
  const peer = accounts[2];     // recipient of payments
  const jerk = accounts[3];     // anyone. represents an outside bad actor / curious guy
  const testBoss = accounts[4]; // owner of the testc.
  const minter = accounts[5];

  const tab = new BN(ethToWei(10));  // 10 eth
  const zen = new BN(86400);    // 1 day
  let who; // managing contract address
  let due;  //token contracts
  let gem;
  let _due; // token contract addresses
  let _gem;

  beforeEach("Instantiate Contracts", async() => {
    vault = await VaultContract.new({from:boss});
    proxy = await ProxyContract.new(vault.address, {from:boss});
    chief = await ChiefContract.new(vault.address, proxy.address, {from:boss});
    await vault.init(chief.address, proxy.address);

    testc = await TesterContract.new(chief.address, {from:testBoss});
    due = await TokenContract.new({from:minter});
    gem = await TokenContract.new({from:minter});
    _due = due.address;
    _gem = gem.address;
    who = testc.address;
    
  });

  it("Check contract constructors", async() => {
    assert.equal(await chief.proxy(), proxy.address, "Chief proxy incorrect.");
    assert.equal(await chief.vault(), vault.address, "Chief vault incorrect.");
    assert.equal(await vault.chief(), chief.address, "Vault chief incorrect.");
    assert.equal(await vault.proxy(), proxy.address, "Vault proxy incorrect.");
    assert.equal(await proxy.vault(), vault.address, "Proxy vault incorrect.");
    assert.equal(await testc.chief(), chief.address, "Testc vault incorrect.");

    assert.equal(await chief.owner(), boss, "Chief owner incorrect.");
    assert.equal(await vault.owner(), boss, "Vault owner incorrect.");
    assert.equal(await testc.owner(), testBoss, "Testc owner incorrect.");
    assert.equal(await due.isMinter(minter), true, "Due minter incorrect.");
    assert.equal(await gem.isMinter(minter), true, "Gem minter incorrect.");
  });

  it("Check Chief with no mama params", async() => {
    await due.mint(user, new BN(ethToWei(100)), {from:minter}); // mint due tokens to user
    await due.approve(proxy.address, tab, {from:user});         // approve proxy to transfer
    const openTx = await testc.open(tab, zen, user, _due, false); // no mama

    const era = (await web3.eth.getBlock(openTx.receipt.blockNumber)).timestamp;

    // gem = 0, bal = 0 bc no user trades yet
    // ohm = 0, state = 0 bc in par state 
    checkAcct(chief, who, user, _due, 0, era, tab, tab, 0, zen, 0, 0, false, false);

    console.log("uints: ", await chief.acctUints(who, user));
    console.log("state: ", await chief.acctState(who, user));
    console.log("addresses: ", await chief.acctAddresses(who, user));
    console.log("bools: ", await chief.acctBools(who, user));
  });
});

// TODO: check order too
// NOTE: takes _who, _due, _gem, and user from global variables
async function checkAcct(chief, who, user, _due, _gem, era, tab, bal, val, zen, ohm, state, mom, opt) {
  const acctUints = await chief.acctUints(who, user);
  const acctBools = await chief.acctBools(who, user);
  const acctState = await chief.acctState(who, user);
  const acctAddresses = await chief.acctAddresses(who, user);

  console.log("acctUints: ", acctUints.tab);
  
  // TODO: should use expect().to.eq.BN() for these
  assert.equal(acctUints.era.toString(), era.toString(), "Acct era wrong");
  assert.equal(acctUints.tab.toString(), tab.toString(), "Acct tab wrong");
  assert.equal(acctUints.bal.toString(), bal.toString(), "Acct bal wrong");
  assert.equal(acctUints.val.toString(), val.toString(), "Acct val wrong");
  assert.equal(acctUints.zen.toString(), zen.toString(), "Acct zen wrong");
  assert.equal(acctUints.ohm.toString(), ohm.toString(), "Acct ohm wrong");
  assert.equal(acctBools.mom, mom, "Acct mom wrong");
  assert.equal(acctBools.opt, opt, "Acct mom wrong");
  assert.equal(acctState, state, "Acct val wrong");
  assert.equal(acctAddresses.who, who, "Acct who wrong");
  assert.equal(acctAddresses.due, _due, "Acct due wrong");
  assert.equal(acctAddresses.gem, _gem, "Acct gem wrong");
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