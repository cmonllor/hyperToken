// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
 
import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {Helper} from "../script/Helper.sol";

import {CCHTTP_Peer} from "../src/CCHTTP_Peer.sol";
import {CCHTTP_Types} from "../src/CCHTTP_Types.sol";

import {CCTCP_Host} from "../src/CCTCP_Host.sol";
import {CCHTTP_Peer} from "../src/CCHTTP_Peer.sol";

import {HyperTokenFactory} from "../src/hyperTokenFactory.sol";
import {HyperTokenManager} from "../src/hyperTokenManager.sol";
import {ProtocolFactory} from "../src/ProtocolFactory.sol";

import {HyperToken} from "../src/hyperToken.sol";
import {ERC20Backed_hyperToken} from "../src/ERC20Backed_hyperToken.sol";
import {ERC721Backed_hyperToken} from "../src/ERC721Backed_hyperToken.sol";
import {NativeBacked_hyperToken} from "../src/nativeBacked_hyperToken.sol";
import {hyperLINK} from "../src/hyperLINK.sol";


 
contract DeployProtocolsScript is Script {

    struct deployment{
        ProtocolFactory protFactory;
        HyperTokenManager manager;
        HyperTokenFactory hTFactory;
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
        string rpcURL;
    }

    address public protocolDeployer;
    CCIPLocalSimulatorFork simulator;

    uint256 [] activeChains;

    mapping (uint256 chainIdx => chainInfo  ) chainDetails;
    mapping (uint256 chainIdx => deployment ) deployments;

    mapping (uint256 chainIdx => uint256 [4] ackCosts) ackFeePerChain;


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



    function deployProtocol(uint num) public {    
        uint256 pk = vm.envUint( "PRIVATE_KEY" );
        protocolDeployer = vm.addr(pk);

        vm.startBroadcast( pk );
        deployProtocolInChain(activeChains[num]);
        vm.stopBroadcast();
    }




    function deployProtocolInChain(
        uint256 chain
    ) internal {
        //assume chain exists        
       
        Register.NetworkDetails memory netDetails = simulator.getNetworkDetails(chainDetails[chain].chainId);
        
        {
            bytes32 prot_FactorySalt = keccak256(
                abi.encodePacked(
                    "ProtocolFactory 1.4",
                    protocolDeployer
                )
            );

            deployments[chain].protFactory = new ProtocolFactory{ 
                salt: prot_FactorySalt
            }(
                protocolDeployer
            );

            ERC20Backed_hyperToken erc20_hT_impl = new ERC20Backed_hyperToken(
                "", // name
                "", // symbol
                18 // decimals
            );
            NativeBacked_hyperToken native_hT_impl = new NativeBacked_hyperToken(
                "", // name
                "", // symbol
                18 // decimals
            );
            ERC721Backed_hyperToken erc721_hT_impl = new ERC721Backed_hyperToken(
                "", // name
                "", // symbol
                18 // decimals
            );

            deployments[chain].protFactory.loadERC20Backed_hyperTokenImpl(
                address(erc20_hT_impl)
            );
            deployments[chain].protFactory.loadNativeBacked_hyperTokenImpl(
                address(native_hT_impl)
            );
            deployments[chain].protFactory.loadERC721Backed_hyperTokenImpl(
                address(erc721_hT_impl)
            );

            deployments[chain].protFactory.loadCCTCPHostBytecode( 
                type(CCTCP_Host).creationCode
            );
            deployments[chain].protFactory.loadCCHTTPPeerBytecode( 
                type(CCHTTP_Peer).creationCode
            );
            deployments[chain].protFactory.loadFactoryBytecode( 
                type(HyperTokenFactory).creationCode
            );
            deployments[chain].protFactory.loadManagerBytecode( 
                type(HyperTokenManager).creationCode
            );

            address host = deployments[chain].protFactory.deploy_CCTCP_Host(
                protocolDeployer
            );
            deployments[chain].cctcp_host = CCTCP_Host(host);

            IERC20(netDetails.linkAddress).transfer(
                host,
                3e18 // transfer 1 million LINK to the host
            );

            address peer = deployments[chain].protFactory.deploy_CCHTTP_Peer();
            deployments[chain].cchttp_peer = CCHTTP_Peer(peer);

            address factory = deployments[chain].protFactory.deployFactory(
                protocolDeployer
            );
            deployments[chain].hTFactory = HyperTokenFactory(factory);

            address manager = deployments[chain].protFactory.deployManager(
                protocolDeployer
            );
            deployments[chain].manager = HyperTokenManager(manager);
        }

        deployments[chain].cctcp_host.init(
            chainDetails[chain].chainSelector, // chainSelector
            netDetails.routerAddress, // router
            netDetails.linkAddress, // linkToken
            address(deployments[chain].cchttp_peer), // cchttpPeer
            address(0), //hyperLink not implemented and not used in this test
            netDetails.wrappedNativeAddress, // wrappedNative
            chainDetails[chain].NativeUSD_Aggregator, // Native/USD aggregator
            chainDetails[chain].LINKUSD_Aggregator // LINK/USD aggregator
        );


        //TODO transfer LINK to CCTCP_Host deployment


        for( uint256 i = 0; i < activeChains.length; i++ ){
            if( activeChains[i] == chain ){
                continue;
            }
            deployments[chain].cctcp_host.enableChain(
                chainDetails[activeChains[i]].chainSelector, 
                chainDetails[activeChains[i]].linkTokenAddress 
            );
        }

        deployments[chain].cchttp_peer.init(
            chainDetails[chain].chainSelector,
            netDetails.routerAddress, // router
            netDetails.linkAddress, // linkToken
            netDetails.wrappedNativeAddress, // wrappedNative
            address(deployments[chain].cctcp_host), // host
            address(deployments[chain].hTFactory) // hyperTokenFactory
        );

        {
            address rmn = netDetails.rmnProxyAddress;
            address regOwnerCustom = netDetails.registryModuleOwnerCustomAddress;
            address tar = netDetails.tokenAdminRegistryAddress;

            deployments[chain].hTFactory.init(
                chainDetails[chain].chainSelector, // chainId
                netDetails.routerAddress, // router
                netDetails.linkAddress, // linkToken
                netDetails.wrappedNativeAddress, // wrappedNative
                chainDetails[chain].nativeName, // nativeName
                chainDetails[chain].nativeSymbol, // nativeSymbol
                18, // nativeDecimals
                tar, // tokenAdminRegistry
                regOwnerCustom, // registryModuleOwnerCustom
                rmn, // RMN
                address(deployments[chain].cchttp_peer), // CCHTTP_peer
                address(deployments[chain].manager) // HyperTokenManager
            );

            deployments[chain].manager.init(
                chainDetails[chain].chainSelector, // chainId
                netDetails.routerAddress, // router
                netDetails.linkAddress, // linkToken
                netDetails.wrappedNativeAddress, // wrappedNative
                chainDetails[chain].nativeName, // nativeName
                chainDetails[chain].nativeSymbol, // nativeSymbol
                18, // nativeDecimals
                address(deployments[chain].hTFactory) // hyperTokenFactory
            );
        }
        
        for( uint256 i = 0; i < activeChains.length; i++ ){
            if( activeChains[i] == chain ){
                continue;
            }
            deployments[chain].hTFactory.enablePeerChain( chainDetails[i].chainSelector );
            deployments[chain].manager.enablePeerChain( chainDetails[i].chainSelector );

            deployments[ chain ].cctcp_host.setAckCost(
                chainDetails[ activeChains[i] ].chainSelector,
                ackFeePerChain[ activeChains[i] ][chain]
            );
            
        }

        deployments[chain].hTFactory.deployHyperLINK();
        deployments[chain].hyperLink = deployments[chain].hTFactory.hyperLinkToken();

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
        ackFeePerChain[ activeChains[0] ] = [
            0,
             36e15,
             36e15,
             36e15
        ]; 
        
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
        ackFeePerChain[ activeChains[1] ] = [
            124e15,
            0,
             98e15,
             98e15
        ];

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
        ackFeePerChain[ activeChains[2] ] = [
             38e15,
             11e15,
             0,
             12e15
        ];
        /*
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
    }



    function run(uint256 num) public {
        deployProtocol(num);
    }
}