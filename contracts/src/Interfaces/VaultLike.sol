pragma solidity ^0.5.2;

contract VaultLike {

    // Transfer tokens from user to us
    function take(address _gem, address src, uint amt) external returns (bool);

    // Transfer tokens from us to user
    function give(address _gem, address dst, uint amt) external returns (bool);

    // Add to user's claim balance
    function addClaim(address _gem, address lad, uint amt) external;

    // Verify that nothing has gone crazy
    function verifyBalance(address _gem) private view;

    function giveToWrapper(address _gem, address dst, uint amt) external returns (bool);

    function takeFromWrapper(address _gem, address src, uint amt) external returns (bool);

}