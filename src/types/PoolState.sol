// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {PoolId} from "v4-core/types/PoolId.sol";

type PoolState is bytes32;

using PoolStateLibrary for PoolState global;

function toPoolState(
    PoolId poolId,
    uint16 liquidityRange,
    uint16 liquidityThreshold,
    uint16 arbitrageLiquidityPips,
    int24 tickLower,
    int24 tickUpper
) pure returns (PoolState state) {
    assembly {
        state := shl(96, shr(96, poolId))
        state := or(state, shl(80, liquidityRange))
        state := or(state, shl(64, liquidityThreshold))
        state := or(state, shl(48, arbitrageLiquidityPips))
        state := or(state, shl(24, tickLower))
        state := or(state, tickUpper)
    }
}

/// @title PoolStateLibrary
library PoolStateLibrary {
// TODO: add getter functions as we go along
}
