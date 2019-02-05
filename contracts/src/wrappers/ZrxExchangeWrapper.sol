// For use with 0x V2 contracts

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "../../lib/MathTools.sol";
import "../../lib/AuthTools.sol";
import "../../lib/ZrxLib.sol";
import "../interfaces/GemLike.sol";
import "../interfaces/ZrxExchangeLike.sol";

contract ZrxExchangeWrapper is AuthAndOwnable {

    address public vault;
    address public zrxProxy;
    ZrxExchangeLike public exchange;
    GemLike public zrx;

    constructor(
        address _vault,
        address _zeroExExchange,
        address _zeroExProxy,
        address _zrx
    ) 
        public 
    {
        vault = _vault;
        zrxProxy = _zeroExProxy;
        exchange = ZrxExchangeLike(_zeroExExchange);
        zrx = GemLike(_zrx);

        // The ZRX token does not decrement allowance if set to max uint
        // therefore setting it once to the maximum amount is sufficient
        // NOTE: this is *not* standard behavior for an ERC20, so do not rely on it for other tokens
        zrx.approve(zrxProxy, uint(-1));
    }


    function fillOrKill(
        address tradeOrigin,
        address makerGem,
        address takerGem,
        // uint makerAmt,          // -- might not need this. all we care about at this point is fill amt?
        // uint takerAmt,          // -- same?
        uint fillAmt,
        bytes memory orderData  // TODO: calldata / external
    )
        public auth returns (uint)
    {
        // ** make sure we're approving the vault to take everything
        // Also need to take taker fee from user? --- need to get this from chief

        // prepare order and signature for the exchange
        ZrxLib.Order memory order = parseOrder(orderData, makerGem, takerGem);
        bytes memory sig = parseSignature(orderData);

        // get the taker fee from the user (if taker fee > 0)
        _takeTakerFee(order, tradeOrigin, fillAmt);

        // maker sure the exchange can take the fee token from us
        checkAllowance(takerGem, zrxProxy, fillAmt);

        ZrxLib.FillResults memory fill = exchange.fillOrKillOrder(order, fillAmt, sig);

        // validate the results of the order
        assert(fill.takerAssetFilledAmount == fillAmt);

        // Approve vault to take recieved tokens
        checkAllowance(makerGem, vault, fill.makerAssetFilledAmount);

        return fill.makerAssetFilledAmount;
    }

    function checkAllowance(address _gem, address spender, uint amt) private {
        GemLike gem = GemLike(_gem);
        if (gem.allowance(address(this), spender) >= amt) { return; }

        gem.approve(spender, uint(-1));
    }

    function _takeTakerFee(ZrxLib.Order memory order, address tradeOrigin, uint fillAmt) 
        private 
    {
        uint takerFee = MathTools.getPartialAmt(
            fillAmt, 
            order.takerAssetAmount, 
            order.takerFee
        );

        if (takerFee == 0) { return; }

        zrx.transferFrom(tradeOrigin, address(this), takerFee);
    }

    function parseOrder(bytes memory orderData, address makerGem, address takerGem)
        private
        pure
        returns (ZrxLib.Order memory)
    {
        ZrxLib.Order memory order;

        /* solium-disable-next-line security/no-inline-assembly */
        assembly {
            mstore(order,           mload(add(orderData, 32)))  // makerAddress
            mstore(add(order, 32),  mload(add(orderData, 64)))  // takerAddress
            mstore(add(order, 64),  mload(add(orderData, 96)))  // feeRecipientAddress
            mstore(add(order, 96),  mload(add(orderData, 128))) // senderAddress
            mstore(add(order, 128), mload(add(orderData, 160))) // makerAssetAmount
            mstore(add(order, 160), mload(add(orderData, 192))) // takerAssetAmount
            mstore(add(order, 192), mload(add(orderData, 224))) // makerFee
            mstore(add(order, 224), mload(add(orderData, 256))) // takerFee
            mstore(add(order, 256), mload(add(orderData, 288))) // expirationTimeSeconds
            mstore(add(order, 288), mload(add(orderData, 320))) // salt
        }

        order.makerAssetData = tokenAddressToAssetData(makerGem);
        order.takerAssetData = tokenAddressToAssetData(takerGem);

        return order;
    }

    function parseSignature(
        bytes memory orderData
    )
        private
        pure
        returns (bytes memory)
    {
        bytes memory signature = new bytes(66);

        /* solium-disable-next-line security/no-inline-assembly */
        assembly {
            mstore(add(signature, 32), mload(add(orderData, 352)))  // first 32 bytes
            mstore(add(signature, 64), mload(add(orderData, 384)))  // next 32 bytes
            mstore(add(signature, 66), mload(add(orderData, 386)))  // last 2 bytes
        }

        return signature;
    }

    function tokenAddressToAssetData(address tokenAddress) 
        private 
        pure 
        returns (bytes memory)
    {
        bytes memory result = new bytes(36);

        // padded version of bytes4(keccak256("ERC20Token(address)"));
        bytes32 selector = 0xf47261b000000000000000000000000000000000000000000000000000000000;

        /* solium-disable-next-line security/no-inline-assembly */
        assembly {
            // Store the selector and address in the asset data
            // The first 32 bytes of an array are the length (already set above)
            mstore(add(result, 32), selector)
            mstore(add(result, 36), tokenAddress)
        }

        return result;
    }

}