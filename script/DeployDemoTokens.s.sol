// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
 
import {Script, console} from "forge-std/Script.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {Helper} from "../script/Helper.sol";

import {ERC20Demo} from "../src/demo/ERC20_demo.sol";
import {ERC721Demo} from "../src/demo/ERC721_demo.sol";

contract DeployDemoTokens is Script, Helper {
    using Strings for uint256;

    CCIPLocalSimulatorFork public simulator;
    mapping (uint256 => string) public chainNames;
    uint64 []  activeChains;


    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);

        address demoERC20 = address(new ERC20Demo(1000000 * 10 ** 18));
        address demoERC721 = address(new ERC721Demo("DemoNFT", "DNFT"));

        console.log("Deployed ERC20 Demo Token at: ", demoERC20);
        console.log("Deployed ERC721 Demo Token at: ", demoERC721);

        vm.stopBroadcast();
    }
}
