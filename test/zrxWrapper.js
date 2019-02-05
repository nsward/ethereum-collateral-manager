// Utils
const { expectRevert, getTxTime, bn, k256, ethToWei } = require('./helpers/testHelpers');
const { createSignedZrxOrder } = require('./helpers/zrxHelpers');
const { deploySystem } = require("./helpers/deploy");

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
  const salt = new BigNum(123);
  const makerFee = new BigNum(0);
  
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

  it("Check order creation", async() => {
    const owedAmt = new BigNum(100);
    const heldAmt = new BigNum(100);
    const takerFee = new BigNum(0);
    const giveHeldForOwedOrder = await createSignedZrxOrder(
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

    console.log("order: ", giveHeldForOwedOrder);
  });


});