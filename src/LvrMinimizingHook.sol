// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ERC6909Claims} from "v4-core/ERC6909Claims.sol";
import {ILiquidityPool} from "./interfaces/ILiquidityPool.sol";
import {PoolState, toPoolState} from "./types/PoolState.sol";
import {BaseHook} from "./BaseHook.sol";

/// @title LvrMinimizingHook
contract LvrMinimizingHook is ILiquidityPool, IUnlockCallback, BaseHook, ERC6909Claims {
    error OnlyPoolManager();
    error InvalidHookAddress();
    error AlreadyInitialized();
    error OnlyInitializeViaHook();
    error OnlyAddLiquidityViaHook();
    error OnlyRemoveLiquidityViaHook();

    IPoolManager private immutable poolManager;
    mapping(PoolId => PoolState) private poolStates;

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), OnlyPoolManager());
        _;
    }

    constructor(IPoolManager poolManager_) {
        uint160 mask = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
        require(uint160(address(this)) & mask == mask, InvalidHookAddress());

        poolManager = poolManager_;
    }

    function initialize(InitializeParams memory params) external {
        params.key.tickSpacing = 1; // note: only support key.tickSpacing == 1 for now
        PoolId poolId = params.key.toId();
        require(PoolState.unwrap(poolStates[poolId]) == bytes32(0), AlreadyInitialized());

        int24 tick = poolManager.initialize(params.key, params.sqrtPriceX96);

        poolStates[poolId] = toPoolState(
            params.liquidityRange,
            params.arbitrageLiquidityPips,
            tick - int16(params.liquidityRange),
            tick + int16(params.liquidityRange)
        );
    }

    function mint(PoolKey calldata key, uint256 liquidity) external payable {
        poolManager.unlock(abi.encode(ModifyLiquidityData(key, int256(liquidity), msg.sender)));
        _mint(msg.sender, uint256(PoolId.unwrap(key.toId())), liquidity);

        uint256 leftover = address(this).balance;
        if (leftover > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, leftover);
        }
    }

    function burn(PoolKey calldata key, uint256 liquidity) external {
        _burn(msg.sender, uint256(PoolId.unwrap(key.toId())), liquidity);
        poolManager.unlock(abi.encode(ModifyLiquidityData(key, -int256(liquidity), msg.sender)));
    }

    function unlockCallback(bytes calldata callbackData) external onlyPoolManager returns (bytes memory) {
        ModifyLiquidityData memory data = abi.decode(callbackData, (ModifyLiquidityData));
        PoolState poolState = poolStates[data.key.toId()];

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            data.key,
            IPoolManager.ModifyLiquidityParams(poolState.tickLower(), poolState.tickUpper(), data.liquidityDelta, ""),
            ""
        );

        if (delta.amount0() < 0) _settle(data.key.currency0, uint128(-delta.amount0()), data.sender);
        if (delta.amount1() < 0) _settle(data.key.currency1, uint128(-delta.amount1()), data.sender);
        if (delta.amount0() > 0) _take(data.key.currency0, uint128(delta.amount0()), data.sender);
        if (delta.amount1() > 0) _take(data.key.currency1, uint128(delta.amount1()), data.sender);

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

    // TODO: before/after swap

    function _settle(Currency currency, uint256 amount, address payer) private {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            if (payer == address(this)) {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(poolManager), amount);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
            }
            poolManager.settle();
        }
    }

    function _take(Currency currency, uint256 amount, address recipient) private {
        poolManager.take(currency, recipient, amount);
    }
}
