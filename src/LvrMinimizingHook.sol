// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {ILiquidityPool} from "./interfaces/ILiquidityPool.sol";
import {BaseHook} from "./BaseHook.sol";

/// @title LvrMinimizingHook
contract LvrMinimizingHook is ILiquidityPool, BaseHook {}
