// https://github.com/JoinColony/colonyNetwork/blob/develop/helpers/test-helper.js
// export async function expectEvent(tx, eventName) {
//   const { logs } = await tx;
//   const event = logs.find(e => e.event === eventName);
//   return assert.exists(event);
// }


// export async function forwardTime(seconds, test) {
//   const client = await web3GetClient();
//   const p = new Promise((resolve, reject) => {
//     if (client.indexOf("TestRPC") === -1) {
//       resolve(test.skip());
//     } else {
//       // console.log(`Forwarding time with ${seconds}s ...`);
//       web3.currentProvider.send(
//         {
//           jsonrpc: "2.0",
//           method: "evm_increaseTime",
//           params: [seconds],
//           id: 0
//         },
//         err => {
//           if (err) {
//             return reject(err);
//           }
//           return web3.currentProvider.send(
//             {
//               jsonrpc: "2.0",
//               method: "evm_mine",
//               params: [],
//               id: 0
//             },
//             (err2, res) => {
//               if (err2) {
//                 return reject(err2);
//               }
//               return resolve(res);
//             }
//           );
//         }
//       );
//     }
//   });
//   return p;
// }

// becuase web3 utils uses bn.js instead of bignumber.js
function bn(num) {
    return web3.utils.toBN(num);
}

function k256(addr1, addr2) {
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

module.exports = { bn, k256, ethToWei, weiToEth, hex }