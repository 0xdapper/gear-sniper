// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IGLB, GearSniper} from "../src/GearSniper.sol";

IGLB constant GLB = IGLB(0xcB91F4521Fc43d4B51586E69F7145606b926b8D4);

contract GearSniperScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        new GearSniper(GLB);
    }
}
