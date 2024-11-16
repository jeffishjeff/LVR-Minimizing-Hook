// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ERC6909Claims} from "v4-core/ERC6909Claims.sol";
import {ILiquidityPool} from "./interfaces/ILiquidityPool.sol";
import {PoolState, toPoolState} from "./types/PoolState.sol";
import {BaseHook} from "./BaseHook.sol";

/// @title LvrMinimizingHook
contract LvrMinimizingHook is ILiquidityPool, BaseHook, ERC6909Claims {
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

    function mint(PoolKey calldata key, uint256 liquidity, address recipient) external payable {
        PoolId poolId = key.toId();
        bytes memory data = abi.encode(); // TODO: create callback data

        poolManager.unlock(data);
        _mint(recipient, uint256(PoolId.unwrap(poolId)), liquidity);

        uint256 leftover = address(this).balance;
        if (leftover > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, leftover);
        }
    }

    function burn(PoolKey calldata key, uint256 liquidity, address recipient) external {
        PoolId poolId = key.toId();
        bytes memory data = abi.encode(); // TODO: create callback data

        poolManager.unlock(data);
        _burn(recipient, uint256(PoolId.unwrap(poolId)), liquidity);
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
}
