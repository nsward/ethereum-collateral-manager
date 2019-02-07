// much borrowd from Colony Network's testing helpers: 
// https://github.com/JoinColony/colonyNetwork/blob/develop/helpers/test-helper.js
const BigNum = require('bignumber.js');

async function expectEvent(tx, eventName) {
  const { logs } = await tx;
  const event = logs.find(e => e.event === eventName);
  return assert.exists(event);
}

function web3GetTransactionReceipt(txid) {
  return new Promise((resolve, reject) => {
      web3.eth.getTransactionReceipt(txid, (err, res) => {
      if (err !== null) return reject(err);
      return resolve(res);
    });
  });
}

async function expectRevert(promise, errorMessage) {
  // There is a discrepancy between how ganache-cli handles errors
  // (throwing an exception all the way up to these tests) and how geth/parity handle them
  // (still making a valid transaction and returning a txid). For the explanation of why
  // See https://github.com/ethereumjs/testrpc/issues/39
  //
  // Obviously, we want our tests to pass on all, so this is a bit of a problem.
  // We have to have this special function that we use to catch the error.
  let receipt;
  let reason;
  try {
    ({ receipt } = await promise);
    // If the promise is from Truffle, then we have the receipt already.
    // If this tx has come from the mining client, the promise has just resolved to a tx hash and we need to do the following
    if (!receipt) {
      const txid = await promise;
      receipt = await web3GetTransactionReceipt(txid);
    }
  } catch (err) {
    ({ reason } = err);
    assert.equal(reason, errorMessage);
    return;
  }
  // Check the receipt `status` to ensure transaction failed.
  assert.isFalse(receipt.status, `Transaction succeeded, but expected error ${errorMessage}`);
}

async function getTxTime(tx) {
  const block = await web3.eth.getBlock(tx.receipt.blockHash);
  return block.timestamp;
}

// becuase web3 utils uses bn.js instead of bignumber.js
function bn(num) {
  return web3.utils.toBN(num);
}

function k256(addr1, addr2=null) {
  if (addr2 === null) {
    return web3.utils.soliditySha3({type: 'address', value: addr1});
  }
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

function yearlyRateToRay(_rate) {
  rate = new BigNum(_rate);
  ten = new BigNum(10);
  return rate.div(365 * 86400).plus(1).times(ten.pow(27))
}

function weiToRay(_val) {
  val = new BigNum(_val);
  ten = new BigNum(10);
  return val.times(ten.pow(27));
}

function hex(val) {
  return web3.utils.toHex(val);
}

module.exports = { 
  expectRevert, 
  yearlyRateToRay,
  weiToRay,
  getTxTime, 
  expectEvent, 
  bn, 
  k256, 
  ethToWei, 
  weiToEth, 
  hex 
}