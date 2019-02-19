// utils
const { bn, ethToWei } = require('./helpers/web3Helpers');
const { deploySystem } = require("./helpers/setupTests");

// modules
const BigNum = require('bignumber.js'); // useful bignumber library
const chai = require('chai');
const bnChai = require('bn-chai');
const { expect } = chai;
chai.use(bnChai(web3.utils.BN));


contract("ecm System deployment", function(accounts) {
  
  BigNum.config({ DECIMAL_PLACES: 27, POW_PRECISION: 100})

  // Test addresses
  const owner = accounts[0];    // owner of the system contracts
  const user = accounts[1];     // owner of the collateral position
  const minter = accounts[2];   // can mint tokens so we have some to play with

  // Value contract constructor defaults
  const price0 = new BigNum(ethToWei(100)); // 100 gem / 1 due token
  const mintAmt = new BigNum(ethToWei(100000));

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
    expect(await proxy.auths(wrapper.address)).to.eq.BN(1, "Proxy wrapper not auth");

    // Spotter
    expect(await spotter.owner()).to.equal(owner, "Spotter owner incorrect");
    expect(await spotter.oracle()).to.equal(oracle.address, "Spotter oracle address incorrect");
    expect(await spotter.broker()).to.equal(broker.address, "Spotter broker address incorrect");
    expect(await spotter.pair()).to.equal(pairKey, "Spotter pair key incorrect");

    // Wrapper
    expect(await wrapper.owner()).to.equal(owner, "Wrapper owner incorerct");
    expect(await wrapper.auths(broker.address)).to.eq.BN(1, "Wrapper broker not auth");
    expect(await wrapper.vault()).to.equal(vault.address, "Wrapper vault address incorrect");
    expect(await wrapper.proxy()).to.equal(proxy.address, "Wrapper proxy address incorrect");
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

});