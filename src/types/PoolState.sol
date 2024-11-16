// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

type PoolState is bytes32;

using PoolStateLibrary for PoolState global;

function toPoolState(uint16 liquidityRange, uint16 arbitrageLiquidityPips, int24 tickLower, int24 tickUpper)
    pure
    returns (PoolState state)
{
    assembly {
        state := shl(64, liquidityRange)
        state := or(state, shl(48, arbitrageLiquidityPips))
        state := or(state, shl(24, tickLower))
        state := or(state, tickUpper)
    }
}

/// @title PoolStateLibrary
library PoolStateLibrary {
    function tickLower(PoolState self) internal pure returns (int24 tickLower_) {
        assembly {
            tickLower_ := shr(232, shl(208, self))
        }
    }

    function tickUpper(PoolState self) internal pure returns (int24 tickUpper_) {
        assembly {
            tickUpper_ := shr(232, shl(232, self))
        }
    }
}
