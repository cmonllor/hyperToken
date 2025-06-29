//SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { ERC1967Proxy } from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { WETH9 } from "@chainlink/contracts/src/v0.8/vendor/canonical-weth/WETH9.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { RegistryModuleOwnerCustom } from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import { ITokenAdminRegistry } from "@chainlink/contracts-ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
//import { RateLimiter } from "@chainlink/contracts-ccip/contracts/libraries/RateLimiter.sol";

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";

//import { LockReleaseTokenPool } from "./mods/LockReleaseTokenPool.sol";
//import { BurnMintTokenPool } from "./mods/BurnMintTokenPool.sol";
//import { TokenPool } from "./mods/TokenPool.sol";
import { IMinimalBnMPool } from "./interfaces/IMinimalBnMPool.sol";

import { IProtocolFactory } from "./interfaces/IProtocolFactory.sol";

import { IHyperTokenFactory } from "./interfaces/IHyperTokenFactory.sol";
import { ICCHTTP_Consumer } from "./interfaces/ICCHTTP_Consumer.sol";
import { ICCHTTP_Peer } from "./interfaces/ICCHTTP_Peer.sol";

import { IHyperToken } from "./interfaces/IHyperToken.sol";
import { IERC20Backed_HyperToken } from "./interfaces/IERC20Backed_HyperToken.sol";
import { INativeBacked_HyperToken } from "./interfaces/INativeBacked_HyperToken.sol";
import { IERC721Backed_HyperToken } from "./interfaces/IERC721Backed_HyperToken.sol";
import { IHyperLINK } from "./interfaces/IHyperLINK.sol";
import { IHyperLinkPool } from "./interfaces/IHyperLinkPool.sol";

import { IHyperTokenManager } from "./interfaces/IHyperTokenManager.sol";

import { ICCHTTP_Peer } from "./interfaces/ICCHTTP_Peer.sol";
import { CCHTTP_Types } from "./CCHTTP_Types.sol";

import { FeesManager } from "./FeesManager.sol";


