// utils
const { expectRevert, getTxTime, yearlyRateToRay, weiToRay, bn, k256, ethToWei } = require('./helpers/web3Helpers');
const { createSignedZrxOrder, zrxOrderToBytes } = require('./helpers/zrxHelpers');
const { deploySystem } = require("./helpers/setupTests");

// modules
const BigNum = require('bignumber.js'); // useful bignumber library
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));


contract("Broker", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const owner = accounts[0];    // owner of the system contracts
  const auth = accounts[1]; // represents spotter. authorized address on the broker
  const admin = accounts[2];    // simulates the admin contract
  const user = accounts[3];     // owner of the collateral position
  const peer = accounts[4];     // recipient of payments
  const keeper = accounts[5];   // keeper / liquidator / biter
  const minter = accounts[6];   // can mint tokens so we have some to play with
  const relayer = accounts[7];  // 0x relayer
  const anyone = accounts[8];   // anyone. represents an outside bad actor / curious guy
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000';

  // Value contract constructor defaults
  const price0 = new BigNum(ethToWei(100)); // 100 gem / 1 due token
  const mintAmt = new BigNum(ethToWei(100000));
  const salt = new BigNum(123);
  
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
    
    await broker.addAuth(auth, {from:owner});
  });

  it("Check lock() with owedGem", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const lockAmt = new BigNum(ethToWei(5));
    const callTime  = new BigNum(1000000);
    const useAdminParams = false;

    // open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await exec.open(
      owedTab, 
      callTime, 
      user, 
      owedGem.address, 
      useAdminParams, 
      {from:admin}
    );

    // approve proxy to transfer lock funds
    await owedGem.approve(proxy.address, lockAmt, {from:user});

    // lock funds
    await broker.lock(acctKey, owedGem.address, lockAmt, {from:user});

    // check result
    const acct = await vat.accounts(acctKey);
    expect(acct.owedBal, "lock owedBal").to.eq.BN(bn(owedTab.plus(lockAmt)));
  });

  it("Check lock() with new heldGem", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const lockAmt = new BigNum(ethToWei(5));
    const callTime  = new BigNum(1000000);
    const useAdminParams = false;
    const asset = {
      gemAddr: heldGem.address,
      tax: yearlyRateToRay(0).toFixed(0),
      biteLimit: weiToRay(1).toFixed(0),
      biteFee: weiToRay(1).toFixed(0),
    }

    // open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await exec.open(
      owedTab, 
      callTime, 
      user, 
      owedGem.address, 
      useAdminParams, 
      {from:admin}
    );

    // approve proxy to transfer lock funds
    await heldGem.approve(proxy.address, lockAmt, {from:user});

    // can't lock funds if gem not approved
    await expectRevert(
      broker.lock(acctKey, heldGem.address, lockAmt, {from:user}), 
      "ccm-broker-lock-gem-unapproved"
    );

    // approve heldGem asset
    await exec.addAccountAsset(asset.tax, asset.biteLimit, asset.biteFee, asset.gemAddr, user, {from:admin});

    // lock new heldGem
    // approve proxy to transfer lock funds
    await heldGem.approve(proxy.address, lockAmt, {from:user});

    // lock funds
    await broker.lock(acctKey, heldGem.address, lockAmt, {from:user});

    // check result
    const acct = await vat.accounts(acctKey);
    expect(acct.owedBal, "lock owedBal").to.eq.BN(bn(owedTab));
    expect(acct.heldBal, "lock heldBal").to.eq.BN(bn(lockAmt));
    expect(acct.heldGem).to.equal(heldGem.address);
  });

  // TODO: tons more test cases for swap()
  it("Check swap", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const price = new BigNum(ethToWei(1));  // 1 to 1 exchange rate
    const heldAmt = owedTab;    // swap for equal amt of collateral in new gem
    const callTime  = new BigNum(1000000);
    const useAdminParams = false;
    const makerFee = 0;
    const takerFee = 0;
    const asset = {
      gemAddr: heldGem.address,
      tax: yearlyRateToRay(0).toFixed(0),
      biteLimit: weiToRay(1).toFixed(0),
      biteFee: weiToRay(1).toFixed(0),
    }

    // open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await exec.open(
      owedTab, 
      callTime, 
      user, 
      owedGem.address, 
      useAdminParams, 
      {from:admin}
    );
    
    // approve heldGem asset
    await exec.addAccountAsset(asset.tax, asset.biteLimit, asset.biteFee, asset.gemAddr, user, {from:admin});

    // set spot price
    await broker.spot(pairKey, price, {from:auth});

    // create order
    await heldGem.mint(peer, bn(mintAmt), {from:minter});
    await heldGem.approve(zrxProxy.address, heldAmt, {from:peer});
    const order = await createSignedZrxOrder(
      zrxExchange.address,
      peer,
      ZERO_ADDR,
      heldGem.address,
      owedGem.address,
      heldAmt,
      owedTab,
      makerFee,
      takerFee,
      relayer,
      ZERO_ADDR,
      new BigNum(100000000000000),  // how long order is valid for
      salt
    );
    
    // take order
    await broker.swap(
      acctKey,
      wrapper.address,
      heldGem.address,
      owedGem.address,
      heldAmt,
      owedTab,
      owedTab,
      zrxOrderToBytes(order),
      {from:user}
    );
    
    const acct = await vat.accounts(acctKey);
    expect(acct.owedBal).to.eq.BN(bn(owedTab.minus(heldAmt)));
    expect(await owedGem.balanceOf(vault.address)).to.eq.BN(bn(owedTab.minus(heldAmt)));
    expect(acct.heldBal).to.eq.BN(bn(heldAmt));
    expect(acct.heldGem).to.equal(heldGem.address);
    expect(await heldGem.balanceOf(vault.address)).to.eq.BN(bn(heldAmt))
    
  });
  
});