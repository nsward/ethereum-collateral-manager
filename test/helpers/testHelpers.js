// much borrowd from Colony Network's testing helpers: 
// https://github.com/JoinColony/colonyNetwork/blob/develop/helpers/test-helper.js

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

function web3GetRawCall(params) {
  const packet = {
    jsonrpc: "2.0",
    method: "eth_call",
    params: [params],
    id: new Date().getTime()
  };

  return new Promise((resolve, reject) => {
    web3.currentProvider.send(packet, (err, res) => {
      if (err !== null) return reject(err);
      return resolve(res);
    });
  });
}

function web3GetTransaction(txid) {
  return new Promise((resolve, reject) => {
    web3.eth.getTransaction(txid, (err, res) => {
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

// Borrowed from `truffle` https://github.com/trufflesuite/truffle/blob/next/packages/truffle-contract/lib/reason.js
function extractReasonString(res) {
  if (!res || (!res.error && !res.result)) return "";

  const errorStringHash = "0x08c379a0";

  const isObject = res && typeof res === "object" && res.error && res.error.data;
  const isString = res && typeof res === "object" && typeof res.result === "string";

  if (isObject) {
    const { data } = res.error;
    const hash = Object.keys(data)[0];

    if (data[hash].return && data[hash].return.includes(errorStringHash)) {
      return web3.eth.abi.decodeParameter("string", data[hash].return.slice(10));
    }
  } else if (isString && res.result.includes(errorStringHash)) {
    return web3.eth.abi.decodeParameter("string", res.result.slice(10));
  }
  return "";
}


// async function expectRevert(promise, errorMessage) {
//   let receipt;
//   try {
//     receipt = await promise;
//   } catch (err) {
//     const txid = err.transactionHash;
//     const tx = await web3GetTransaction(txid);
//     const response = await web3GetRawCall({ from: tx.from, to: tx.to, data: tx.input, gas: tx.gas, value: tx.value });
//     const reason = extractReasonString(response);
//     assert.equal(reason, errorMessage);
//     return;
//   }

//   assert.equal(receipt.status, 0, `Transaction succeeded, but expected to fail with: ${errorMessage}`);
// }


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

function hex(val) {
  return web3.utils.toHex(val);
}

module.exports = { expectRevert, getTxTime, expectEvent, bn, k256, ethToWei, weiToEth, hex }