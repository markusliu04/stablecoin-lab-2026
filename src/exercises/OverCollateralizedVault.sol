// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SimpleStablecoin} from "../SimpleStablecoin.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

/// @title Over-collateralized vault (Ex5)
/// @notice Unlike the 1:1 loop in Vault.sol, $1 of collateral deposited here mints at most
///         0.667 sUSD (a 150% collateral ratio). Once the collateral ratio falls below
///         120%, anyone can take that collateral at a discount by paying sUSD — that is
///         liquidation, the core mechanism behind MakerDAO.
///
///         Three decimal scales must be told apart:
///           collateral  18 decimals (like WETH)
///           stable       6 decimals (like USDC)
///           priceFeed    8 decimals (like Chainlink ETH/USD)
contract OverCollateralizedVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateral;
    SimpleStablecoin public immutable stable;
    IPriceFeed public immutable priceFeed;

    uint256 public constant RATIO_PRECISION = 100;
    uint256 public constant MIN_COLLATERAL_RATIO = 150; // 150% is the floor for minting
    uint256 public constant LIQUIDATION_RATIO = 120; // below 120% you can be liquidated
    uint256 public constant LIQUIDATION_BONUS = 10; // the liquidator takes an extra 10%

    /// @dev Collateral the user has deposited, 18 decimals
    mapping(address => uint256) public collateralOf;
    /// @dev Stablecoin the user owes, 6 decimals
    mapping(address => uint256) public debtOf;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed user, uint256 amount);
    event StableMinted(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    error ZeroAddress();
    error ZeroAmount();
    error Undercollateralized();
    error NotLiquidatable();
    error InsufficientCollateral();

    constructor(IERC20 collateral_, SimpleStablecoin stable_, IPriceFeed priceFeed_) {
        if (
            address(collateral_) == address(0) || address(stable_) == address(0)
                || address(priceFeed_) == address(0)
        ) {
            revert ZeroAddress();
        }
        collateral = collateral_;
        stable = stable_;
        priceFeed = priceFeed_;
    }

    // ==================================================================
    // Given to you — no decimal conversion involved, do not touch
    // ==================================================================

    /// @notice What one unit of collateral is worth in USD, 8 decimals
    /// @dev Production code would also check whether updatedAt is stale and whether
    ///      answer <= 0 — the oracle is an attack surface of its own
    function collateralPrice() public view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        if (answer <= 0) revert ZeroAmount();
        return uint256(answer);
    }

    /// @notice The user's collateral, converted into sUSD smallest units (6 decimals)
    function collateralValueOf(address user) public view returns (uint256) {
        return collateralValue(collateralOf[user]);
    }

    /// @notice Current collateral ratio; 150 means 150%. Returns the maximum when there is
    ///         no debt at all
    function collateralRatio(address user) public view returns (uint256) {
        if (debtOf[user] == 0) return type(uint256).max;
        return collateralValueOf(user) * RATIO_PRECISION / debtOf[user];
    }

    /// @notice Deposit collateral
    function depositCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;
        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Repay debt: burn sUSD and reduce what is owed
    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > debtOf[msg.sender]) revert InsufficientCollateral();
        stable.burn(msg.sender, amount);
        debtOf[msg.sender] -= amount;
    }

    // ==================================================================
    // Ex5.1 — decimal conversion
    // ==================================================================

    /// @notice Convert `amount` units of collateral (18 decimals) into sUSD smallest units
    ///         (6 decimals)
    /// @dev The product carries 18 + 8 = 26 decimals and we want 6 — divide by 10^20.
    function collateralValue(uint256 amount) public view returns (uint256) {
        return amount * collateralPrice() / 1e20;
    }

    // ==================================================================
    // Ex5.2 — minting has to leave enough collateral behind
    // ==================================================================

    /// @notice Mint `amount` of sUSD, but the collateral ratio afterwards must not fall
    ///         below MIN_COLLATERAL_RATIO
    /// @dev Record the debt first and check second, so that collateralRatio() is looking
    ///      at the post-mint state
    function mintStable(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        debtOf[msg.sender] += amount;
        if (collateralRatio(msg.sender) < MIN_COLLATERAL_RATIO) revert Undercollateralized();

        stable.mint(msg.sender, amount);
        emit StableMinted(msg.sender, amount);
    }

    // ==================================================================
    // Ex5.3 — withdrawing collateral must not leave the position unhealthy either
    // ==================================================================

    /// @notice Withdraw `amount` units of collateral; the ratio afterwards must not fall
    ///         below MIN_COLLATERAL_RATIO
    function redeemCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > collateralOf[msg.sender]) revert InsufficientCollateral();
        collateralOf[msg.sender] -= amount;
        if (collateralRatio(msg.sender) < MIN_COLLATERAL_RATIO) revert Undercollateralized();

        collateral.safeTransfer(msg.sender, amount);
        emit CollateralRedeemed(msg.sender, amount);
    }

    // ==================================================================
    // Ex5.4 — liquidation
    // ==================================================================

    /// @notice Once the ratio falls below LIQUIDATION_RATIO, anyone may burn that user's
    ///         entire sUSD debt and seize collateral worth
    ///         "debt value × (100% + LIQUIDATION_BONUS)".
    /// @dev Do not forget: the collateral may not be enough to pay that bonus. In that case
    ///      take everything the user has left — the shortfall is bad debt, and that is
    ///      exactly where liquidation is most fragile.
    function liquidate(address user) external {
        if (collateralRatio(user) >= LIQUIDATION_RATIO) revert NotLiquidatable();

        uint256 debt = debtOf[user];
        // Debt has 6 decimals. Multiplying by 10^20 before dividing by the 8-decimal
        // price gives 18-decimal collateral; apply the bonus before rounding down.
        uint256 seized = debt * (RATIO_PRECISION + LIQUIDATION_BONUS) * 1e20
            / (RATIO_PRECISION * collateralPrice());
        if (seized > collateralOf[user]) seized = collateralOf[user];

        debtOf[user] = 0;
        collateralOf[user] -= seized;
        stable.burn(msg.sender, debt);
        collateral.safeTransfer(msg.sender, seized);
        emit Liquidated(user, msg.sender, debt, seized);
    }
}
