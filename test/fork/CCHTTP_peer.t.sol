//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {WETH9} from "@chainlink/contracts/src/v0.8/vendor/canonical-weth/WETH9.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";

import {Helper} from "../../script/Helper.sol";

import {CCHTTP_Peer} from "../../src/CCHTTP_Peer.sol";
import {ICCHTTP_Consumer} from "../../src/interfaces/ICCHTTP_Consumer.sol";
import {CCHTTP_Types} from "../../src/CCHTTP_Types.sol";

import {HyperABICoder} from "../../src/libraries/HyperABICoder.sol";
import {CCTCP_Types} from "../../src/CCTCP_Types.sol";
import {CCTCP_Host} from "../../src/CCTCP_Host.sol";

contract CCHTTP_PeerTest is ICCHTTP_Consumer, Test {

    event DebugTest(string message);
    event DebugBytesTest(bytes data);

    address payable user;

    address peerAddress;
    address hostAddress;

    CCHTTP_Peer arbPeer;
    CCTCP_Host arbHost;

    CCHTTP_Peer optPeer;
    CCTCP_Host optHost;

    CCIPLocalSimulatorFork simulator;
    uint256 arbForkId;
    uint256 optForkId;

    address arbLinkToken;
    address optLinkToken;

    address payable arbWrappedEther;
    address payable optWrappedEther;

    address arbRouter;
    address optRouter;

    uint64 arbChainSelector;
    uint64 optChainSelector;

    address arbWETHUSD_Aggregator;
    address arbLINKUSD_Aggregator;
    
    address optWETHUSD_Aggregator;
    address optLINKUSD_Aggregator;


    CCHTTP_Types.deploy_and_mint_mssg public DnM_sent;
    CCHTTP_Types.deploy_and_mint_mssg public DnM_received; 
    CCHTTP_Types.deploy_and_mint_mssg public DnM_confirmed;

    CCHTTP_Types.update_supply_mssg public updateSupply_sent;
    CCHTTP_Types.update_supply_mssg public updateSupply_received; 
    CCHTTP_Types.update_supply_mssg public updateSupply_confirmed;

    // Not used in this test, but can be used for future tests
    //address arbRegModule;
    //address optRegModule;

    function setUp() public {
        // Initialize the CCIP Local Simulator Fork       
        simulator = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(simulator));

        user = payable(makeAddr("user"));

        string memory arbURL = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        string memory opURL = vm.envString("OPTIMISM_SEPOLIA_RPC_URL");
        
        arbForkId = vm.createFork(arbURL);
        Register.NetworkDetails memory arbDetails = simulator.getNetworkDetails(
            421614 // Arbitrum Sepolia chain ID
        );
        arbLinkToken = arbDetails.linkAddress;
        arbWrappedEther = payable(arbDetails.wrappedNativeAddress);

        arbLINKUSD_Aggregator = 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298;
        arbWETHUSD_Aggregator = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

        arbChainSelector = arbDetails.chainSelector;
        arbRouter = arbDetails.routerAddress;        


        optForkId = vm.createFork(opURL);
        Register.NetworkDetails memory optDetails = simulator.getNetworkDetails(
            11155420 // Optimism Sepolia chain ID
        );
        optLinkToken = optDetails.linkAddress;
        optWrappedEther = payable(optDetails.wrappedNativeAddress);

        optChainSelector = optDetails.chainSelector;
        optRouter = optDetails.routerAddress;

        optWETHUSD_Aggregator = 0x0D41087ab4b10889312cc70A2582788270811c07;
        optLINKUSD_Aggregator = 0x53f91dA33120F44893CB896b12a83551DEDb31c6;

        bytes32 hostSalt = keccak256(abi.encodePacked("CCTCP_Host", address(this)));
        bytes32 peerSalt = keccak256(abi.encodePacked("CCHTTP_Peer", address(this)));

        vm.selectFork(arbForkId);

        // Deploy contracts Host and Peer first, then initialize them
        // This is to ensure that the addresses are deterministic and match the ones in the fork
        arbHost = new CCTCP_Host{salt: hostSalt}(user);
        hostAddress = address(arbHost);

        arbPeer = new CCHTTP_Peer{salt: peerSalt}();
        peerAddress = address(arbPeer);

        arbHost.init(
            arbChainSelector,
            arbRouter, // router
            arbLinkToken, // linkToken
            peerAddress, // peer
            address(0), //hyperLink not implemented and not used in this test
            arbWrappedEther, // wrappedNative
            arbWETHUSD_Aggregator, // WETH/USD aggregator
            arbLINKUSD_Aggregator // LINK/USD aggregator
        );
        //enable optimism in the host
        arbHost.enableChain(optChainSelector, optLinkToken);

        // Initialize the peer with necessary parameters
        arbPeer.init(
            arbChainSelector,
            arbRouter, // router
            arbLinkToken, // linkToken
            arbWrappedEther, // wrappedNative
            hostAddress, // host
            address(this) // hyperTokenFactory will be simulated in this test
        );

        vm.selectFork(optForkId);
        // Deploy the CCTCP_Host contract
        optHost = new CCTCP_Host{salt: hostSalt}(user);
        assertEq(hostAddress, address(optHost), "Host address mismatch");

        optPeer = new CCHTTP_Peer{salt: peerSalt}();
        assertEq(peerAddress, address(optPeer), "Peer address mismatch");

        // Initialize the host with necessary parameters
        optHost.init(
            optChainSelector,
            optRouter, // router
            optLinkToken, // linkToken
            peerAddress, // peer
            address(0), // hyperLink not implemented and not used in this test
            optWrappedEther, // wrappedNative
            optWETHUSD_Aggregator, // WETH/USD aggregator
            optLINKUSD_Aggregator // LINK/USD aggregator
        );
        //enable arbitrum in the host
        optHost.enableChain(arbChainSelector, arbLinkToken);

        // Initialize the peer with necessary parameters
        optPeer.init(
            optChainSelector,
            optRouter, // router
            optLinkToken, // linkToken
            optWrappedEther, // wrappedNative
            hostAddress, // host
            address(this) // hyperTokenFactory will be simulated in this test
        );

    }


    //ICCHTTP_Consumer implementation
    function DeployAndMintReceived(
        uint64 chain,
        CCHTTP_Types.deploy_and_mint_mssg memory params
    ) external override returns (bool) {
        //DnM_received = params; memory to storage? field by field plz
        DnM_received.name_length = params.name_length;
        DnM_received.name = params.name;
        DnM_received.symbol_length = params.symbol_length;
        DnM_received.symbol = params.symbol;
        DnM_received.decimals = params.decimals;
        DnM_received.deployer = params.deployer;
        DnM_received.chainSupply = params.chainSupply;
        DnM_received.expectedTokenAddress = params.expectedTokenAddress;
        DnM_received.tokenType = params.tokenType;
        DnM_received.backingToken = params.backingToken;
        DnM_received.tokenId = params.tokenId;
        emit log_named_string("DeployAndMintReceived", "Received deploy and mint message");
        return true;
    }

    function DeployAndMintConfirmed(
        uint64 chain,
        CCHTTP_Types.deploy_and_mint_mssg memory params
    ) external override returns (bool) {
        //DnM_confirmed = params; memory to storage? field by field plz
        DnM_confirmed.name_length = params.name_length;
        DnM_confirmed.name = params.name;
        DnM_confirmed.symbol_length = params.symbol_length;
        DnM_confirmed.symbol = params.symbol;
        DnM_confirmed.decimals = params.decimals;
        DnM_confirmed.deployer = params.deployer;
        DnM_confirmed.chainSupply = params.chainSupply;
        DnM_confirmed.expectedTokenAddress = params.expectedTokenAddress;
        DnM_confirmed.tokenType = params.tokenType;
        DnM_confirmed.backingToken = params.backingToken;
        DnM_confirmed.tokenId = params.tokenId;
        emit log_named_string("DeployAndMintConfirmed", "Confirmed deploy and mint message");
        return true;
    }


    function UpdateTotalSupplyReceived(
        uint64 chain,
        CCHTTP_Types.update_supply_mssg memory params
    ) external override returns (bool) {
        //updateSupply_received = params; memory to storage? field by field plz
        updateSupply_received.hyperToken = params.hyperToken;
        updateSupply_received.amount = params.amount;
        updateSupply_received.destination = params.destination;
        emit DebugTest("UpdateTotalSupplyReceived");
        emit DebugBytesTest(abi.encodePacked(params.hyperToken));
        emit DebugBytesTest(abi.encodePacked(params.destination));
        emit DebugBytesTest(abi.encodePacked(params.amount));

        emit log_named_string("UpdateTotalSupplyReceived", "Received update total supply message");
        return true;
    }


