pragma solidity ^0.5.2;

// interface for exchange wrapper contracts
contract WrapperLike {
    function fillOrKill(
        address tradeOrigin,
        address makerAsset,
        address takerAsset,
        uint makerAmt,
        uint takerAmt,
        uint fillAmt,
        bytes calldata orderData
    ) external returns (uint);
}