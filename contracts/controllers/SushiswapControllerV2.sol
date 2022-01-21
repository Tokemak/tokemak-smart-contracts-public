// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11 <=0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Router02.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IUniswapV2Factory.sol";
import "../interfaces/IMasterChefV2.sol";
import "./BaseController.sol";

contract SushiswapControllerV2 is BaseController {
    using SafeERC20 for IERC20;
    using Address for address;
    using Address for address payable;
    using SafeMath for uint256;

    // solhint-disable-next-line var-name-mixedcase
    IUniswapV2Router02 public immutable SUSHISWAP_ROUTER;
    // solhint-disable-next-line var-name-mixedcase
    IUniswapV2Factory public immutable SUSHISWAP_FACTORY;
    // solhint-disable-next-line var-name-mixedcase
    IMasterChefV2 public immutable MASTERCHEF;

    constructor(
        IUniswapV2Router02 router,
        IUniswapV2Factory factory,
        IMasterChefV2 masterchef,
        address manager,
        address _addressRegistry
    ) public BaseController(manager, _addressRegistry) {
        require(address(router) != address(0), "INVALID_ROUTER");
        require(address(factory) != address(0), "INVALID_FACTORY");
        require(address(masterchef) != address(0), "INVALID_MASTERCHEF");
        SUSHISWAP_ROUTER = router;
        SUSHISWAP_FACTORY = factory;
        MASTERCHEF = masterchef;
    }

    /// @notice deploy liquidity to Sushiswap pool
    /// @dev Calls to external contract
    /// @param data Bytes passed from manager.  Contains token addresses, minimum amounts, desired amounts.  Passed to Sushi router
    function deploy(bytes calldata data) external onlyManager {
        (
            address tokenA,
            address tokenB,
            uint256 amountADesired,
            uint256 amountBDesired,
            uint256 amountAMin,
            uint256 amountBMin,
            address to,
            uint256 deadline,
            uint256 poolId,
            bool toDeposit
        ) = abi.decode(
                data,
                (address, address, uint256, uint256, uint256, uint256, address, uint256, uint256, bool)
            );

        require(to == manager, "MUST_BE_MANAGER");
        require(addressRegistry.checkAddress(tokenA, 0), "INVALID_TOKEN");
        require(addressRegistry.checkAddress(tokenB, 0), "INVALID_TOKEN");

        _approve(address(SUSHISWAP_ROUTER), IERC20(tokenA), amountADesired);
        _approve(address(SUSHISWAP_ROUTER), IERC20(tokenB), amountBDesired);

        IERC20 pair = IERC20(SUSHISWAP_FACTORY.getPair(tokenA, tokenB));
        uint256 balanceBefore = pair.balanceOf(address(this));

        ( , , uint256 liquidity) = SUSHISWAP_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );

        uint256 balanceAfter = pair.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "MUST_INCREASE");

        if (toDeposit) {
            _approve(address(MASTERCHEF), pair, liquidity);
            depositLPTokensToMasterChef(poolId, liquidity);
        }
    }

    /// @notice Withdraw liquidity from a sushiswap LP pool
    /// @dev Calls an external contract
    /// @param data Bytes data, contains token addrs, amounts, deadline for sushi router interaction
    function withdraw(bytes calldata data) external onlyManager {
        (
            address tokenA,
            address tokenB,
            uint256 liquidity,
            uint256 amountAMin,
            uint256 amountBMin,
            address to,
            uint256 deadline,
            uint256 poolId,
            bool toWithdraw
        ) = abi.decode(data, (address, address, uint256, uint256, uint256, address, uint256, uint256, bool));

        require(to == manager, "MUST_BE_MANAGER");
        require(addressRegistry.checkAddress(tokenA, 0), "INVALID_TOKEN");
        require(addressRegistry.checkAddress(tokenB, 0), "INVALID_TOKEN");

        if (toWithdraw) withdrawLPTokensFromMasterChef(poolId);
        
        IERC20 pair = IERC20(SUSHISWAP_FACTORY.getPair(tokenA, tokenB));
        require(address(pair) != address(0), "pair doesn't exist");
        require(pair.balanceOf(address(this)) >= liquidity, "INSUFFICIENT_LIQUIDITY");
        _approve(address(SUSHISWAP_ROUTER), pair, liquidity);

        IERC20 tokenAInterface = IERC20(tokenA);
        IERC20 tokenBInterface = IERC20(tokenB);
        uint256 tokenABalanceBefore = tokenAInterface.balanceOf(address(this));
        uint256 tokenBBalanceBefore = tokenBInterface.balanceOf(address(this));

        SUSHISWAP_ROUTER.removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );

        uint256 tokenABalanceAfter = tokenAInterface.balanceOf(address(this));
        uint256 tokenBBalanceAfter = tokenBInterface.balanceOf(address(this));
        require(tokenABalanceAfter > tokenABalanceBefore, "MUST_INCREASE");
        require(tokenBBalanceAfter > tokenBBalanceBefore, "MUST_INCREASE");
    }

    function depositLPTokensToMasterChef(uint256 _poolId, uint256 amount) private {
        MASTERCHEF.deposit(_poolId, amount, address(this));
    }

    function withdrawLPTokensFromMasterChef(uint256 _poolId) private {
        (uint256 amount, ) = MASTERCHEF.userInfo(_poolId, address(this));
        MASTERCHEF.withdraw(_poolId, amount, address(this));
    }

    function _approve(address spender, IERC20 token, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance > 0) {
            token.safeDecreaseAllowance(spender, currentAllowance);
        }
        token.safeIncreaseAllowance(spender, amount);
    }
}