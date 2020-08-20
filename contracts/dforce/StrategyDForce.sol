/**
 *Submitted for verification at Etherscan.io on 2020-08-13
*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.5.5;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';

import '../interface/IUniswapRouter.sol';
import '../interface/IController.sol';
import '../interface/IVault.sol';
import '../interface/IPool.sol';
import '../interface/IERC20.sol';
import '../library/SafeERC20.sol';

/*

 A strategy must implement the following calls;
 
 - deposit()
 - withdraw(address) must exclude any tokens used in the yield - Controller role - withdraw should return to Controller
 - withdraw(uint) - Controller | Vault role - withdraw should always return to vault
 - withdrawAll() - Controller | Vault role - withdraw should always return to vault
 - balanceOf()
 
 Where possible, strategies must remain as immutable as possible, instead of updating variables, we update the contract by linking it in the controller
 
*/


// convet ycurv ,dai,usdt,... to dtoken， 传入dtoken的token地址
interface dTokenConvert {
  function mint(address, uint256) external;
  function redeem(address, uint) external;
  function getTokenBalance(address) external view returns (uint);
  function getExchangeRate() external view returns (uint);
}


/*
 * forked from https://etherscan.io/address/0x01b354a9fb34760455ee9cbe7d71d2ce5c11ab5c#code
 */
