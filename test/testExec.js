// utils
const { expectRevert, getTxTime, weiToRay, yearlyRateToRay, bn, k256, ethToWei } = require('./helpers/web3Helpers');
const { deploySystem } = require("./helpers/setupTests");

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
  const minter = accounts[5];   // can mint tokens so we have some to play with
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000';

  // Value contract constructor defaults
  const price0 = new BigNum(ethToWei(100)); // 100 gem / 1 due token
  const mintAmt = new BigNum(ethToWei(100000));

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

  it("Check open with account-specific parameters", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const callTime  = new BigNum(1000000);
    const useAdminParams = false;
    const paramsKey = k256(admin, user);

    // prepare to open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    expect(await vat.allowances(acctKey, owedGem.address), "setAllowance")
      .to.eq.BN(bn(owedTab));

    // can open account correctly
    const tx = await exec.open(
      owedTab, 
      callTime, 
      user, 
      owedGem.address, 
      useAdminParams, 
      {from:admin}
    );
    expect(await vat.owedGems(paramsKey), "open owedGem")
      .to.equal(owedGem.address);
    expect(await vat.allowances(acctKey, owedGem.address), "open allowance")
      .to.eq.BN(0);

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

    // check transfer
    expect(await owedGem.balanceOf(user), "open transfer")
      .to.eq.BN(bn(mintAmt.minus(owedTab)));

    // can't call open on an existing account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await expectRevert(
      exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin}),
      "ccm-vat-doOpen-account-exists"
    );
  });

  it("Check addAdminOwedGem", async() => {
    const paramsKey = k256(admin);
    
    // set owed gem
    await exec.setAdminOwedGem(owedGem.address, {from:admin});
    expect(await vat.owedGems(paramsKey), "open owedGem").to.equal(owedGem.address);
  });

  it("Check open with admin-wide parameters", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const callTime  = new BigNum(1000000);
    const useAdminParams = true;
    const paramsKey = k256(admin);

    // prepare to open account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    expect(await vat.allowances(acctKey, owedGem.address), "setAllowance")
      .to.eq.BN(bn(owedTab));

    // can't open account without admin owed gem set
    await expectRevert(
      exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin}),
      "ccm-exec-open-no-owedGem"
    );

    // set admin params
    await exec.setAdminOwedGem(owedGem.address, {from:admin});

    // can open account correctly
    const tx = await exec.openWithAdminParams(owedTab, callTime, user, {from:admin});
    expect(await vat.allowances(acctKey, owedGem.address), "open allowance")
      .to.eq.BN(0);

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

    // check transfer
    expect(await owedGem.balanceOf(user), "open transfer")
      .to.eq.BN(bn(mintAmt.minus(owedTab)));

    // can't call open on an existing account
    await owedGem.approve(proxy.address, owedTab, {from:user});
    await broker.setAllowance(admin, owedGem.address, owedTab, {from:user});
    await expectRevert(
      exec.open(owedTab, callTime, user, owedGem.address, useAdminParams, {from:admin}),
      "ccm-vat-doOpen-account-exists"
    );
  });

  it("Check addAdminAsset", async() => {
    const paramsKey = k256(admin);
    const asset = {
      gemAddr: heldGem.address,
      tax: yearlyRateToRay(0.05).toFixed(0),
      biteLimit: weiToRay(1.2).toFixed(0),
      biteFee: weiToRay(1.2).toFixed(0),
    }

    // set owed gem
    await exec.setAdminOwedGem(owedGem.address, {from:admin});

    // add asset
    await exec.addAdminAsset(asset.tax, asset.biteLimit, asset.biteFee, asset.gemAddr, {from:admin});

    // check result
    const returnedAsset = await vat.assets(paramsKey, asset.gemAddr);
    expect(returnedAsset.tax).to.eq.BN(asset.tax);
    expect(returnedAsset.biteLimit).to.eq.BN(asset.biteLimit);
    expect(returnedAsset.biteFee).to.eq.BN(asset.biteFee);
    expect(returnedAsset.use).to.eq.BN(1);
  });

  it("Check addAccountAsset", async() => {
    const owedTab = new BigNum(ethToWei(10));
    const callTime  = new BigNum(1000000);
    const useAdminParams = false;
    const paramsKey = k256(admin, user);
    const asset = {
      gemAddr: heldGem.address,
      tax: yearlyRateToRay(0).toFixed(0),
      biteLimit: yearlyRateToRay(0).toFixed(0),
      biteFee: yearlyRateToRay(0).toFixed(0),
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

    // add assset
    await exec.addAccountAsset(asset.tax, asset.biteLimit, asset.biteFee, asset.gemAddr, user, {from:admin});

    // check result
    const returnedAsset = await vat.assets(paramsKey, asset.gemAddr);
    expect(returnedAsset.tax).to.eq.BN(asset.tax);
    expect(returnedAsset.biteLimit).to.eq.BN(asset.biteLimit);
    expect(returnedAsset.biteFee).to.eq.BN(asset.biteFee);
    expect(returnedAsset.use).to.eq.BN(1);
  });

});