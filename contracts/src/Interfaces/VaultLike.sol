pragma solidity ^0.5.3;

contract VaultLike {
    function take(address, address, uint) external returns (bool);
    function give(address, address, uint) external returns (bool);
    function addClaim(address, address, uint) external;
    function giveToWrapper(address, address, uint) external returns (bool);
    function takeFromWrapper(address, address, uint) external returns (bool);
}