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