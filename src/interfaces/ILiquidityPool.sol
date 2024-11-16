// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @title ILiquidityPool
interface ILiquidityPool {
    struct InitializeParams {
        PoolKey key;
        uint160 sqrtPriceX96;
        uint16 liquidityRange;
        uint16 arbitrageLiquidityPips;
    }

    function initialize(InitializeParams calldata params) external;

    struct ModifyLiquidityData {
        PoolKey key;
        int256 liquidityDelta;
        address sender;
    }

    function mint(PoolKey calldata key, uint256 liquidity) external payable;
    function burn(PoolKey calldata key, uint256 liquidity) external;
}
