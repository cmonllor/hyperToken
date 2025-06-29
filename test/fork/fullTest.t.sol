//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {WETH9} from "@chainlink/contracts/src/v0.8/vendor/canonical-weth/WETH9.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";

import {Router} from "@chainlink/contracts-ccip/contracts/Router.sol";

import {Helper} from "../../script/Helper.sol";

import {HyperABICoder} from "../../src/libraries/HyperABICoder.sol";
import {CCTCP_Types} from "../../src/CCTCP_Types.sol";
import {CCTCP_Host} from "../../src/CCTCP_Host.sol";
import {CCHTTP_Types} from "../../src/CCHTTP_Types.sol";
import {CCHTTP_Peer} from "../../src/CCHTTP_Peer.sol";

import {ICCTCP_Consumer} from "../../src/interfaces/ICCTCP_Consumer.sol";
import {IHyperTokenFactory} from "../../src/interfaces/IHyperTokenFactory.sol";
import {HyperTokenFactory} from "../../src/hyperTokenFactory.sol";

import {IHyperTokenManager} from "../../src/interfaces/IHyperTokenManager.sol";
import {HyperTokenManager} from "../../src/hyperTokenManager.sol";

import { ProtocolFactory } from "../../src/ProtocolFactory.sol";

import {HyperToken} from "../../src/hyperToken.sol";
import {ERC20Backed_hyperToken} from "../../src/ERC20Backed_hyperToken.sol";
import {NativeBacked_hyperToken} from "../../src/nativeBacked_hyperToken.sol";
import {hyperLINK} from "../../src/hyperLINK.sol";


contract mockERC20 is ERC20, ERC20Burnable {
    using Strings for uint256;
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override {
        super.burnFrom(account, amount);
    }
}

contract mockERC721 is ERC721 {
    using Strings for uint256;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        bytes memory rtrString = abi.encodePacked('{\n');

        rtrString = abi.encodePacked(rtrString, '\t"name":"', name(), ',\n');
        rtrString = abi.encodePacked(rtrString, '\t"symbol":"', symbol(), ',\n');
        rtrString = abi.encodePacked(rtrString, '\t"tokenId":', tokenId.toString(), ',\n');
        rtrString = abi.encodePacked(rtrString, '\t"owner":"', Strings.toHexString(uint160(ownerOf(tokenId)), 20), '"\n');
        rtrString = abi.encodePacked(rtrString, "}");
        return string(rtrString);
    }
}

