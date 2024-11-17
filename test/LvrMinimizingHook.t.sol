// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "forge-std/Test.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Deployers} from "../lib/v4-core/test/utils/Deployers.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ILiquidityPool} from "../src/interfaces/ILiquidityPool.sol";
import {LvrMinimizingHook} from "../src/LvrMinimizingHook.sol";

contract LvrMinimizingHookTest is Test, Deployers {
    LvrMinimizingHook hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                    | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
            )
        );
        deployCodeTo("LvrMinimizingHook.sol", abi.encode(manager, address(0)), hookAddress);
        hook = LvrMinimizingHook(hookAddress);

        key = PoolKey(currency0, currency1, 3000, 60, hook);
        hook.initialize(ILiquidityPool.InitializeParams(key, SQRT_PRICE_1_1, 1000, 9000));
    }

    // function test_cannotAddLiqudityToPool() public {
    //     vm.expectRevert(abi.encodeWithSelector(LvrMinimizingHook.OnlyAddLiquidityViaHook.selector));
    //     manager.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    // }
}
