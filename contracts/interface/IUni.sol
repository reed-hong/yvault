pragma solidity ^0.5.0;


interface IUni {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}