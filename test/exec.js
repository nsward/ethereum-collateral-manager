// utils
const { expectRevert, getTxTime, bn, k256, ethToWei } = require('./helpers/testHelpers');
const { deploySystem } = require("./helpers/deploy");

// modules
const BigNum = require('bignumber.js'); // useful bignumber library
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));


contract("Exec", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const owner = accounts[0];    // owner of the system contracts
  const admin = accounts[1];    // simulates the admin contract
  const user = accounts[2];     // owner of the collateral position
  const peer = accounts[3];     // recipient of payments
  const keeper = accounts[4];   // keeper / liquidator / biter
  const minter = accounts[5];   // can mint tokens so we have some to play with
  const relayer = accounts[6];  // 0x relayer
  const anyone = accounts[7];   // anyone. represents an outside bad actor / curious guy
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000';

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
  let owedGem;  // owed token contract
  let heldGem;  // held token contract
  let zrxGem;   // ZRX token contract

  // mapping keys
  let pairKey;                      // keccak256(_owedGem, _heldGem)
  let acctKey = k256(admin, user);  // keccak256(admin, user)


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

  });

  it("Check addAdminOwedGem", async() => {

  });

  it("Check open with account-specific parameters", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const callTime  = new BigNum(1000000);
    const useAdminParams = false;
    const paramsKey = k256(admin, user);

    // prepare to open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    expect(await vat.allowances(acctKey, owedGem.address), "setAllowance").to.eq.BN(bn(owedTab));

    // can open account correctly
    const tx = await exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin});
    expect(await vat.owedGems(paramsKey), "open owedGem").to.equal(owedGem.address);
    expect(await vat.allowances(acctKey, owedGem.address), "open allowance").to.eq.BN(0);

    // check resulting account
    const acct = await vat.accounts(acctKey);
    expect(acct.callTime, "open callTime").to.eq.BN(bn(callTime));
    expect(acct.callTab, "open callTab").to.eq.BN(0);
    expect(acct.lastAccrual, "open lastAccrual").to.eq.BN(await getTxTime(tx));
    expect(acct.owedTab, "open owedTab").to.eq.BN(bn(owedTab));
    expect(acct.owedBal, "open owedBal").to.eq.BN(bn(owedTab));
    expect(acct.heldBal, "open heldBal").to.eq.BN(0);
    expect(acct.heldGem, "open heldGem").to.equal(ZERO_ADDR);
    expect(acct.paramsKey, "open paramsKey").to.equal(paramsKey);
    expect(acct.user, "open user").to.equal(user);
    expect(acct.admin, "open admin").to.equal(admin);
    // TODO: check state?

    // check transfer
    expect(await owedGem.balanceOf(user), "open transfer").to.eq.BN(bn(mintAmt.minus(owedTab)));

    // can't call open on an existing account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await expectRevert(
      exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin}),
      "ccm-vat-doOpen-account-exists"
    );
  });

  it("Check open with admin-wide parameters", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const callTime  = new BigNum(1000000);
    const useAdminParams = true;
    const paramsKey = k256(admin);

    // prepare to open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    expect(await vat.allowances(acctKey, owedGem.address), "setAllowance").to.eq.BN(bn(owedTab));

    // can't open account without admin owed gem set
    await expectRevert(
      exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin}),
      "ccm-exec-open-no-owedGem"
    );

    // set admin params
    await exec.setAdminOwedGem(owedGem.address, {from:admin});
    expect(await vat.owedGems(paramsKey), "open owedGem").to.equal(owedGem.address);

    // can open account correctly
    const tx = await exec.openWithAdminParams(owedTab, callTime, user, {from:admin});
    expect(await vat.allowances(acctKey, owedGem.address), "open allowance").to.eq.BN(0);

    // check resulting account
    const acct = await vat.accounts(acctKey);
    expect(acct.callTime, "open callTime").to.eq.BN(bn(callTime));
    expect(acct.callTab, "open callTab").to.eq.BN(0);
    expect(acct.lastAccrual, "open lastAccrual").to.eq.BN(await getTxTime(tx));
    expect(acct.owedTab, "open owedTab").to.eq.BN(bn(owedTab));
    expect(acct.owedBal, "open owedBal").to.eq.BN(bn(owedTab));
    expect(acct.heldBal, "open heldBal").to.eq.BN(0);
    expect(acct.heldGem, "open heldGem").to.equal(ZERO_ADDR);
    expect(acct.paramsKey, "open paramsKey").to.equal(paramsKey);
    expect(acct.user, "open user").to.equal(user);
    expect(acct.admin, "open admin").to.equal(admin);
    // TODO: check state?

    // check transfer
    expect(await owedGem.balanceOf(user), "open transfer").to.eq.BN(bn(mintAmt.minus(owedTab)));

    // can't call open on an existing account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await expectRevert(
      exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin}),
      "ccm-vat-doOpen-account-exists"
    );
  });

});