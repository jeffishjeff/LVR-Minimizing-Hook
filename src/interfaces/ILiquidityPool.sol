// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {PoolKey} from "v4-core/types/PoolKey.sol";

/// @title ILiquidityPool
interface ILiquidityPool {
    struct InitializeParams {
        PoolKey key;
        uint160 sqrtPriceX96;
        uint16 liquidityRange;
        uint16 liquidityThreshold;
        uint16 arbitrageLiquidityPips;
    }

    function initialize(InitializeParams calldata params) external;
}
