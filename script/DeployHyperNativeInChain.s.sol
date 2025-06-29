// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
 
import {Script, console} from "forge-std/Script.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {Helper} from "../script/Helper.sol";

import {HyperTokenManager} from "../src/hyperTokenManager.sol";
import {CCHTTP_Types} from "../src/CCHTTP_Types.sol";

contract DeployHyperNativeInChain is Script, Helper {
    using Strings for uint256;

    address public hyperTokenManagerAddress;

    struct chainInfo{
        uint256 chainId;
        uint64 chainSelector;
        string name;
        string nativeName;
        string nativeSymbol;
        address linkTokenAddress;
        address wrappedNativeAddress;
        address routerAddress;
        address LINKUSD_Aggregator;
        address NativeUSD_Aggregator;
        address FeeQuoterAddress; 
        string rpcURL;
    }

    CCIPLocalSimulatorFork public simulator;
    mapping (uint256 => chainInfo) public chainDetails;
    uint64 []  activeChains;

    address public deployer;

    function initChain(
        uint256 chainId,
        string memory chainName,
        string memory nativeName,
        string memory nativeSymbol,
        string memory rpcURL,
        address LINKUSD_Aggregator,
        address NativeUSD_Aggregator
    ) internal {
        uint256 chain = activeChains.length;
        Register.NetworkDetails memory netDetails = simulator.getNetworkDetails(chainId);

        chainDetails[chain].chainId = chainId;
        chainDetails[chain].chainSelector = netDetails.chainSelector;
        chainDetails[chain].name = chainName;
        chainDetails[chain].nativeName = nativeName;
        chainDetails[chain].nativeSymbol = nativeSymbol;
        chainDetails[chain].linkTokenAddress = netDetails.linkAddress;
        chainDetails[chain].wrappedNativeAddress = netDetails.wrappedNativeAddress;
        chainDetails[chain].routerAddress = netDetails.routerAddress;
        chainDetails[chain].LINKUSD_Aggregator = LINKUSD_Aggregator;
        chainDetails[chain].NativeUSD_Aggregator = NativeUSD_Aggregator;
        chainDetails[chain].rpcURL = rpcURL;
        activeChains.push(netDetails.chainSelector);
    }

    function initChains() internal {    
        //ETHETREUM SEPPOLIA FORK
        initChain(
            11155111, //sepolia chainId
            "Ethereum Sepolia",
            "Ether(Sepolia)",
            "ETH",
            vm.envString("ETHEREUM_SEPOLIA_RPC_URL"),
            0xc59E3633BAAC79493d908e63626716e204A45EdF, //LINK/USD Aggregator hardcoded :(
            0x694AA1769357215DE4FAC081bf1f309aDC325306 //Native/USD Aggregator hardcoded :(
        );
         
        
        //Arbitrum Sepolia Chain
        initChain(
            421614, //arbitrum sepolia chainId
            "Arbitrum Sepolia",
            "Arbitrum Ether(Sepolia)",
            "arbETH",
            vm.envString("ARBITRUM_SEPOLIA_RPC_URL"),
            0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298, //LINK/USD Aggregator hardcoded :(
            0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
        );
        

        //OP Sepolia Chain
        initChain(
            11155420, //op sepolia chainId
            "Optimism Sepolia",
            "Optimism Ether(Sepolia)",
            "opETH",
            vm.envString("OPTIMISM_SEPOLIA_RPC_URL"),
            0x98EeB02BC20c5e7079983e8F0D0D839dFc8F74fA,
            0x61Ec26aA57019C486B10502285c5A3D4A4750AD7
        );
        
        /*
        Problems deploying: DISABLED FOR NOW

        //Avalanche Fuji Chain
        initChain(
            43113, //avalanche fuji chainId
            "Avalanche Fuji",
            "Avax(Fuji)",
            "AVAX",
            vm.envString("AVALANCHE_FUJI_RPC_URL"),
            0x34C4c526902d88a3Aa98DB8a9b802603EB1E3470,
            0x5498BB86BC934c8D34FDA08E81D444153d0D06aD
        );
        ackFeePerChain[ activeChains[3] ] = [
             36e15,
            103e15,
             10e15,
            0
        ];

        */
    }



    function setUp() public {
        simulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(simulator));
        initChains();

        hyperTokenManagerAddress = 0xefC2d9473C29AC3C3177c422d39eCa5F28905E1b; // HyperTokenManager address
    }

    function run(uint chainIdx) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        HyperTokenManager manager = HyperTokenManager(hyperTokenManagerAddress);

        manager.deployHyperNative();
        address hyperNative = manager.hyperNativeToken();

        for (uint i=0; i < activeChains.length; i++) {
            if(i == chainIdx) {
                continue; // skip the current chain
            }

            (uint256 fee, uint256 ackFee) = manager.estimateDeploymentCost(
                hyperNative,
                activeChains[i],
                chainDetails[chainIdx].linkTokenAddress,
                chainDetails[chainIdx].linkTokenAddress
            );

            fee = fee + 1e17; // add 0.1 LINK for safety

            IERC20(chainDetails[chainIdx].linkTokenAddress).approve(
                hyperTokenManagerAddress,
                fee + ackFee + 1e18 // add 1 LINK for safety
            );

            manager.deployHyperTokenInChain(
                hyperNative,
                activeChains[i],
                0, //supply 0 for native tokens
                chainDetails[chainIdx].linkTokenAddress,
                fee,
                chainDetails[chainIdx].linkTokenAddress,
                ackFee + 1e18 // add 1 LINK for safety
            );
        }
    }
}