// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// import { AddressUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { IWBNB } from "../interfaces/IWBNB.sol";
import { IPancakeswapFarm } from "../interfaces/IPancakeswapFarm.sol";
import { IPancakeRouter02 } from "../interfaces/IPancakeRouter02.sol";

// solhint-disable max-states-count
contract PancakeStrategyV2 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint256 public pid;
  address public farmContractAddress;
  address public want;
  address public cake;
  address public token0;
  address public token1;
  address public router;
  address public helioFarming;

  bool public enableAutoHarvest;

  address[] public earnedToToken0Path;
  address[] public earnedToToken1Path;

  uint256 public wantLockedTotal;
  uint256 public sharesTotal;

  uint256 public minEarnAmount;
  uint256 public constant MIN_EARN_AMOUNT_LL = 10**10;

  uint256 public slippageFactor;
  uint256 public constant SLIPPAGE_FACTOR_UL = 995;
  uint256 public constant SLIPPAGE_FACTOR_MAX = 1000;

  modifier onlyHelioFarming() {
    require(msg.sender == helioFarming, "!helio Farming");
    _;
  }

  function initialize(
    uint256 _pid,
    uint256 _minEarnAmount,
    bool _enableAutoHarvest,
    address[] memory _addresses,
    // 0 address _farmContractAddress,
    // 1 address _want,
    // 2 address _cake,
    // 3 address _token0,
    // 4 address _token1,
    // 5 address _router,
    // 6 address _helioFarming,
    address[] memory _earnedToToken0Path,
    address[] memory _earnedToToken1Path
  ) public initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    require(_minEarnAmount >= MIN_EARN_AMOUNT_LL, "min earn amount is too low");
    slippageFactor = 950;
    pid = _pid;
    minEarnAmount = _minEarnAmount;
    farmContractAddress = _addresses[0];
    want = _addresses[1];
    cake = _addresses[2];
    token0 = _addresses[3];
    token1 = _addresses[4];
    router = _addresses[5];
    helioFarming = _addresses[6];
    enableAutoHarvest = _enableAutoHarvest;
    earnedToToken0Path = _earnedToToken0Path;
    earnedToToken1Path = _earnedToToken1Path;
  }

  // Receives new deposits from user
  function deposit(address, uint256 _wantAmt)
    public
    virtual
    onlyHelioFarming
    whenNotPaused
    returns (uint256)
  {
    if (enableAutoHarvest) {
      _harvest();
    }
    IERC20Upgradeable(want).safeTransferFrom(address(msg.sender), address(this), _wantAmt);

    uint256 sharesAdded = _wantAmt;
    if (wantLockedTotal > 0 && sharesTotal > 0) {
      sharesAdded = (_wantAmt * sharesTotal) / wantLockedTotal;
    }
    sharesTotal += sharesAdded;

    _farm();

    return sharesAdded;
  }

  function withdraw(address, uint256 _wantAmt)
    public
    virtual
    onlyHelioFarming
    nonReentrant
    returns (uint256)
  {
    require(_wantAmt > 0, "_wantAmt <= 0");

    if (enableAutoHarvest) {
      _harvest();
    }

    uint256 sharesRemoved = (_wantAmt * sharesTotal) / wantLockedTotal;
    if (sharesRemoved > sharesTotal) {
      sharesRemoved = sharesTotal;
    }
    sharesTotal -= sharesRemoved;

    _unfarm(_wantAmt);

    uint256 wantAmt = IERC20Upgradeable(want).balanceOf(address(this));
    if (_wantAmt > wantAmt) {
      _wantAmt = wantAmt;
    }

    if (wantLockedTotal < _wantAmt) {
      _wantAmt = wantLockedTotal;
    }

    wantLockedTotal -= _wantAmt;

    IERC20Upgradeable(want).safeTransfer(helioFarming, _wantAmt);

    return sharesRemoved;
  }

  function farm() public virtual nonReentrant {
    _farm();
  }

  function _farm() internal virtual {
    uint256 wantAmt = IERC20Upgradeable(want).balanceOf(address(this));
    wantLockedTotal += wantAmt;
    IERC20Upgradeable(want).safeIncreaseAllowance(farmContractAddress, wantAmt);

    IPancakeswapFarm(farmContractAddress).deposit(pid, wantAmt);
  }

  function _unfarm(uint256 _wantAmt) internal virtual {
    IPancakeswapFarm(farmContractAddress).withdraw(pid, _wantAmt);
  }

  // 1. Harvest farm tokens
  // 2. Converts farm tokens into want tokens
  // 3. Deposits want tokens
  function harvest() public virtual nonReentrant whenNotPaused {
    _harvest();
  }

  // 1. Harvest farm tokens
  // 2. Converts farm tokens into want tokens
  // 3. Deposits want tokens
  function _harvest() internal virtual {
    // Harvest farm tokens
    _unfarm(0);

    // Converts farm tokens into want tokens
    uint256 earnedAmt = IERC20Upgradeable(cake).balanceOf(address(this));

    IERC20Upgradeable(cake).safeApprove(router, 0);
    IERC20Upgradeable(cake).safeIncreaseAllowance(router, earnedAmt);

    if (earnedAmt < minEarnAmount) {
      return;
    }

    if (cake != token0) {
      // Swap half earned to token0
      _safeSwap(
        router,
        earnedAmt / 2,
        slippageFactor,
        earnedToToken0Path,
        address(this),
        block.timestamp + 600
      );
    }

    if (cake != token1) {
      // Swap half earned to token1
      _safeSwap(
        router,
        earnedAmt / 2,
        slippageFactor,
        earnedToToken1Path,
        address(this),
        block.timestamp + 600
      );
    }

    // Get want tokens, ie. add liquidity
    uint256 token0Amt = IERC20Upgradeable(token0).balanceOf(address(this));
    uint256 token1Amt = IERC20Upgradeable(token1).balanceOf(address(this));
    if (token0Amt > 0 && token1Amt > 0) {
      IERC20Upgradeable(token0).safeIncreaseAllowance(router, token0Amt);
      IERC20Upgradeable(token1).safeIncreaseAllowance(router, token1Amt);
      IPancakeRouter02(router).addLiquidity(
        token0,
        token1,
        token0Amt,
        token1Amt,
        0,
        0,
        address(this),
        block.timestamp + 600
      );
    }

    _farm();
  }

  function inCaseTokensGetStuck(
    address _token,
    uint256 _amount,
    address _to
  ) public virtual onlyOwner {
    require(_token != cake, "!safe");
    require(_token != want, "!safe");
    IERC20Upgradeable(_token).safeTransfer(_to, _amount);
  }

  function _safeSwap(
    address _uniRouterAddress,
    uint256 _amountIn,
    uint256 _slippageFactor,
    address[] memory _path,
    address _to,
    uint256 _deadline
  ) internal virtual {
    uint256[] memory amounts = IPancakeRouter02(_uniRouterAddress).getAmountsOut(_amountIn, _path);
    uint256 amountOut = amounts[amounts.length - 1];

    IPancakeRouter02(_uniRouterAddress).swapExactTokensForTokensSupportingFeeOnTransferTokens(
      _amountIn,
      (amountOut * _slippageFactor) / SLIPPAGE_FACTOR_MAX,
      _path,
      _to,
      _deadline
    );
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function setAutoHarvest(bool _value) external onlyOwner {
    enableAutoHarvest = _value;
  }

  function setSlippageFactor(uint256 _slippageFactor) external onlyOwner {
    require(_slippageFactor <= SLIPPAGE_FACTOR_UL, "slippageFactor too high");
    slippageFactor = _slippageFactor;
  }

  function setMinEarnAmount(uint256 _minEarnAmount) external onlyOwner {
    require(_minEarnAmount >= MIN_EARN_AMOUNT_LL, "min earn amount is too low");
    minEarnAmount = _minEarnAmount;
  }

  function setPid(uint256 _pid) external onlyOwner {
    require(pid == 0, "pid already setted");
    pid = _pid;
  }
}