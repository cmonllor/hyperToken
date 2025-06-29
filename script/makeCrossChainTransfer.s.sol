// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
 
import {Script, console} from "forge-std/Script.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

contract MakeCrossChainTransfer is Script {
    using Strings for uint256;

    CCIPLocalSimulatorFork simulator;

    uint256 [] activeChains;

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

    mapping (uint256 chainIdx => chainInfo  ) chainDetails;

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
        activeChains.push(chain);
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
    }

    function setUp() public {
        simulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(simulator));
        initChains();
    }

    function run(
        address hyperToken,
        address destination,
        uint256 destinationChainId,
        uint256 amount,
        address linkToken
    ) external {
        vm.startBroadcast();

        

        // Get the chain index for the destination chain
        uint256 destinationChainIdx = 0;
        for (uint256 i = 0; i < activeChains.length; i++) {
            if (chainDetails[i].chainId == destinationChainId) {
                destinationChainIdx = i;
                break;
            }
        }
        
        Client.EVMTokenAmount[] memory sentTokens = new Client.EVMTokenAmount[](1);
        sentTokens[0] = Client.EVMTokenAmount({
            token: hyperToken,
            amount: amount
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destination),
            data: new bytes(0),
            tokenAmounts: sentTokens,
            feeToken: linkToken,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 1000000 }))
        });

        IRouterClient router = IRouterClient(chainDetails[destinationChainIdx].routerAddress);

        uint256 fee = router.getFee(
            chainDetails[destinationChainIdx].chainSelector,
            message
        );
        console.log("Estimated fee for cross-chain transfer: %s", fee);
        IERC20(linkToken).approve(
            address(router),
            fee
        );
        bytes32 ccipId = router.ccipSend(
            chainDetails[destinationChainIdx].chainSelector,
            message
        );
        console.log("CCIP ID for cross-chain transfer: %s", Strings.toHexString(uint256(ccipId)));

        vm.stopBroadcast();
    }
}