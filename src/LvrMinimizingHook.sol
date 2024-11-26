// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.26;

import {BrevisApp} from "brevis-contracts/sdk/apps/framework/BrevisApp.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {CurrencySettler} from "../lib/v4-core/test/utils/CurrencySettler.sol";
import {LiquidityAmounts} from "../lib/v4-core/test/utils/LiquidityAmounts.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ERC6909Claims} from "v4-core/ERC6909Claims.sol";
import {ILiquidityPool} from "./interfaces/ILiquidityPool.sol";
import {BaseHook} from "./BaseHook.sol";

/// @title LvrMinimizingHook
contract LvrMinimizingHook is ILiquidityPool, IUnlockCallback, BaseHook, ERC6909Claims, BrevisApp {
    error OnlyPoolManager();
    error InvalidHookAddress();
    error InvalidVerifyingKey();
    error AlreadyInitialized();
    error BlockNotOpened();
    error BlockAlreadyOpened();
    error OnlyInitializeViaHook();
    error OnlyAddLiquidityViaHook();
    error OnlyRemoveLiquidityViaHook();

    struct PoolState {
        uint16 liquidityRange;
        uint16 arbitrageLiquidityPips;
        int24 tickLower;
        int24 tickUpper;
    }

    using CurrencySettler for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    uint128 private constant PIPS_DENOMINATOR = 10_000;

    bytes32 private vkHash;
    uint256 private variance;
    uint256 private lastBlockOpened;
    IPoolManager private immutable poolManager;
    mapping(PoolId => PoolState) private poolStates;

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), OnlyPoolManager());
        _;
    }

    constructor(IPoolManager poolManager_, address brevisReques_) BrevisApp(brevisReques_) {
        uint160 mask = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        require(uint160(address(this)) & mask == mask, InvalidHookAddress());

        poolManager = poolManager_;
    }

    function initialize(InitializeParams memory params) external {
        params.key.tickSpacing = 1; // note: only support key.tickSpacing == 1 for now
        PoolId poolId = params.key.toId();
        require(poolStates[poolId].tickLower == 0 && poolStates[poolId].tickUpper == 0, AlreadyInitialized());

        int24 tick = poolManager.initialize(params.key, params.sqrtPriceX96);

        poolStates[poolId] = PoolState(
            params.liquidityRange,
            params.arbitrageLiquidityPips,
            tick - int16(params.liquidityRange),
            tick + int16(params.liquidityRange)
        );
    }

    function mint(PoolKey calldata key, uint256 liquidity) external payable {
        poolManager.unlock(abi.encode(ModifyLiquidityData(key, int256(liquidity), msg.sender, 0)));
        _mint(msg.sender, uint256(PoolId.unwrap(key.toId())), liquidity);

        uint256 leftover = address(this).balance;
        if (leftover > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, leftover);
        }
    }

    function burn(PoolKey calldata key, uint256 liquidity) external {
        _burn(msg.sender, uint256(PoolId.unwrap(key.toId())), liquidity);
        poolManager.unlock(abi.encode(ModifyLiquidityData(key, -int256(liquidity), msg.sender, 0)));
    }

    function open(PoolKey calldata key, uint160 newSqrtPriceX96) external payable {
        require(block.number > lastBlockOpened, BlockAlreadyOpened());

        PoolId poolId = key.toId();
        uint128 liquidity = poolManager.getLiquidity(poolId);
        lastBlockOpened = block.number;

        poolManager.unlock(
            abi.encode(
                ModifyLiquidityData(
                    key,
                    -int128(liquidity * poolStates[poolId].arbitrageLiquidityPips / PIPS_DENOMINATOR),
                    msg.sender,
                    newSqrtPriceX96
                )
            )
        );

        uint256 leftover = address(this).balance;
        if (leftover > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, leftover);
        }
    }

    function unlockCallback(bytes calldata callbackData) external onlyPoolManager returns (bytes memory) {
        ModifyLiquidityData memory data = abi.decode(callbackData, (ModifyLiquidityData));
        PoolState memory poolState = poolStates[data.key.toId()];

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            data.key,
            IPoolManager.ModifyLiquidityParams(poolState.tickLower, poolState.tickUpper, data.liquidityDelta, ""),
            ""
        );

        if (data.newSqrtPriceX96 == 0) {
            if (delta.amount0() < 0) {
                data.key.currency0.settle(poolManager, data.sender, uint128(-delta.amount0()), false);
            }
            if (delta.amount1() < 0) {
                data.key.currency1.settle(poolManager, data.sender, uint128(-delta.amount1()), false);
            }
            if (delta.amount0() > 0) data.key.currency0.take(poolManager, data.sender, uint128(delta.amount0()), false);
            if (delta.amount1() > 0) data.key.currency1.take(poolManager, data.sender, uint128(delta.amount1()), false);
        } else {
            (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(data.key.toId());

            delta = poolManager.swap(
                data.key,
                IPoolManager.SwapParams(data.newSqrtPriceX96 < sqrtPriceX96, type(int256).min, data.newSqrtPriceX96),
                ""
            );

            if (delta.amount0() < 0) {
                data.key.currency0.settle(poolManager, data.sender, uint128(-delta.amount0()), false);
            }
            if (delta.amount1() < 0) {
                data.key.currency1.settle(poolManager, data.sender, uint128(-delta.amount1()), false);
            }
            if (delta.amount0() > 0) data.key.currency0.take(poolManager, data.sender, uint128(delta.amount0()), false);
            if (delta.amount1() > 0) data.key.currency1.take(poolManager, data.sender, uint128(delta.amount1()), false);
        }

        return "";
    }

    function beforeInitialize(address sender, PoolKey calldata, uint160)
        external
        view
        override
        onlyPoolManager
        returns (bytes4)
    {
        require(sender == address(this), OnlyInitializeViaHook());

        return this.beforeInitialize.selector;
    }

    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        require(sender == address(this), OnlyAddLiquidityViaHook());

        return this.beforeAddLiquidity.selector;
    }

    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4) {
        require(sender == address(this), OnlyRemoveLiquidityViaHook());

        return this.beforeRemoveLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        require(block.number == lastBlockOpened, BlockNotOpened());

        return (this.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId poolId = key.toId();

        PoolState memory poolState = poolStates[poolId];
        uint128 liquidity = poolManager.getLiquidity(poolId);
        poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(poolState.tickLower, poolState.tickUpper, -int128(liquidity), ""),
            ""
        );
        uint256 amount0 = uint256(poolManager.currencyDelta(address(this), key.currency0));
        uint256 amount1 = uint256(poolManager.currencyDelta(address(this), key.currency1));

        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);
        uint160 lowerSqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick - int16(poolState.liquidityRange));
        uint160 upperSqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick + int16(poolState.liquidityRange));
        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, upperSqrtPriceX96, amount0);
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtPriceX96, lowerSqrtPriceX96, amount1);

        if (liquidity0 > liquidity1) {
            upperSqrtPriceX96 = uint160(sqrtPriceX96 * liquidity1 / (liquidity1 - amount0 * sqrtPriceX96));
        } else if (liquidity1 > liquidity0) {
            lowerSqrtPriceX96 = uint160((sqrtPriceX96 * liquidity0 - amount1) / liquidity0);
        }

        int24 tickLower = TickMath.getTickAtSqrtPrice(lowerSqrtPriceX96);
        int24 tickUpper = TickMath.getTickAtSqrtPrice(upperSqrtPriceX96);
        poolStates[poolId].tickLower = tickLower;
        poolStates[poolId].tickUpper = tickUpper;

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                tickLower, tickUpper, int128(liquidity0 > liquidity1 ? liquidity1 : liquidity0), ""
            ),
            ""
        );

        poolManager.clear(key.currency0, amount0 - uint128(-delta.amount0()));
        poolManager.clear(key.currency1, amount1 - uint128(-delta.amount1()));

        return (this.afterSwap.selector, 0);
    }

    function handleProofResult(bytes32 vkHash_, bytes calldata circuitOutput_) internal override {
        require(vkHash == vkHash_, InvalidVerifyingKey());

        variance = uint248(bytes31(circuitOutput_[0:31]));
    }

    function setVkHash(bytes32 vkHash_) external {
        vkHash = vkHash_;
    }
}
