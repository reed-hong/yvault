pragma solidity ^0.5.5;

interface IPool {
    function withdraw(uint) external;
    function getReward() external;
    function stake(uint) external;
    function balanceOf(address) external view returns (uint);
    function exit() external;
    function earned(address) external view returns (uint);
}

