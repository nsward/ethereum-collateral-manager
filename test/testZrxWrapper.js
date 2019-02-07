// Utils
const { bn, ethToWei } = require('./helpers/web3Helpers');
const { createSignedZrxOrder, zrxOrderToBytes } = require('./helpers/zrxHelpers');
const { deploySystem } = require("./helpers/setupTests");

// modules
const BigNum = require('bignumber.js'); // useful bignumber library
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));


contract("Zero Ex Wrapper", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const owner = accounts[0];    // owner of the system contracts
  const auth = accounts[1];   // set as auth on wrapper contract, represents the broker contract
  const user = accounts[3];     // owner of the collateral position
  const peer = accounts[4];     // recipient of payments
  const minter = accounts[5];   // can mint tokens so we have some to play with
  const relayer = accounts[6];  // 0x relayer
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000';

  // Value contract constructor defaults
  const price0 = new BigNum(ethToWei(100)); // 100 gem / 1 due token
  const mintAmt = new BigNum(ethToWei(100000));
  const salt = new BigNum(123);
  const makerFee = new BigNum(0);

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

    await wrapper.addAuth(auth, {from:owner});
    await heldGem.mint(peer, bn(mintAmt), {from:minter});
    await zrxGem.mint(peer, bn(mintAmt), {from:minter});
    await owedGem.mint(minter, bn(mintAmt), {from:minter});

  });

  it("Check fillOrKill with no fees", async() => {
    const owedAmt = new BigNum(100);
    const heldAmt = new BigNum(100);
    const takerFee = new BigNum(0);

    const order = await createSignedZrxOrder(
      zrxExchange.address,
      peer,
      ZERO_ADDR,
      heldGem.address,
      owedGem.address,
      heldAmt,
      owedAmt,
      makerFee,
      takerFee,
      relayer,
      ZERO_ADDR,
      new BigNum(100000000000000),
      salt
    );

    await heldGem.approve(zrxProxy.address, heldAmt, {from:peer});
    await owedGem.transfer(wrapper.address, owedAmt, {from:minter});

    // submit order
    await wrapper.fillOrKill(
      user, 
      heldGem.address, 
      owedGem.address, 
      heldAmt, 
      zrxOrderToBytes(order),
      {from:auth, gas:6500000}
    );

    // check result
    const wrapperOwedBalanceF = await owedGem.balanceOf(wrapper.address);
    const wrapperHeldBalanceF = await heldGem.balanceOf(wrapper.address);
    expect(wrapperOwedBalanceF).to.eq.BN(0);
    expect(wrapperHeldBalanceF).to.eq.BN(bn(heldAmt));
    
  });

  it("Check fillOrKill with taker fee", async() => {
    const owedAmt = new BigNum(1000000);
    const heldAmt = new BigNum(1000000);
    const takerFee = new BigNum(100);

    const order = await createSignedZrxOrder(
      zrxExchange.address,
      peer,
      ZERO_ADDR,
      heldGem.address,
      owedGem.address,
      heldAmt,
      owedAmt,
      makerFee,
      takerFee,
      relayer,
      ZERO_ADDR,
      new BigNum(100000000000000),
      salt
    );

    await heldGem.approve(zrxProxy.address, heldAmt, {from:peer});
    await zrxGem.approve(proxy.address, takerFee, {from:user});
    await owedGem.transfer(wrapper.address, owedAmt, {from:minter});

    // submit order
    await wrapper.fillOrKill(
      user, 
      heldGem.address, 
      owedGem.address, 
      heldAmt, 
      zrxOrderToBytes(order),
      {from:auth, gas:6500000}
    );

    // check result
    const wrapperOwedBalanceF = await owedGem.balanceOf(wrapper.address);
    const wrapperHeldBalanceF = await heldGem.balanceOf(wrapper.address);
    expect(wrapperOwedBalanceF).to.eq.BN(0);
    expect(wrapperHeldBalanceF).to.eq.BN(bn(heldAmt));
    
  });


});