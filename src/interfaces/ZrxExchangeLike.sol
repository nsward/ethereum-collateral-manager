pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "../../lib/ZrxLib.sol";

contract ZrxExchangeLike {
    /// @dev Fills the input order. Reverts if exact takerAssetFillAmount not filled.
    /// @param order LibOrder.Order struct containing order specifications.
    /// @param takerAssetFillAmount Desired amount of takerAsset to sell.
    /// @param signature Proof that order has been created by maker.
    function fillOrKillOrder(
        ZrxLib.Order memory order,
        uint256 takerAssetFillAmount,
        bytes memory signature
    )
        public
        returns (ZrxLib.FillResults memory fillResults);
}