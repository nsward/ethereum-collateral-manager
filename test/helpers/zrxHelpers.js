// From dYdX Protocol https://github.com/dydxprotocol/protocol
const ethUtil = require('ethereumjs-util');

const { addressToBytes32, concatBytes } = require('./bytesHelpers');

const ORDER_TYPE = "zeroExV2";

async function createSignedZrxOrder(
    exchangeAddr,
    maker,
    taker,
    makerGem,
    takerGem,
    makerAmt,
    takerAmt,
    makerFee,
    takerFee,
    feeRecipient,
    sender,
    expirationTimeSeconds,
    salt
) {
  const order = {
    type: ORDER_TYPE,
    exchangeAddress: exchangeAddr,

    makerAddress: maker,
    takerAddress: taker,
    feeRecipientAddress: feeRecipient,
    senderAddress: sender,

    makerFee: makerFee,
    takerFee: takerFee,
    expirationTimeSeconds: expirationTimeSeconds,
    salt: salt,

    makerTokenAddress: makerGem,
    makerAssetAmount: makerAmt,
    takerTokenAddress: takerGem,
    takerAssetAmount: takerAmt
  };

  order.signature = await signV2Order(order);

  return order;
}

async function signV2Order(order) {
    const signature = await web3.eth.sign(
    getV2OrderHash(order), order.makerAddress
  );

  const { v, r, s } = ethUtil.fromRpcSig(signature);

  // 0x00 Illegal
  // 0x01 Invalid
  // 0x02 EIP712 (no prepended string)
  // 0x03 EthSign (prepended "\x19Ethereum Signed Message:\n32")
  // 0x04 Wallet
  // 0x05 Validator
  // 0x06 PreSigned
  // 0x07 NSignatureTypes
  const sigType = 3;

  return ethUtil.bufferToHex(
    Buffer.concat([
      ethUtil.toBuffer(v),
      r,
      s,
      ethUtil.toBuffer(sigType)
    ])
  );
}

function getV2OrderHash(order) {

  const eip712Hash = "0x770501f88a26ede5c04a20ef877969e961eb11fc13b78aaf414b633da0d4f86f";

  const makerAssetData = addressToAssetData(order.makerTokenAddress);
  const takerAssetData = addressToAssetData(order.takerTokenAddress);

  const basicHash = web3.utils.soliditySha3(
    { t: 'bytes32', v: eip712Hash },
    { t: 'bytes32', v: addressToBytes32(order.makerAddress) },
    { t: 'bytes32', v: addressToBytes32(order.takerAddress) },
    { t: 'bytes32', v: addressToBytes32(order.feeRecipientAddress) },
    { t: 'bytes32', v: addressToBytes32(order.senderAddress) },
    { t: 'uint256', v: order.makerAssetAmount },
    { t: 'uint256', v: order.takerAssetAmount },
    { t: 'uint256', v: order.makerFee },
    { t: 'uint256', v: order.takerFee },
    { t: 'uint256', v: order.expirationTimeSeconds },
    { t: 'uint256', v: order.salt },
    { t: 'bytes32', v: web3.utils.soliditySha3({ t: 'bytes', v: makerAssetData })},
    { t: 'bytes32', v: web3.utils.soliditySha3({ t: 'bytes', v: takerAssetData })}
  );

  const eip712DomSepHash = "0x91ab3d17e3a50a9d89e63fd30b92be7f5336b03b287bb946787a83a9d62a2766";

  const eip712DomainHash = web3.utils.soliditySha3(
    { t: 'bytes32', v: eip712DomSepHash },
    { t: 'bytes32', v: web3.utils.soliditySha3({ t: 'string', v: '0x Protocol' })},
    { t: 'bytes32', v: web3.utils.soliditySha3({ t: 'string', v: '2' })},
    { t: 'bytes32', v: addressToBytes32(order.exchangeAddress) }
  );

  const retVal = web3.utils.soliditySha3(
    { t: 'bytes', v: "0x1901" },
    { t: 'bytes32', v: eip712DomainHash },
    { t: 'bytes32', v: basicHash },
  );

  return retVal;
}

function toBytes32(val) {
  return web3.utils.hexToBytes(
    web3.utils.padLeft(web3.utils.toHex(val), 64)
  );
}

function zrxOrderToBytes(order) {
  const v = []
    .concat(toBytes32(order.makerAddress))
    .concat(toBytes32(order.takerAddress))
    .concat(toBytes32(order.feeRecipientAddress))
    .concat(toBytes32(order.senderAddress))
    .concat(toBytes32(order.makerAssetAmount))
    .concat(toBytes32(order.takerAssetAmount))
    .concat(toBytes32(order.makerFee))
    .concat(toBytes32(order.takerFee))
    .concat(toBytes32(order.expirationTimeSeconds))
    .concat(toBytes32(order.salt))
    .concat(toBytes32(order.signature));
  return web3.utils.bytesToHex(v);
}

function addressToAssetData(address) {
  const assetDataPrepend = '0xf47261b0';
  return concatBytes(assetDataPrepend, addressToBytes32(address));
}

module.exports = {
  createSignedZrxOrder,
  signV2Order,
  getV2OrderHash,
  addressToAssetData,
  zrxOrderToBytes
}