contract StrategyDForce {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address public pool;
    address public dtoken;
    address public output;
    string public getName;
    

    address constant public df = address(0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0);  

    // vault

    address constant public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address constant public usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address constant public usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address constant public unirouter = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address constant public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // used for df <> weth <> usdc route
    address constant public yfii = address(0xa1d0E215a23d7030842FC67cE582a6aFa3CCaB83);
    
    
    uint public fee = 600;
    uint public burnfee = 300;
    uint public callfee = 100;
    uint constant public max = 10000;
    
    address public governance;
    address public controller;

    address  public want;
    
    address[] public swapRouting;


    mapping(address => address) public dTokens;
    mapping(address => address) public dPools;

    /*
     * @_output: df erc20 address 
     * @_pool: dforce pool
     * @_want: in [dai, dtoken, usdt ] 
     */

    constructor(address _output,address _want) public {
        governance = tx.origin;
        controller = 0xe14e60d0F7fb15b1A98FDE88A3415C17b023bf36;
        output = _output;
        //pool = _pool;
        want = _want;
        getName = string(
            abi.encodePacked("yfii:Strategy:", 
                abi.encodePacked(IERC20(want).name(),
                    abi.encodePacked(":",IERC20(output).name())
                )
            ));
        init(); 
        swapRouting = [output,weth,yfii];

    }
    
    function init () public{
        IERC20(output).safeApprove(unirouter, uint(-1));

        dTokens[dai] = address(0x02285AcaafEB533e03A7306C55EC031297df9224);
        dTokens[usdt] = address(0x868277d475E0e475E38EC5CdA2d9C83B5E1D9fc8);
        dTokens[usdc] = address(0x16c9cF62d8daC4a38FB50Ae5fa5d51E9170F3179);
        dtoken = dTokens[want];
        require(dtoken != address(0x0), "error want address");

        dPools[dai] = address(0xD2fA07cD6Cd4A5A96aa86BacfA6E50bB3aaDBA8B);
        dPools[usdt] = address(0x324EebDAa45829c6A8eE903aFBc7B61AF48538df);
        dPools[usdc] = address(0xB71dEFDd6240c45746EC58314a01dd6D833fD3b5);
        pool = dPools[want];

        require(pool != address(0x0), "error want address");
    }
    
    
    function deposit() public {
        uint _wantBalance = IERC20(want).balanceOf(address(this));
        if (_wantBalance > 0) {  // use stable coin mint usdc
            IERC20(want).safeApprove(dtoken, 0);
            IERC20(want).safeApprove(dtoken, _wantBalance);
            dTokenConvert(dtoken).mint(address(this), _wantBalance);
        }
        
        uint _dtokenBalance = IERC20(dtoken).balanceOf(address(this));

        if (_dtokenBalance > 0) {
            IERC20(dtoken).safeApprove(pool, 0);
            IERC20(dtoken).safeApprove(pool, _dtokenBalance);
            IPool(pool).stake(_dtokenBalance);
        }
        
    }
    
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == controller, "!controller");
        require(want != address(_asset), "want");
        require(dtoken != address(_asset), "dtoken");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(controller, balance);
    }
    
    // Withdraw partial funds, normally used with a vault withdrawal
    function withdraw(uint _amount) external {
        require(msg.sender == controller, "!controller");
        uint _balance = IERC20(want).balanceOf(address(this));
        if (_balance < _amount) {
            _amount = _withdrawSome(_amount.sub(_balance));
            _amount = _amount.add(_balance);
        }
        
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        
        IERC20(want).safeTransfer(_vault, _amount);
    }
    
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() public returns (uint balance) { 
        require(msg.sender == controller||msg.sender==governance, "!controller");
        _withdrawAll();
        
        
        balance = IERC20(want).balanceOf(address(this));
        
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).safeTransfer(_vault, balance);
    }
    
    function _withdrawAll() internal {
        IPool(pool).exit();
        uint _dtoken = IERC20(dtoken).balanceOf(address(this));

        //  如果不是usdc就，就可以取回来
        if (_dtoken > 0 && want != dtoken ) { 
            dTokenConvert(dtoken).redeem(address(this),_dtoken);
        }
    }
    
    function setNewPool(address _output,address _pool) public{
        require(msg.sender == governance, "!governance");
        //这边是切换池子以及挖到的代币
        //先退出之前的池子.
        harvest();
        withdrawAll();
        output = _output;
        pool = _pool;
        getName = string(
            abi.encodePacked("yfii:Strategy:", 
                abi.encodePacked(IERC20(want).name(),
                    abi.encodePacked(":",IERC20(output).name())
                )
            ));

    }
    
    
    function harvest() public {
        require(!Address.isContract(msg.sender),"!contract");
        IPool(pool).getReward(); 
        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

        uint outputBalance = IERC20(output).balanceOf(address(this));
        if (outputBalance > 0) {
  
            IUniswapRouter(unirouter).swapExactTokensForTokens(IERC20(output).balanceOf(address(this)), 0, swapRouting, address(this), now.add(1800));

            // fee
            uint b = IERC20(yfii).balanceOf(address(this));
            uint _fee = b.mul(fee).div(max);
            uint _callfee = b.mul(callfee).div(max);
            uint _burnfee = b.mul(burnfee).div(max);
            IERC20(yfii).safeTransfer(IController(controller).rewards(), _fee); //6%  5% team +1% insurance
            IERC20(yfii).safeTransfer(msg.sender, _callfee); //call fee 1%
            IERC20(yfii).safeTransfer(address(0x6666666666666666666666666666666666666666), _burnfee); //burn fee 3%

            //把yfii 存进去分红.
            IERC20(yfii).safeApprove(_vault, 0);
            IERC20(yfii).safeApprove(_vault, IERC20(yfii).balanceOf(address(this)));
            IVault(_vault).make_profit(IERC20(yfii).balanceOf(address(this)));
        }
    }
    
    function _withdrawSome(uint256 _amount) internal returns (uint) {
        uint _dtoken = _amount.mul(1e18).div(dTokenConvert(dtoken).getExchangeRate());
        uint _before = IERC20(dtoken).balanceOf(address(this));
        IPool(pool).withdraw(_dtoken);
        uint _after = IERC20(dtoken).balanceOf(address(this));
        uint _withdrew = _after.sub(_before);
        _before = IERC20(want).balanceOf(address(this));

        //  如果不是usdc就，就可以取回来
        if ( want != dtoken ) { 
            dTokenConvert(dtoken).redeem(address(this), _withdrew);
        }



        _after = IERC20(want).balanceOf(address(this));
        _withdrew = _after.sub(_before);
        return _withdrew;
    }
    
    function balanceOfWant() public view returns (uint) {
        return IERC20(want).balanceOf(address(this));
    }
    
    function balanceOfPool() public view returns (uint) {
        return (IPool(pool).balanceOf(address(this))).mul(dTokenConvert(dtoken).getExchangeRate()).div(1e18);
    }
    
    function getExchangeRate() public view returns (uint) {
        return dTokenConvert(dtoken).getExchangeRate();
    }
    
    function balanceOfDUSDC() public view returns (uint) {
        return dTokenConvert(dtoken).getTokenBalance(address(this));
    }
    
    function balanceOf() public view returns (uint) {
        return balanceOfWant()
               .add(balanceOfDUSDC())
               .add(balanceOfPool());
    }
    
    function balanceOfPendingReward() public view returns(uint){ //还没有领取的收益有多少...
        return IPool(pool).earned(address(this));
	}
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function setController(address _controller) external {
        require(msg.sender == governance, "!governance");
        controller = _controller;
    }

    function setFee(uint256 _fee) external{
        require(msg.sender == governance, "!governance");
        fee = _fee;
    }
    function setCallFee(uint256 _fee) external{
        require(msg.sender == governance, "!governance");
        callfee = _fee;
    }    
    function setBurnFee(uint256 _fee) external{
        require(msg.sender == governance, "!governance");
        burnfee = _fee;
    }
    function setSwapRouting(address[] memory _path) public{
        require(msg.sender == governance, "!governance");
        swapRouting = _path;
    }
}