/*
    Disabled after design change: not broadcasting the update supply message to all chains
    function UpdateTotalSupplyConfirmed(
        uint64 chain,
        CCHTTP_Types.update_supply_mssg memory params
    ) external override returns (bool) {
        //updateSupply_confirmed = params; memory to storage? field by field plz
        updateSupply_confirmed.hyperToken = params.hyperToken;
        updateSupply_confirmed.newSupply = params.newSupply;
        updateSupply_confirmed.destination = params.destination;
        emit DebugTest("UpdateTotalSupplyConfirmed");
        emit DebugBytesTest(abi.encodePacked(params.hyperToken));
        emit DebugBytesTest(abi.encodePacked(params.newSupply));
        emit DebugBytesTest(abi.encodePacked(params.destination));
        
        emit log_named_string("UpdateTotalSupplyConfirmed", "Confirmed update total supply message");
        return true;
    }
*/


    function testDeployAndMintStack() public {
        vm.selectFork(optForkId);
        simulator.requestLinkFromFaucet(hostAddress, 10 ether);

        vm.selectFork(arbForkId);

        vm.deal(user, 1 ether); // Give user 1 ETH //for gas
        simulator.requestLinkFromFaucet(user, 10 ether); //for fees
        simulator.requestLinkFromFaucet(hostAddress, 10 ether); //for ACK fees

        vm.startPrank(user);
        WETH9(arbWrappedEther).deposit{value: 1 ether}(); // Wrap ETH to WETH
        
        CCHTTP_Types.deployAndMintParams memory params;
        params.chainId = optChainSelector;
        params.origin = msg.sender;
        params.destination = msg.sender;
        params.linkToken = arbLinkToken;
        params.linkAmount = 1e18; // 1 LINK
        params.feeToken = arbWrappedEther;
        params.feesAmount = 0.01 ether; // 0.01 ETH
        params.name_length = 4;
        params.name = "TEST";
        params.symbol_length = 3;
        params.symbol = "TST";
        params.decimals = 18;
        params.deployer = msg.sender;
        params.chainSupply = 1000 * 10 ** 18; // 1000 tokens
        params.expectedTokenAddress = address(0); // Not used in this test
        params.tokenType = CCHTTP_Types.HyperToken_Types.HyperUnbacked;
        params.backingToken = arbWrappedEther; // Wrapped Ether for native token
        params.tokenId = 0; // Not used in this test

        IERC20(arbLinkToken).approve(address(arbPeer), params.linkAmount);
        WETH9(arbWrappedEther).approve(address(arbPeer), params.feesAmount);

        bool success = arbPeer.deployAndMintRequest(params);
        assertTrue(success, "Deploy and mint request failed");

        DnM_sent.name_length = params.name_length;
        DnM_sent.name = params.name;
        DnM_sent.symbol_length = params.symbol_length;
        DnM_sent.symbol = params.symbol;
        DnM_sent.decimals = params.decimals;
        DnM_sent.deployer = params.deployer;
        DnM_sent.chainSupply = params.chainSupply;
        DnM_sent.expectedTokenAddress = params.expectedTokenAddress;
        DnM_sent.tokenType = params.tokenType;
        DnM_sent.backingToken = params.backingToken;
        DnM_sent.tokenId = params.tokenId;


        // Simulate the message being sent to the Optimism chain
        simulator.switchChainAndRouteMessage(optForkId);


        assertEq(DnM_received.name_length, params.name_length, "Name length mismatch on receiving chain");
        assertEq(DnM_received.name, params.name, "Name mismatch on receiving chain");
        assertEq(DnM_received.symbol_length, params.symbol_length, "Symbol length mismatch on receiving chain");
        assertEq(DnM_received.symbol, params.symbol, "Symbol mismatch on receiving chain");
        assertEq(DnM_received.deployer, params.deployer, "Deployer mismatch on receiving chain");
        assertEq(DnM_received.chainSupply, params.chainSupply, "Chain supply mismatch on receiving chain");
        assertEq(DnM_received.expectedTokenAddress, params.expectedTokenAddress, "Expected token address mismatch on receiving chain");
        assertEq(uint8(DnM_received.tokenType), uint8(params.tokenType), "Token type mismatch on receiving chain");
        assertEq(DnM_received.backingToken, params.backingToken, "Backing token mismatch on receiving chain");
        assertEq(DnM_received.tokenId, params.tokenId, "Token ID mismatch on receiving chain");

    
        // Simulate the confirmation of the message on the Arbitrum chain
        simulator.switchChainAndRouteMessage(arbForkId);
        assertEq(DnM_confirmed.name_length, params.name_length, "Name length mismatch on confirming chain");
        assertEq(DnM_confirmed.name, params.name, "Name mismatch on confirming chain");
        assertEq(DnM_confirmed.symbol_length, params.symbol_length, "Symbol length mismatch on confirming chain");
        assertEq(DnM_confirmed.symbol, params.symbol, "Symbol mismatch on confirming chain");
        assertEq(DnM_confirmed.deployer, params.deployer, "Deployer mismatch on confirming chain");
        assertEq(DnM_confirmed.chainSupply, params.chainSupply, "Chain supply mismatch on confirming chain");
        assertEq(DnM_confirmed.expectedTokenAddress, params.expectedTokenAddress, "Expected token address mismatch on confirming chain");
        assertEq( uint8(DnM_confirmed.tokenType), uint8(params.tokenType), "Token type mismatch on confirming chain");
        assertEq(DnM_confirmed.backingToken, params.backingToken, "Backing token mismatch on confirming chain");
        assertEq(DnM_confirmed.tokenId, params.tokenId, "Token ID mismatch on confirming chain");


        emit log_named_string("testDeployAndMintStack", "Deploy and mint stack test completed successfully");

        vm.stopPrank();
    }

    function testUpdateSupplyStack() public{
        vm.selectFork(optForkId);
        simulator.requestLinkFromFaucet(hostAddress, 10 ether);

        vm.selectFork(arbForkId);

        vm.deal(user, 1 ether); // Give user 1 ETH //for gas
        simulator.requestLinkFromFaucet(user, 10 ether); //for fees
        simulator.requestLinkFromFaucet(hostAddress, 10 ether); //for ACK fees

        vm.startPrank(user);
        WETH9(arbWrappedEther).deposit{value: 1 ether}(); // Wrap ETH to WETH
        
        // Prepare the update supply parameters
        CCHTTP_Types.updateSupplyParams memory params;
        params.chainId = optChainSelector;
        params.feeToken = arbWrappedEther;
        params.feesAmount = 0.01 ether; // 0.01 ETH
        params.amount = 1000 * 10 ** 18; // Amount to update supply
        params.hyperToken = address(0x1234567890123456789012345678901234567890); // Example hyper token address
        params.destination = address(0x0987654321098765432109876543210987654321); // Example destination address


        WETH9(arbWrappedEther).approve(address(arbPeer), params.feesAmount);

        // Act
        bool success = arbPeer.updateSupplyRequest(params);
        assertTrue(success, "Update supply request failed");

        // Store the sent message
        updateSupply_sent.hyperToken = params.hyperToken;
        updateSupply_sent.amount = params.amount;
        updateSupply_sent.destination = params.destination;

        // Simulate the message being sent to the Optimism chain
        simulator.switchChainAndRouteMessage(optForkId);

        // Assert the received message
        assertEq(updateSupply_received.hyperToken, params.hyperToken, "Hyper token mismatch on receiving chain");
        assertEq(updateSupply_received.amount, params.amount, "New supply mismatch on receiving chain");
        assertEq(updateSupply_received.destination, params.destination, "Destination mismatch on receiving chain");
        
        emit log_named_string("UpdateSupplyReceived", "Received update supply message");
    }
}