contract HyperTokenFactory is IHyperTokenFactory, ICCHTTP_Consumer, FeesManager, Ownable {
    using SafeERC20 for IERC20;
    event HyperTokenStarted(address indexed hyperToken);
    event DeploymentSent(address indexed hyperToken, uint64 chainId);
    event DeploymentReceived(address indexed hyperToken, uint64 chainId);

    event HyperTokenDeployed(address indexed hyperToken);

    event Debug(string message);
    event DebugBytes(string message, bytes data);
    event NonRevertingError(string message, bytes data);

    uint64 public chainId;
    address public router;

    string public nativeName;
    string public nativeSymbol;
    uint8 public nativeDecimals;

    address public tokenAdminRegistry;
    address public regOwnerCustom;
    address public RMN;

    uint64 [] public enabledPeerChains;

    address public protocolFactory;
    address public manager;
    address public CCHTTP_peer;

    struct deployHyperTokenParams {
        uint64 motherChainId;
        string name;
        string symbol;
        uint8 decimals;
        address backingToken;
        uint256 tokenId; // For ERC721, the token ID
        uint256 chainSupply;
        address tokenOwner;
        CCHTTP_Types.HyperToken_Types tokenType; // Type of the hyper token (ERC20, ERC721, etc.)
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this function");
        _;
    }

    constructor( address protocolDeployer )  Ownable() { 
        transferOwnership(protocolDeployer);
        protocolFactory = msg.sender; // Set the protocol factory address
    }

    function init(
        uint64 _chainId,
        address _router,
        address _linkToken,
        address _wrappedNative,
        string calldata _nativeName,
        string calldata _nativeSymbol,
        uint8 _nativeDecimals,
        address _tokenAdminRegistry,
        address _regOwnerCustom,
        address _RMN,
        address _CCHTTP_peer,
        address _manager
    ) external onlyOwner {
        chainId = _chainId;
        router = _router;
        linkToken = _linkToken;

        wrappedNative = payable(_wrappedNative);
        nativeName = _nativeName;
        nativeSymbol = _nativeSymbol;
        nativeDecimals = _nativeDecimals;

        tokenAdminRegistry = _tokenAdminRegistry;
        regOwnerCustom = _regOwnerCustom;
        RMN = _RMN;
        
        CCHTTP_peer = _CCHTTP_peer;
        manager = _manager;

    }

    function enablePeerChain(uint64 _chainId) external onlyOwner {
        emit DebugBytes("enablePeerChain: enabling peer chain: ", abi.encodePacked(_chainId));
        // Check if the chain is already enabled
        for (uint256 i = 0; i < enabledPeerChains.length; i++) {
            if (enabledPeerChains[i] == _chainId) {
                revert("Chain already enabled");
            }
        }
        // Add the chain to the list of enabled peer chains
        enabledPeerChains.push(_chainId);
    }



    function deployHyperLINK() external onlyOwner {
        emit Debug("deployHyperLINK: deploying hyperLINK token");
        hyperLinkToken = IProtocolFactory(protocolFactory).createHyperLINK();
        emit Debug("deployHyperLINK: hyperLINK created");
        emit DebugBytes("deployHyperLINK: hyperLinkToken: ", abi.encodePacked(hyperLinkToken));

        IHyperLINK hyperLinkCtr = IHyperLINK(hyperLinkToken);

        hyperLinkCtr.init(
            chainId, // Set the mother chain ID
            linkToken // Set the link token address
        );

        address hyperLinkPoolAddress = IProtocolFactory(protocolFactory).createHyperLinkPool(
            hyperLinkToken // Hyperlink token address
        );
        IHyperLinkPool linkPool = IHyperLinkPool(hyperLinkPoolAddress);
        linkPool.init(
            linkToken
        );
        emit Debug("deployHyperLINK: hyperLinkPool created");
        emit DebugBytes("deployHyperLINK: hyperLinkPool: ", abi.encodePacked(address(linkPool)));


        address CCIP_Pool = deployCCIP_Pool(
            hyperLinkToken, // HyperToken address
            0, // motherChain: 0 so all hyperLINK CCIP_pools share address in all EVM chains
            18 // Decimals of the token
        );

        IHyperTokenManager(manager).saveHyperTokenInfo(
            hyperLinkToken,
            "hyperLINK", // Name of the token
            "hLINK", // Symbol of the token
            18, // Decimals of the token
            CCHTTP_Types.HyperToken_Types.HyperERC20, // Type of the hyper token
            linkToken, // Backing token address
            0, // Token ID for ERC20 is not used
            CCIP_Pool, // Pool address
            chainId, // Mother chain ID
            0, // Total supply is not tracked in hyperLinkToken
            msg.sender // Token owner is the contract deployer
        );
        

        hyperLinkCtr.setLinkPool(address(linkPool)); // Set the link pool address in the hyperLINK contract      

        // Register the hyperLINK token in the TokenAdminRegistry
        registerHyperToken(hyperLinkToken);
        hyperLinkToken = hyperLinkToken; // Set the hyperLINK token address
    }



    function deployHyperNative(
        uint64 motherChain,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address backing,  
        address tokenOwner              
    ) external onlyManager returns (address){
        return _deployHyperNative(
            motherChain,
            name,
            symbol,
            decimals,
            backing,  
            tokenOwner              
        );
    }



    function _deployHyperNative(
        uint64 motherChain,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address backing,  
        address tokenOwner              
    ) internal returns (address) {
        address proxyAddr = IProtocolFactory(protocolFactory).createNativeBacked_hyperToken(
            name, // Name of the token
            symbol, // Symbol of the token
            decimals // Decimals of the token
        );
        emit Debug("createNativeBacked_hyperToken: ERC1967Proxy created");
        emit DebugBytes("createNative_hyperToken: hyperTokenAdd: ", abi.encodePacked(proxyAddr));
    
        // Create a NativeBacked_hyperToken instance
        INativeBacked_HyperToken hyperNativeCtr = INativeBacked_HyperToken(proxyAddr);

        hyperNativeCtr.init(
            motherChain==chainId ? 0 : motherChain, // Set the mother chain ID to 0 for native tokens in mother chain
            // mother chain ID: 0 for native tokens in mother chain
            name, // Set the name of the token
            symbol, // Set the symbol of the token
            decimals, // Set the decimals of the token
            backing, // Set the backing token address
            address(0), // Pool address will be set later
            wrappedNative, // Wrapped native token address
            linkToken, // Link token address
            hyperLinkToken // Hyperlink token address
        );

        address pool = deployCCIP_Pool(
            address(hyperNativeCtr), // HyperToken address
            motherChain, // Mother chain ID
            nativeDecimals // Decimals of the token
        );
        emit Debug("deployHyperNative: CCIP_Pool deployed for hyperNative");

        emit Debug("deployHyperNative: NativeBacked_hyperToken initialized");

        IHyperTokenManager(manager).saveHyperTokenInfo(
            address(hyperNativeCtr),
            name, // Name of the token
            symbol, // Symbol of the token
            decimals, // Decimals of the token
            CCHTTP_Types.HyperToken_Types.HyperNative, // Type of the hyper token
            backing, // Backing token address
            0, // Token ID for native is not used
            pool, // Pool address
            motherChain, // Mother chain ID
            0, // Total supply is initially 0
            tokenOwner // Token owner is the contract deployer
        );
        emit Debug("deployHyperNative: HyperToken info saved in manager");
        return proxyAddr;               
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // This function is called when the contract receives an ERC721 token
        // We can use this to set the backing NFT if it wasn't set in the constructor
        emit Debug("onERC721Received: ERC721 token received");        
        return IERC721Receiver.onERC721Received.selector;
    }
 

    function deployHyperToken(
        deployHyperTokenParams memory params
    ) internal returns (address) {
        address hyperTokenAdd;
        uint64 motherChainInToken = params.motherChainId;

        if(params.motherChainId == chainId){
            motherChainInToken = 0; //mother chain is 0 for hyperTokens in motherchain
        }
        
        if( params.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ) {
            // Create a  ERC20Backed_hyperToken instance
            hyperTokenAdd = IProtocolFactory(protocolFactory).createERC20Backed_hyperToken(
                params.name, // Name of the token
                params.symbol, // Symbol of the token
                params.decimals // Decimals of the token
            );
            IERC20Backed_HyperToken(hyperTokenAdd).init(
                motherChainInToken, // Set the mother chain ID
                params.name,
                params.symbol,
                params.decimals,
                params.backingToken, // Set the backing token address
                address(0), // Pool address will be set later
                wrappedNative, // Wrapped native token address
                linkToken, // Link token address
                hyperLinkToken // Hyperlink token address
            );
        }
        else if( params.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721 ) {
            // Create a  ERC721Backed_hyperToken instance
            hyperTokenAdd = IProtocolFactory(protocolFactory).createERC721Backed_hyperToken(
                params.name, // Name of the token
                params.symbol, // Symbol of the token
                params.decimals, // Decimals of the token
                params.backingToken, // Backing token address (ERC721 contract)
                params.tokenId // Token ID for the ERC721 token
            );
            IERC721Backed_HyperToken(hyperTokenAdd).init(
                motherChainInToken, // Set the mother chain ID
                params.name,
                params.symbol,
                params.decimals,
                params.backingToken, // Set the backing token address
                params.tokenId, // Set the token ID for the ERC721 token
                address(0), // Pool address will be set later
                wrappedNative, // Wrapped native token address
                linkToken, // Link token address
                hyperLinkToken // Hyperlink token address
            );
        } else {
            revert("Unknown token type");
        }

        emit Debug("deployHyperToken: ERC20Backed_hyperToken created");
        emit DebugBytes("deployHyperToken: hyperTokenAdd: ", abi.encodePacked(hyperTokenAdd));
       
        if( params.motherChainId != chainId) { //child: register data
            emit Debug("deployHyperToken: registering child hyperToken");                
          
            IHyperTokenManager(manager).saveHyperTokenInfo(
                hyperTokenAdd,
                params.name,
                params.symbol,
                params.decimals,
                params.tokenType,
                params.backingToken,
                params.tokenId,
                address(0), // Pool address will be set later
                params.motherChainId,
                params.chainSupply, // Total supply is set to the chain supply for child tokens
                params.tokenOwner
            );
        }
        else{   //else mother, already registered
            emit Debug("deployHyperToken: registering mother hyperToken");
            
            if(params.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20) {
                //transfer backing supply to token contract
                IERC20(params.backingToken).safeTransfer(
                    hyperTokenAdd, //backing token is held by token contract
                    params.chainSupply // Transfer the chain supply to the token contract
                ); // Transfer the backing token to this contract
            }
            else if(params.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721) {
                //transfer backing NFT to token contract
                IERC721(params.backingToken).safeTransferFrom(
                    address(this), // Transfer from this contract
                    hyperTokenAdd, //backing token is held by token contract
                    params.tokenId //token ID for the ERC721 token
                );
            }
        }
        //deploy pool
        deployCCIP_Pool(
            hyperTokenAdd, // HyperToken address
            params.motherChainId, // Mother chain ID
            params.decimals // Decimals of the token
        );

        uint256 amountToMint =
            params.motherChainId == chainId
                ? IHyperTokenManager(manager).getSupplyOnChain(
                    hyperTokenAdd,
                    params.motherChainId
                )
                : params.chainSupply; // Set the amount to mint based on the chain supply
        
        //mint the initial supply 
        IHyperToken(hyperTokenAdd).mint(
            params.tokenOwner,
            amountToMint // Mint the initial supply to the token owner
        );

        // Register the hyper token in the TokenAdminRegistry
        registerHyperToken(hyperTokenAdd);

        emit HyperTokenDeployed(hyperTokenAdd);

        return hyperTokenAdd;
    }


    function deployCCIP_Pool(
        address hyperTokenAdd,
        uint64 motherChainId,
        uint8 decimals
    ) internal returns (address) {  //Scope to avoid stack too deep error
        // Create a MinimalBnMPool instance
        address poolAddress = IProtocolFactory(protocolFactory).createMinimalBnMPool(
            hyperTokenAdd, // HyperToken address
            motherChainId, // Mother chain ID
            decimals // Decimals of the token
        );
        IMinimalBnMPool pool = IMinimalBnMPool(poolAddress);
        emit DebugBytes("deployHyperToken: MinimalBnMPool created: ", abi.encodePacked(address(pool)));

        pool.init(
            router, // Router address
            RMN // RMN address
        );
        IHyperToken(hyperTokenAdd).setPool(address(pool));

        // Enable the remote chains in the pool
        emit Debug("deployHyperToken: enabling remote chains in the pool");


        emit DebugBytes("deployHyperToken: number of enabled peer chains: ", abi.encodePacked(enabledPeerChains.length));
        for (uint256 i = 0; i < enabledPeerChains.length; i++) {
            emit DebugBytes("deployHyperToken: enabling remote chain: ", abi.encodePacked(enabledPeerChains[i]));
            uint64 chain = enabledPeerChains[i];
            // Set the onRamp and offRamp addresses for the remote chain
            pool.enableRemoteChain(chain);
        }
        
        return poolAddress;
    }

    function registerHyperToken(address hyperToken) internal{
        emit DebugBytes("registerHyperToken: hyperToken: ", abi.encodePacked(hyperToken));
        //begin regiser
        RegistryModuleOwnerCustom regMod = RegistryModuleOwnerCustom(regOwnerCustom);
        regMod.registerAdminViaGetCCIPAdmin(hyperToken);
        //Accept admin role
        ITokenAdminRegistry reg = ITokenAdminRegistry(tokenAdminRegistry); 
        reg.acceptAdminRole(hyperToken);

        // Set the pool for the hyper token
        reg.setPool( hyperToken, IHyperToken(hyperToken).getPool() );
    }

    function sendDeploymentToChain(
        address hyperToken,
        uint64 destChainId,
        uint256 _chainSupply,
        address feeToken,
        uint256 feeAmount,
        address CCIP_ackToken,
        uint256 CCIP_ackAmount
    ) external onlyManager {
        emit Debug("sendDeploymentToChain called");
        
        IHyperTokenManager.hyperTokenInfo memory info = IHyperTokenManager(manager).getHyperTokenInfo(hyperToken);
        
        if( info.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ) {
            IERC20(info.backingToken).safeTransferFrom(
                info.tokenOwner, // Transfer from the token owner
                address(this), //backing token is held by factory contract until hyperToken is deployed
                _chainSupply
            ); // Transfer the backing token to this contract
            //upgrade totalSupply
            IHyperTokenManager(manager).updateSupply(
                hyperToken,
                (_chainSupply + info.totalSupply) // Update the total supply for the hyper token
            );
        } else if (info.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721) {
            //transfer already done in motherchain, if it's child, don't needed
            //just upgrade totalSupply
            emit Debug("sendDeploymentToChain: HyperERC721 token type detected");
            IHyperTokenManager(manager).updateSupply(
                hyperToken,
                (_chainSupply + info.totalSupply) // Update the total supply for the hyper token
            );
        } else if (info.tokenType == CCHTTP_Types.HyperToken_Types.HyperNative) {
            //native is deployed by developer team
            //users will wrap and that will update supply
            //no upgrade in totalSupply to do
            emit Debug("sendDeploymentToChain: HyperNative token type detected");
        } else {
              revert("Unknown token type");
        }

        uint chainIdx = 0;
        // Check if chain is enabled
        for(uint256 i = 0; i < enabledPeerChains.length; i++) {
            if (enabledPeerChains[i] == destChainId) {
                // Chain is enabled
                chainIdx = i; // Store the index of the enabled chain
                break;
            }
            if (i == enabledPeerChains.length - 1) {
                revert("Chain not enabled");
            }
        }
        emit DebugBytes("sendDeploymentToChain: destChainId: ", abi.encodePacked(destChainId));
        emit DebugBytes("sendDeploymentToChain: hyperToken: ", abi.encodePacked(hyperToken));

        // Send the deployment to the specified chain
        //TODO: Implement the logic to send the deployment to the specified chain
        CCHTTP_Types.deployAndMintParams memory params = CCHTTP_Types.deployAndMintParams({
            chainId: destChainId,
            origin: address(this),
            destination: address(this), //EVM predictable address
            linkToken: linkToken,
            linkAmount: CCIP_ackAmount,
            feeToken: feeToken,
            feesAmount: feeAmount,
            name_length: uint8(bytes(info.name).length),
            name: info.name,
            symbol_length: uint8(bytes(info.symbol).length),
            symbol: info.symbol,
            decimals: info.decimals,
            deployer: info.tokenOwner,
            chainSupply: _chainSupply,
            expectedTokenAddress: hyperToken,
            tokenType: info.tokenType,
            backingToken: info.backingToken,
            tokenId: info.tokenId
        });

        cashInAndApproveFeesAndACK(
            feeToken,
            feeAmount,
            CCIP_ackToken,
            CCIP_ackAmount,
            CCHTTP_peer
        );

        ICCHTTP_Peer(CCHTTP_peer).deployAndMintRequest(
            params
        );
        
        // Emit an event to indicate that the deployment has been sent
        emit DeploymentSent(hyperToken, chainId);
    }



    function estimateDeploymentCost(
        address hyperToken,
        uint64 destChainId,
        address feeToken,
        address CCIP_ackToken
    ) public view returns (uint256 feeAmount, uint256 ackAmount) {
        IHyperTokenManager.hyperTokenInfo memory info = IHyperTokenManager(manager).getHyperTokenInfo(hyperToken);
        uint256 chainIdx = 0;
        // Check if the chain is enabled
        for (uint256 i = 0; i < enabledPeerChains.length; i++) {
            if (enabledPeerChains[i] == destChainId) {
                // Chain is enabled
                chainIdx = i; // Store the index of the enabled chain
                break;
            }
            if (i == enabledPeerChains.length - 1) {
                revert("Chain not enabled");
            }
        }

        CCHTTP_Types.deployAndMintParams memory params = CCHTTP_Types.deployAndMintParams({
            chainId: destChainId,
            origin: address(this),
            destination: address(this), // Assuming the destination is this contract
            linkToken: linkToken,
            linkAmount: 0, // This will be estimated later
            feeToken: feeToken,
            feesAmount: 0, // This will be estimated later
            name_length: uint8(bytes(info.name).length),
            name: info.name,
            symbol_length: uint8(bytes(info.symbol).length),
            symbol: info.symbol,
            decimals: info.decimals,
            deployer: info.tokenOwner,
            chainSupply: type(uint256).max, // Set a dummy chain supply for estimation
            expectedTokenAddress: hyperToken,
            tokenType: info.tokenType,
            backingToken: info.backingToken,
            tokenId: info.tokenId
        });

        // Estimate the fee amount for the deployment 
        // Call the CCHTTP_Peer to estimate the fee
        (feeAmount, ackAmount) = ICCHTTP_Peer(CCHTTP_peer).getFeesForDeployAndMint(
            params
        );
        
        return (feeAmount, ackAmount); 
    }


    function updateSupply(
        address hyperToken,
        int256 deltaSupply,
        address destination,
        address feeToken,
        uint256 feesAmount
    ) external returns (bool) {
        require(msg.sender == hyperToken, "Only the hyperToken can update supply");
        IHyperTokenManager.hyperTokenInfo memory info = IHyperTokenManager(manager).getHyperTokenInfo(hyperToken);
        require(info.hyperToken != address(0), "HyperToken does not exist");

        if (chainId == info.motherChainId) {
            // On Motherchain: update totalSupply 
            if(deltaSupply < 0) {
                require(uint256(-deltaSupply) <= info.totalSupply, "Insufficient total supply for update");
                uint256 absDeltaSupply = uint256(-deltaSupply);
                info.totalSupply -= absDeltaSupply; // Decrease the total supply
            }
            else {
                info.totalSupply += uint256(deltaSupply); // Increase the total supply
            }
            
            // Update the supply on the hyperToken contract
            IHyperToken(hyperToken).updateSupply(
                info.totalSupply,
                destination
            ); // Call the updateSupply function on the hyperToken contract

            IHyperTokenManager(manager).updateSupply(
                hyperToken,
                info.totalSupply // Update the total supply in the manager
            );
            emit Debug("updateSupply: Motherchain updated supply");
            return true;

        } else {
            // On child chain: send cross-chain request to Motherchain
            CCHTTP_Types.updateSupplyParams memory params = CCHTTP_Types.updateSupplyParams({
                chainId: info.motherChainId,
                feeToken: feeToken,
                feesAmount: feesAmount,
                amount: deltaSupply,
                hyperToken: hyperToken,
                destination: destination
            });
            cashInAndApproveFeesAndACK(
                feeToken,
                feesAmount,
                address(0),
                uint256(0),
                CCHTTP_peer
            );
            bool sent = ICCHTTP_Peer(CCHTTP_peer).updateSupplyRequest(params);
            emit Debug("updateSupply: Sent cross-chain updateSupplyRequest to Motherchain");
            return sent;
        }
    }


    //ICCHTTP_Consumer implementation
    function DeployAndMintReceived(
        uint64 origChain,
        CCHTTP_Types.deploy_and_mint_mssg memory params
    ) external override returns (bool) {
        uint256 gas = gasleft();
        emit DebugBytes("Gas left: ", abi.encodePacked(gas));
        require(msg.sender == CCHTTP_peer, "Not CCHTTP peer");
        // DEployment order received from peer chain
        //will deploy a child hyperToken
        
        emit Debug("DeployAndMintReceived: deploying hyperToken");
        if( params.tokenType == CCHTTP_Types.HyperToken_Types.HyperNative ) {
            // On child chain, we need to deploy the hyperNative
            address childHyperNative = _deployHyperNative(
                origChain, // The original chain where the hyperNative is from
                params.name,
                params.symbol,
                params.decimals,
                params.backingToken,
                params.deployer
            );

            emit Debug("DeployAndMintReceived: hyperNative deployed on child chain");
            registerHyperToken(childHyperNative); // Register the hyper token in the TokenAdminRegistry
        }
        else{
            // Create and init the hyperToken instance
            deployHyperToken(
                deployHyperTokenParams({
                    motherChainId: origChain, //mother chain id, is origin chain bc sends order
                    name: params.name,
                    symbol: params.symbol,
                    decimals: params.decimals,
                    backingToken: params.backingToken,
                    tokenId: params.tokenId, 
                    chainSupply: params.chainSupply,
                    tokenOwner: params.deployer,
                    tokenType: params.tokenType
                })
            );
            emit Debug("DeployAndMintReceived: hyperToken deployed on child chain");
        }
        emit Debug("DeployAndMintReceived: hyperToken deployed");
        
        return true;
    }

    function DeployAndMintConfirmed(
        uint64 origChain,
        CCHTTP_Types.deploy_and_mint_mssg memory params
    ) external override returns (bool) {
        emit Debug("DeployAndMintConfirmed called");
        
        address hyperToken = params.expectedTokenAddress;
        require(msg.sender == CCHTTP_peer, "Not CCHTTP peer");
        // Deployment confirmed by peer chain
        //will deploy a child hyperToken
        //mark deployment as done and not waiting
        uint256 chainIdx;
        
        IHyperTokenManager(manager).markDeploymentDone(
            hyperToken,
            origChain
        );
        if( params.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ||
            params.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721 ) {
            emit Debug("DeployAndMintConfirmed: hyperToken is ERC20 or ERC721");
            // For ERC20 and ERC721, we need to check if this is the last deployment
            // If this is the last deployment, we can deploy the hyperToken
            if( IHyperTokenManager(manager).isLastDeployment( hyperToken, origChain) ) {
                emit Debug("DeployAndMintConfirmed: last confirmation");
                deployHyperToken(
                    deployHyperTokenParams({
                        motherChainId: chainId, //mother chain id, is this chain bc receives confirmation
                        name: params.name,
                        symbol: params.symbol,
                        decimals: params.decimals,
                        backingToken: params.backingToken,
                        tokenId: params.tokenId, // For ERC20, tokenId is not used
                        chainSupply: params.chainSupply,
                        tokenOwner: params.deployer,
                        tokenType: params.tokenType
                    })
                );
            }
        }
        else if( params.tokenType == CCHTTP_Types.HyperToken_Types.HyperNative ) {
            if ( IHyperTokenManager(manager).isLastDeployment( hyperToken, origChain) ) {
                //native alreadycreated in deployHyperNative
                registerHyperToken(hyperToken); // Register the hyper token in the TokenAdminRegistry
                emit Debug("DeployAndMintConfirmed: last hyperNative deployment confirmed, registering hyperToken");
            }    
        }
        else {
            revert("Unknown token type");
        }
        return true;
    }

    function estimateUpdateSupplyCost(
        uint64 chain,
        address hyperToken,
        address feeToken // The fee token to be used for the update supply
    ) public view returns (uint256 feeAmount) {
        // Estimate the fee amount for the update supply
        // Check if the hyperToken exists
        
        // Prepare the update supply parameters
        CCHTTP_Types.updateSupplyParams memory params = CCHTTP_Types.updateSupplyParams({
            chainId: chain,
            feeToken: feeToken,
            feesAmount: 0, // This will be estimated later
            amount: 0, // The new supply to be set, can be set to 0 for estimation
            hyperToken: hyperToken,
            destination: address(this) //for estimation, we can use this contract address
        });

        // Call the CCHTTP_Peer to estimate the fee
        feeAmount = ICCHTTP_Peer(CCHTTP_peer).getFeesForUpdateSupply(
            params
        );
        return (feeAmount); // Just return the sum of fees for now
    }

    function UpdateTotalSupplyReceived(
        uint64 origChain,
        CCHTTP_Types.update_supply_mssg memory params
    ) external override returns (bool) {
        require(msg.sender == CCHTTP_peer, "Not CCHTTP peer");

        IHyperTokenManager.hyperTokenInfo memory info = IHyperTokenManager(manager).getHyperTokenInfo(params.hyperToken);

        emit Debug("UpdateTotalSupplyReceived");
        uint256 absAmount = uint256(params.amount < 0 ? -params.amount : params.amount);
        
        uint256 newSupply;
        uint256 oldSupply = info.totalSupply; // Get the current total supply of the hyper token
        
        if(params.amount < 0) {
            // If the amount is negative, we are reducing the supply
            require(
                oldSupply >= absAmount,
                "Insufficient supply to reduce"
            );
            emit Debug("UpdateTotalSupplyReceived: reducing supply");
            newSupply = oldSupply - absAmount; // Calculate the new supply by subtracting the absolute amount
        } else {
            // If the amount is positive, we are increasing the supply
            emit Debug("UpdateTotalSupplyReceived: increasing supply");
            newSupply = oldSupply + absAmount; // Calculate the new supply by adding the absolute
          // Get the current supply on the chain and add the absolute amount
        }

        IHyperTokenManager(manager).updateSupply(
            params.hyperToken,
            newSupply // Update the total supply for the hyper token
        ); // Call the updateTotalSupply function on the manager

        IHyperToken(params.hyperToken).updateSupply(
            newSupply,
            params.destination // Update the supply on the hyperToken contract
        ); // Call the updateSupply function on the hyperToken contract

        if( info.tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ||
        info.tokenType == CCHTTP_Types.HyperToken_Types.HyperNative ){
            IERC20Backed_HyperToken(params.hyperToken).releaseBacking(
                absAmount, // The amount to release    
                params.destination // Release the backing token to the destination address
            );
        }
        
        emit Debug("UpdateTotalSupplyReceived: done");
        return true;
    }
}