contract FullTest is Test{

    event DebugTest(string message);
    event DebugBytesTest(bytes data);
    event DebugBytesTest(string message, bytes data);

    struct deployment{
        ProtocolFactory protocolFactory;
        HyperTokenManager manager;
        HyperTokenFactory factory;
        CCHTTP_Peer cchttp_peer;
        CCTCP_Host cctcp_host;
        address hyperLink;
        address hyperNative;
    }

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
    }

    mapping (uint256 fork => chainInfo  ) chainDetails;
    mapping (uint256 fork => deployment ) deployments;

    mapping (uint256 fork => uint256 [4] ackCosts) ackFeePerFork;

    uint256 [] activeForks;

    address payable protocolDeployer;
    CCIPLocalSimulatorFork simulator;


    function initFork(
        uint256 chainId,
        string memory chainName,
        string memory nativeName,
        string memory nativeSymbol,
        string memory rpcURL,
        address LINKUSD_Aggregator,
        address NativeUSD_Aggregator
    ) internal {
        Register.NetworkDetails memory netDetails = simulator.getNetworkDetails(chainId);

        uint256 fork = vm.createFork(rpcURL);
        chainDetails[fork].chainId = chainId;
        chainDetails[fork].chainSelector = netDetails.chainSelector;
        chainDetails[fork].name = chainName;
        chainDetails[fork].nativeName = nativeName;
        chainDetails[fork].nativeSymbol = nativeSymbol;
        chainDetails[fork].linkTokenAddress = netDetails.linkAddress;
        chainDetails[fork].wrappedNativeAddress = netDetails.wrappedNativeAddress;
        chainDetails[fork].routerAddress = netDetails.routerAddress;
        chainDetails[fork].LINKUSD_Aggregator = LINKUSD_Aggregator;
        chainDetails[fork].NativeUSD_Aggregator = NativeUSD_Aggregator;
        activeForks.push(fork);
    }

    function deployProtocol() public {
        //assume protocolDeployer has been initialized
        vm.startPrank(protocolDeployer);

        for( uint256 i = 0; i < activeForks.length; i++ ){
            deployProtocolInFork(activeForks[i]);
        }

        vm.stopPrank();
    }

    function deployProtocolInFork(
        uint256 fork
    ) internal {
        //assume fork exists
        vm.selectFork(fork);
       
        Register.NetworkDetails memory netDetails = simulator.getNetworkDetails(chainDetails[fork].chainId);
        
        {
            bytes32 prot_FactorySalt = keccak256(
                abi.encodePacked(
                    "ProtocolFactory",
                    protocolDeployer
                )
            );

            deployments[fork].protocolFactory = new ProtocolFactory{ 
                salt: prot_FactorySalt
            }(
                protocolDeployer
            );

            deployments[fork].protocolFactory.loadCCTCPHostBytecode( 
                type(CCTCP_Host).creationCode
            );
            deployments[fork].protocolFactory.loadCCHTTPPeerBytecode( 
                type(CCHTTP_Peer).creationCode
            );
            deployments[fork].protocolFactory.loadFactoryBytecode( 
                type(HyperTokenFactory).creationCode
            );
            deployments[fork].protocolFactory.loadManagerBytecode( 
                type(HyperTokenManager).creationCode
            );

            address host = deployments[fork].protocolFactory.deploy_CCTCP_Host(
                protocolDeployer
            );
            deployments[fork].cctcp_host = CCTCP_Host(host);

            address peer = deployments[fork].protocolFactory.deploy_CCHTTP_Peer();
            deployments[fork].cchttp_peer = CCHTTP_Peer(peer);

            address factory = deployments[fork].protocolFactory.deployFactory(
                protocolDeployer
            );
            deployments[fork].factory = HyperTokenFactory(factory);

            address manager = deployments[fork].protocolFactory.deployManager(
                protocolDeployer
            );
            deployments[fork].manager = HyperTokenManager(manager);
        }

        deployments[fork].cctcp_host.init(
            chainDetails[fork].chainSelector, // chainSelector
            netDetails.routerAddress, // router
            netDetails.linkAddress, // linkToken
            address(deployments[fork].cchttp_peer), // cchttpPeer
            address(0), //hyperLink not implemented and not used in this test
            netDetails.wrappedNativeAddress, // wrappedNative
            chainDetails[fork].NativeUSD_Aggregator, // Native/USD aggregator
            chainDetails[fork].LINKUSD_Aggregator // LINK/USD aggregator
        );

        simulator.requestLinkFromFaucet( 
            address(deployments[fork].cctcp_host),
            30e18
        );

        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == fork ){
                continue;
            }
            deployments[fork].cctcp_host.enableChain(
                chainDetails[ activeForks[i] ].chainSelector, 
                chainDetails[ activeForks[i] ].linkTokenAddress 
            );

            deployments[ fork ].cctcp_host.setAckCost(
                chainDetails[ activeForks[i] ].chainSelector, 
                ackFeePerFork[fork][ activeForks[i] ] // ACK fee for this fork
            );
        }


        deployments[fork].cchttp_peer.init(
            chainDetails[fork].chainSelector,
            netDetails.routerAddress, // router
            netDetails.linkAddress, // linkToken
            netDetails.wrappedNativeAddress, // wrappedNative
            address(deployments[fork].cctcp_host), // host
            address(deployments[fork].factory) // hyperTokenFactory
        );

        {
            address rmn = netDetails.rmnProxyAddress;
            address regOwnerCustom = netDetails.registryModuleOwnerCustomAddress;
            address tar = netDetails.tokenAdminRegistryAddress;

            deployments[fork].factory.init(
                chainDetails[fork].chainSelector, // chainId
                netDetails.routerAddress, // router
                netDetails.linkAddress, // linkToken
                netDetails.wrappedNativeAddress, // wrappedNative
                chainDetails[fork].nativeName, // nativeName
                chainDetails[fork].nativeSymbol, // nativeSymbol
                18, // nativeDecimals
                tar, // tokenAdminRegistry
                regOwnerCustom, // registryModuleOwnerCustom
                rmn, // RMN
                address(deployments[fork].cchttp_peer), // CCHTTP_peer
                address(deployments[fork].manager) // hyperTokenManager
            );

            deployments[fork].manager.init(
                chainDetails[fork].chainSelector, // chainId
                netDetails.routerAddress, // router
                netDetails.linkAddress, // linkToken
                netDetails.wrappedNativeAddress, // wrappedNative
                chainDetails[fork].nativeName, // nativeName
                chainDetails[fork].nativeSymbol, // nativeSymbol
                18, // nativeDecimals
                address(deployments[fork].factory) // hyperTokenFactory
            );
        }
        
        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == fork ){
                continue;
            }
            deployments[fork].factory.enablePeerChain( chainDetails[activeForks[i]].chainSelector );
            deployments[fork].manager.enablePeerChain( chainDetails[activeForks[i]].chainSelector );
        }

        deployments[fork].factory.deployHyperLINK();
        deployments[fork].hyperLink = deployments[fork].factory.hyperLinkToken();

    }



    function deployHyperNativeInFork(
        uint256 fork
    ) internal {
        //assume fork exists
        vm.selectFork(fork);

        simulator.requestLinkFromFaucet( 
            protocolDeployer,
            3e18
        );

        vm.deal(protocolDeployer, 3e18);
        WETH9( payable(chainDetails[fork].wrappedNativeAddress) ).deposit{value: 3e18}();

        IERC20(chainDetails[fork].wrappedNativeAddress).approve(
            address(deployments[fork].factory),
            3e18
        );
        IERC20(chainDetails[fork].linkTokenAddress).approve(
            address(deployments[fork].factory),
            3e18
        );

        deployments[fork].manager.deployHyperNative();
        address hyperNativeAddress = deployments[fork].manager.hyperNativeToken();

        (uint256 fee, uint256 linkAmount) = deployments[fork].manager.estimateDeploymentCost(
            address(deployments[fork].hyperLink),
            chainDetails[fork].chainSelector,
            chainDetails[fork].wrappedNativeAddress,
            chainDetails[fork].linkTokenAddress            
        );

        uint256 sentFee = fee + (fee / 10); // add 10% buffer for fees
        uint256 sentLinkAmount = linkAmount + (linkAmount / 10); // add 10% buffer for ACK fees


        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == fork ){
                continue;
            }
            deployments[fork].manager.deployHyperTokenInChain(
                hyperNativeAddress,
                chainDetails[ activeForks[i] ].chainSelector,
                0, // chainSupply
                chainDetails[fork].wrappedNativeAddress,
                sentFee,
                chainDetails[fork].linkTokenAddress,
                sentLinkAmount
            );

            //route message
            simulator.switchChainAndRouteMessage( activeForks[i] );

            //simulate ACK
            simulator.switchChainAndRouteMessage( fork );
        }
    }


    struct deployERC20Backed_HyperTokenParams {
        uint256 fork;
        string name;
        string symbol;
        address backingToken;
        uint8 decimals;
        uint256[] chainSupplies; // same order as activeForks
        address tokenDeployer;
        address feeToken;
        address ackToken;
    }

    function deployERC20Backed_HyperTokenInFork(
        deployERC20Backed_HyperTokenParams memory params
    ) internal returns (address) {
        //assume fork exists
        vm.selectFork(params.fork);
        //set gas prices, high for ethereum sepolia low for the rest
        if( chainDetails[params.fork].chainId == 11155111 ){ //sepolia
            vm.txGasPrice(14 gwei);
        } else {
            vm.txGasPrice(1 gwei);
        }

        simulator.requestLinkFromFaucet( 
            params.tokenDeployer,
            30e18
        );
        vm.deal(params.tokenDeployer, 30e18);

        uint256 forkIdx;
        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == params.fork ){
                forkIdx = i;
                continue;
            }
        }
        require(forkIdx < activeForks.length, "Fork not found");

        IERC20(params.backingToken).approve(
            address(deployments[params.fork].manager),
            params.chainSupplies[forkIdx]
        );

        string memory hName = string(abi.encodePacked("hyper_", params.name));
        string memory hSymbol = string(abi.encodePacked("h", params.symbol));

        //assume all protocol contracts have been deployed in the fork
        address hyperToken = deployments[params.fork].manager.startHyperToken(
            hName,
            hSymbol,
            params.decimals,
            params.backingToken,
            0, // tokenId, 0 for ERC20 backed token
            params.chainSupplies[forkIdx],
            CCHTTP_Types.HyperToken_Types.HyperERC20
        );
        
        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == params.fork ){
                continue;
            }
            (uint256 fee, uint256 linkAmount) = deployments[params.fork].manager.estimateDeploymentCost(
                hyperToken,
                chainDetails[activeForks[i]].chainSelector,
                params.feeToken,
                params.ackToken
            );

            uint256 feeSent = fee + (fee / 10); // add 10% buffer for fees
            uint256 linkSent = linkAmount + (linkAmount / 10); // add 10% buffer for ACK fees

            if( params.feeToken == params.ackToken ){
                IERC20(params.feeToken).approve(
                    address(deployments[params.fork].manager),
                    feeSent + linkSent // assume enough balance for fees
                );
            } else {
                IERC20(params.feeToken).approve(
                    address(deployments[params.fork].manager),
                    feeSent
                );
                IERC20(params.ackToken).approve(
                    address(deployments[params.fork].manager),
                    linkSent
                );
            }

            deployments[params.fork].manager.deployHyperTokenInChain(
                hyperToken,
                chainDetails[activeForks[i]].chainSelector,
                params.chainSupplies[i], 
                params.feeToken, 
                feeSent, // fee amount
                params.ackToken, 
                linkSent // ACK fee, will be calculated later
            );

            //route message
            simulator.switchChainAndRouteMessage( activeForks[i] );

            //simulate ACK
            simulator.switchChainAndRouteMessage( params.fork );
        }
        return hyperToken;
    }

    struct deployERC721Backed_HyperTokenParams {
        uint256 fork;
        string name;
        string symbol;
        address backingToken;
        uint256 tokenId;
        uint8 decimals;
        uint256[] chainSupplies; // same order as activeForks
        address tokenDeployer;
        address feeToken;
        address ackToken;
    }

    function deployERC721Backed_HyperTokenInFork(
        deployERC721Backed_HyperTokenParams memory params
    ) internal returns (address) {
        //assume fork exists
        vm.selectFork(params.fork);
        //assume protocolDeployer has been initialized


        simulator.requestLinkFromFaucet( 
            params.tokenDeployer,
            3e18
        );
        vm.deal(params.tokenDeployer, 3e18);

        uint256 forkIdx;
        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == params.fork ){
                forkIdx = i;
                continue;
            }
        }
        require(forkIdx < activeForks.length, "Fork not found");

        IERC721(params.backingToken).approve(
            address(deployments[params.fork].manager),
            params.tokenId
        );

        string memory hName = string(abi.encodePacked("hyper_", params.name));
        string memory hSymbol = string(abi.encodePacked("h", params.symbol));

        //assume all protocol contracts have been deployed in the fork
        address hyperToken = deployments[params.fork].manager.startHyperToken(
            hName,
            hSymbol,
            params.decimals,
            params.backingToken,
            params.tokenId,
            params.chainSupplies[forkIdx],
            CCHTTP_Types.HyperToken_Types.HyperERC721
        );
        
        for( uint256 i = 0; i < activeForks.length; i++ ){
            if( activeForks[i] == params.fork ){
                emit DebugBytesTest( "Skipping fork: ", abi.encodePacked(activeForks[i]) );
                continue;
            }
            emit DebugBytesTest( "Deploying hyperNFT in fork: ", abi.encodePacked(activeForks[i]) );
            (uint256 fee, uint256 linkAmount) = deployments[params.fork].manager.estimateDeploymentCost(
                address(hyperToken),
                chainDetails[ activeForks[i] ].chainSelector,
                params.feeToken,
                params.ackToken
            );
            uint256 feeSent = fee + (fee / 10); // add 10% buffer for fees
            uint256 linkSent = linkAmount + (linkAmount / 10); // add 10% buffer for ACK fees

            if( params.feeToken == params.ackToken ){
                IERC20(params.feeToken).approve(
                    address(deployments[params.fork].manager),
                    feeSent + linkSent // assume enough balance for fees
                );
            } else {
                IERC20(params.feeToken).approve(
                    address(deployments[params.fork].manager),
                    feeSent
                );
                IERC20(params.ackToken).approve(
                    address(deployments[params.fork].manager),
                    linkSent
                );
            }
            deployments[params.fork].manager.deployHyperTokenInChain(
                hyperToken,
                chainDetails[activeForks[i]].chainSelector,
                params.chainSupplies[i],
                params.feeToken,
                feeSent, // fee
                params.ackToken, // ackToken
                linkAmount // ACK fee
            );
            //route message
            simulator.switchChainAndRouteMessage( activeForks[i] );

            //simulate ACK
            simulator.switchChainAndRouteMessage( params.fork );

        }
        vm.stopPrank();
        return hyperToken;
    }

    struct makeCrossChainTransferParams {
        uint256 fork;
        address from;
        address to;
        address hyperToken;
        uint256 amount;
        uint256 targetFork;
        address feeToken;
        uint256 gasLimit;
    }

    function makeCrossChainTransfer(
        makeCrossChainTransferParams memory params
    ) internal {
        //assume fork exists
        vm.selectFork(params.fork);
        //assume protocolDeployer has been initialized
        vm.startPrank(params.from);

        Client.EVMTokenAmount[] memory sentTokens = new Client.EVMTokenAmount[](1);
        sentTokens[0] = Client.EVMTokenAmount({
            token: params.hyperToken,
            amount: params.amount
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(params.to),
            data: new bytes(0),
            tokenAmounts: sentTokens,
            feeToken: params.feeToken,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: params.gasLimit}))
        });

        IRouterClient router = IRouterClient(chainDetails[params.fork].routerAddress);

        
        emit DebugBytesTest(
            "Cross-chain transfer message to chain:",
            abi.encodePacked(chainDetails[params.targetFork].chainSelector)
        );

        uint256 feeAmount = router.getFee(
            chainDetails[params.targetFork].chainSelector,
            message
        );

        IERC20(params.feeToken).approve(address(router), (feeAmount + feeAmount/10)); // add 10% buffer for fees
        IERC20(params.hyperToken).approve(address(router), params.amount);

        router.ccipSend(
            chainDetails[params.targetFork].chainSelector,
            message
        );

        simulator.switchChainAndRouteMessage(params.targetFork);

        vm.stopPrank();
    }



    //setUp: fill chainDetails, deployments, and activeForks
    function setUp() public {
        protocolDeployer = payable( makeAddr("protocolDeployer") );

        simulator = new CCIPLocalSimulatorFork();
        vm.makePersistent( address(simulator) );

        vm.startPrank(protocolDeployer);
        
        //ETHETREUM SEPPOLIA FORK
        initFork(
            11155111, //sepolia chainId
            "Ethereum Sepolia",
            "Ether(Sepolia)",
            "ETH",
            vm.envString("ETHEREUM_SEPOLIA_RPC_URL"),
            0xc59E3633BAAC79493d908e63626716e204A45EdF, //LINK/USD Aggregator hardcoded :(
            0x694AA1769357215DE4FAC081bf1f309aDC325306 //Native/USD Aggregator hardcoded :(
        );
        ackFeePerFork[ activeForks[0] ] = [
            0,
             36e15,
             36e15,
             36e15
        ]; 
        
        //Arbitrum Sepolia Fork
        initFork(
            421614, //arbitrum sepolia chainId
            "Arbitrum Sepolia",
            "Arbitrum Ether(Sepolia)",
            "arbETH",
            vm.envString("ARBITRUM_SEPOLIA_RPC_URL"),
            0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298, //LINK/USD Aggregator hardcoded :(
            0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
        );
        ackFeePerFork[ activeForks[1] ] = [
            124e15,
            0,
             98e15,
             98e15
        ];

        //OP Sepolia Fork
        initFork(
            11155420, //op sepolia chainId
            "Optimism Sepolia",
            "Optimism Ether(Sepolia)",
            "opETH",
            vm.envString("OPTIMISM_SEPOLIA_RPC_URL"),
            0x98EeB02BC20c5e7079983e8F0D0D839dFc8F74fA,
            0x61Ec26aA57019C486B10502285c5A3D4A4750AD7
        );
        ackFeePerFork[ activeForks[2] ] = [
             38e15,
             11e15,
             0,
             12e15
        ];

        //Avalanche Fuji Fork
        initFork(
            43113, //avalanche fuji chainId
            "Avalanche Fuji",
            "Avax(Fuji)",
            "AVAX",
            vm.envString("AVALANCHE_FUJI_RPC_URL"),
            0x34C4c526902d88a3Aa98DB8a9b802603EB1E3470,
            0x5498BB86BC934c8D34FDA08E81D444153d0D06aD
        );
        ackFeePerFork[ activeForks[3] ] = [
             36e15,
            103e15,
             10e15,
            0
        ];
    }

    
    function contractExistsInFork(
        uint256 fork,
        address contractAddress
    ) internal returns (bool) {
        vm.selectFork(fork);
        return contractAddress.code.length > 0;
    }

    function testDeployment() public {
        deployProtocol();
        for( uint256 i = 0; i < activeForks.length; i++ ){
            //check hyperLink contract exists
            assertEq(
                true,
                contractExistsInFork(
                    activeForks[i],
                    deployments[activeForks[i]].hyperLink
                ),
                string(abi.encodePacked("hyperLink contract not deployed in fork: ", Strings.toString(activeForks[i])))
            );
            for( uint256 j = 0; j < activeForks.length; j++ ){
                if( i == j ){
                    continue;
                }
                //check hyperLink has the same address in all forks
                assertEq(
                    deployments[activeForks[i]].hyperLink,
                    deployments[activeForks[j]].hyperLink,  
                    string(abi.encodePacked("hyperLink contract address mismatch between forks: ", Strings.toString(activeForks[i]), " and ", Strings.toString(activeForks[j])))
                );
            }
        }
    }    

    function testHyperLinkCrossChainTransfer() public {
        address bob = makeAddr("bob");
        address alice = makeAddr("alice");

        deployProtocol();

        //check hyperLINK is deployed in all forks
        for( uint256 i = 0; i < activeForks.length; i++ ){
            assertEq(
                true,
                contractExistsInFork(
                    activeForks[i],
                    deployments[activeForks[i]].hyperLink
                ),
                string(abi.encodePacked("hyperLink contract not deployed in fork: ", Strings.toString(activeForks[i])))
            );
        }

        for ( uint256 i = 0; i < activeForks.length; i++ ){
            for( uint256 j = 0; j < activeForks.length; j++ ){
                if( i == j ){
                    continue;
                }

                vm.selectFork(activeForks[i]);
            
                emit DebugTest( 
                    string( 
                        abi.encodePacked( 
                            "Testing cross-chain transfer from forked ", 
                            chainDetails[ activeForks[i] ].name , 
                            " to fork: ", 
                            chainDetails[ activeForks[j] ].name 
                        ) 
                    )
                );

                
                simulator.requestLinkFromFaucet( 
                    bob,
                    5e18
                );

                vm.startPrank(bob);
                uint256 bobBalanceBefore = IERC20(  deployments[ activeForks[i] ].hyperLink  ).balanceOf(bob);

                IERC20(chainDetails[activeForks[i]].linkTokenAddress).approve(
                    deployments[activeForks[i]].hyperLink,
                    4e18
                );
                hyperLINK(deployments[activeForks[0]].hyperLink).wrapLink(4e18); // wrap 1 LINK

                assertEq(
                    hyperLINK(deployments[activeForks[0]].hyperLink).balanceOf(bob),
                    bobBalanceBefore + 4e18,
                    "Bob should have 4 hyperLINK more than before wrapping"
                );

                vm.selectFork(activeForks[j]);
                uint256 aliceBalance = hyperLINK(  deployments[ activeForks[j] ].hyperLink  ).balanceOf(alice);
                vm.selectFork(activeForks[i]);

                emit DebugTest( "Trying crosschaintransfer from bob to alice");
                makeCrossChainTransfer(
                    makeCrossChainTransferParams({
                        fork: activeForks[i],
                        from: bob,
                        to: alice,
                        hyperToken: deployments[activeForks[i]].hyperLink,
                        amount: 1e18,
                        targetFork: activeForks[j], //arbitrum sepolia
                        feeToken: chainDetails[activeForks[i]].linkTokenAddress,
                        gasLimit: 3000000
                    })
                );
                
                assertEq(
                    hyperLINK(deployments[activeForks[j]].hyperLink).balanceOf(alice),
                    aliceBalance + 1e18,
                    string(abi.encodePacked("Alice should have 1 hyperLINK in fork: ", Strings.toString(activeForks[j])))
                );
                vm.stopPrank();
            }
        }
    }

    function testHyperERC20CrossChainTransfer() public {
        deployProtocol();
        address bob = makeAddr("bob");
        address alice = makeAddr("alice");

        address [] memory backingTokens = new address[](activeForks.length);
        address [] memory hyperTokens = new address[](activeForks.length);
        
        mockERC20  tokenMock;

        for( uint256 i = 0; i < activeForks.length; i++ ){
            //deploy mockERC10 as backing token
            string memory bckName = string(abi.encodePacked("mockNFT_", Strings.toString(i+1)));
            string memory bckSymbol = string(abi.encodePacked("mNFT_", Strings.toString(i+1)));

            bytes32 forkSalt = keccak256(abi.encodePacked("mockNFT", activeForks[i], bckName, bckSymbol));
            vm.selectFork(activeForks[i]);
            if( i==0){ //ethereum sepolia
                vm.txGasPrice(4e9); //40 Gwei
            }
            else{ //other chains
                vm.txGasPrice(17e8); //1.7 Gwei
            }

            tokenMock = new mockERC20{salt: forkSalt}(
                bckName,
                bckSymbol
            );
            backingTokens[i] = address(tokenMock);
            tokenMock.mint(bob, 4e18);
 
            simulator.requestLinkFromFaucet( 
                bob,
                5e18
            );
            vm.startPrank(bob);

            //deploy HyperERC20 token in fork i
            hyperTokens[i] = deployERC20Backed_HyperTokenInFork(
                deployERC20Backed_HyperTokenParams({
                    fork: activeForks[i],
                    name: string(abi.encodePacked("Test Token",activeForks[i])),
                    symbol: string(abi.encodePacked("TTK",Strings.toString(activeForks[i]))),
                    backingToken: backingTokens[i],
                    decimals: 18,
                    chainSupplies: new uint256[](activeForks.length),
                    tokenDeployer: bob,
                    feeToken: chainDetails[activeForks[i]].linkTokenAddress,
                    ackToken: chainDetails[activeForks[i]].linkTokenAddress
                })
            );

            IERC20(backingTokens[i]).approve(hyperTokens[i], 4e18);
            ERC20Backed_hyperToken(hyperTokens[i]).wrap(4e18);
            assertEq(
                ERC20Backed_hyperToken(hyperTokens[i]).balanceOf(bob),
                4e18,
                "Bob should have 4 hyperTTK"
            );
            
            for ( uint256 j = 0; j < activeForks.length; j++ ){
                if( i == j ){
                    continue;
                }

                vm.selectFork(activeForks[i]);
                vm.startPrank(bob);

                emit DebugTest( 
                    string( 
                        abi.encodePacked( 
                            "Testing cross-chain transfer from forked ", 
                            chainDetails[ activeForks[i] ].name , 
                            " to fork: ", 
                            chainDetails[ activeForks[j] ].name 
                        ) 
                    )
                );

                IERC20(address(tokenMock)).approve(
                    hyperTokens[i],
                    1e18
                );
                
                              

                vm.selectFork(activeForks[j]);
                uint256 aliceBalance = IERC20(hyperTokens[i]).balanceOf(alice);
                
                emit DebugTest( "Trying crosschaintransfer from bob to alice");
                
                makeCrossChainTransfer(
                    makeCrossChainTransferParams({
                        fork: activeForks[i],
                        from: bob,
                        to: alice,
                        hyperToken: hyperTokens[i],
                        amount: 1e18, // 1 hTTK
                        targetFork: activeForks[j], 
                        feeToken: chainDetails[activeForks[i]].linkTokenAddress,
                        gasLimit: 3000000
                    })
                );

                assertEq(
                    IERC20(hyperTokens[i]).balanceOf(alice),
                    aliceBalance + 1e18,
                    string(
                        abi.encodePacked(
                            "Alice should have 1 hyperTTK more in fork: ", 
                            Strings.toString(activeForks[j]) 
                        )
                    )
                );
            }
            for(uint256 j=0; j<activeForks.length; j++){
                if(i==j){
                    continue;
                }
                vm.stopPrank();
                vm.startPrank(alice);

                vm.selectFork(activeForks[i]);
                uint256 mockTk_aliceBalance = IERC20(backingTokens[i]).balanceOf(alice);

                vm.selectFork(activeForks[j]);

                simulator.requestLinkFromFaucet(
                    alice,
                    1e17
                );
                

                uint256 unwrapFee = deployments[ activeForks[i] ].factory.estimateUpdateSupplyCost(
                    chainDetails[ activeForks[i] ].chainSelector,
                    hyperTokens[i],
                    chainDetails[ activeForks[j] ].linkTokenAddress
                );
                unwrapFee = (unwrapFee * 105) / 100; // 5% buffer for spikes
                simulator.requestLinkFromFaucet(
                    alice,
                    unwrapFee
                );
                IERC20(chainDetails[ activeForks[j] ].linkTokenAddress).approve(hyperTokens[i], unwrapFee);

                ERC20Backed_hyperToken(hyperTokens[i]).unwrap(
                    1e18,
                    chainDetails[ activeForks[j] ].linkTokenAddress,
                    unwrapFee
                );

                simulator.switchChainAndRouteMessage(activeForks[i]);
                assertEq(
                    IERC20(backingTokens[i]).balanceOf(alice),
                    mockTk_aliceBalance + 1e18,
                    "Alice should have 1 mockTk more"
                );
                vm.stopPrank();
            }
        }                
    }

    function testHyperERC721CrossChainTransfer() public {
        deployProtocol();
        address bob = makeAddr("bob");
        address alice = makeAddr("alice");

        address [] memory backingTokens = new address[](activeForks.length);
        uint256 [] memory backingTokenIds = new uint256[](activeForks.length);
        address [] memory hyperTokens = new address[](activeForks.length);
        
        mockERC721  nftMock;
        uint256 currentId = 0xffffffff0000; 

        for( uint256 i = 0; i < activeForks.length; i++ ){
            //deploy mockERC10 as backing token
            string memory bckName = string(abi.encodePacked("mockERC20_", Strings.toString(i+1)));
            string memory bckSymbol = string(abi.encodePacked("mERC20_", Strings.toString(i+1)));

            bytes32 forkSalt = keccak256(abi.encodePacked("mockERC20", activeForks[i], bckName, bckSymbol));
            vm.selectFork(activeForks[i]);
            vm.startPrank(bob);
            if( i==0){ //ethereum sepolia
                vm.txGasPrice(4e9); //40 Gwei
            }
            else{ //other chains
                vm.txGasPrice(17e8); //1.7 Gwei
            }

            
            nftMock = new mockERC721{salt: forkSalt}(
                bckName,
                bckSymbol
            );
            backingTokens[i] = address(nftMock);

            nftMock.mint(bob, currentId);
            backingTokenIds[i] = currentId;
            currentId++;

            

            simulator.requestLinkFromFaucet( 
                bob,
                300e18
            );
            
            uint256 [] memory chainSupplies = new uint256[](activeForks.length);
            for(uint256 k=0;k<chainSupplies.length;k++){
                chainSupplies[k] = (100+k)* 1e18;
            }
            //deploy HyperERC20 token in fork i
            hyperTokens[i] = deployERC721Backed_HyperTokenInFork(
                deployERC721Backed_HyperTokenParams({
                    fork: activeForks[i],
                    name: string(abi.encodePacked("Test NFT",Strings.toString(activeForks[i]))),
                    symbol: string(abi.encodePacked("TNFT",Strings.toString(activeForks[i]))),
                    backingToken: backingTokens[i],
                    tokenId: backingTokenIds[i],
                    decimals: 18,
                    chainSupplies: chainSupplies,
                    tokenDeployer: bob,
                    feeToken: chainDetails[activeForks[i]].linkTokenAddress,
                    ackToken: chainDetails[activeForks[i]].linkTokenAddress
                })
            );
            vm.selectFork( activeForks[i] );
            assertEq(
                IERC721(backingTokens[i]).ownerOf(backingTokenIds[i]),
                hyperTokens[i],
                "Owner of NFT should be hyperToken"
            );
       
            for(uint256 k=0; k<chainSupplies.length; k++){
                vm.selectFork( activeForks[k] );
                assertEq(
                    IERC20(hyperTokens[i]).balanceOf(bob),
                    (100+k)*1e18,
                    "Bob should have hyperTTK"
                );
            }
            for ( uint256 j = 0; j < activeForks.length; j++ ){
                if( i == j ){
                    continue;
                }

                vm.selectFork(activeForks[i]);

                emit DebugTest( 
                    string( 
                        abi.encodePacked( 
                            "Testing cross-chain transfer from forked ", 
                            chainDetails[ activeForks[i] ].name , 
                            " to fork: ", 
                            chainDetails[ activeForks[j] ].name 
                        ) 
                    )
                );                           

                vm.selectFork(activeForks[j]);
                uint256 aliceBalance = IERC20(hyperTokens[i]).balanceOf(alice);
                
                emit DebugTest( "Trying crosschaintransfer from bob to alice");
                
                makeCrossChainTransfer(
                    makeCrossChainTransferParams({
                        fork: activeForks[i],
                        from: bob,
                        to: alice,
                        hyperToken: hyperTokens[i],
                        amount: 1e18, // 1 hTTK
                        targetFork: activeForks[j], 
                        feeToken: chainDetails[activeForks[i]].linkTokenAddress,
                        gasLimit: 3000000
                    })
                );

                assertEq(
                    IERC20(hyperTokens[i]).balanceOf(alice),
                    aliceBalance + 1e18,
                    string(
                        abi.encodePacked(
                            "Alice should have 1 hyperTTK more in fork: ", 
                            Strings.toString(activeForks[j]) 
                        )
                    )
                );
            }
        }                
    }
}