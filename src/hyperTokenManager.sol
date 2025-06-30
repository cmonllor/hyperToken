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


import { IProtocolFactory } from "./interfaces/IProtocolFactory.sol";
import { IHyperTokenFactory } from "./interfaces/IHyperTokenFactory.sol";
import { IHyperTokenManager } from "./interfaces/IHyperTokenManager.sol";
import { ICCHTTP_Consumer } from "./interfaces/ICCHTTP_Consumer.sol";
import { ICCHTTP_Peer } from "./interfaces/ICCHTTP_Peer.sol";
import { IHyperToken } from "./interfaces/IHyperToken.sol";

import { FeesManager } from "./FeesManager.sol";
import { HyperToken } from "./hyperToken.sol";

import { ICCHTTP_Peer } from "./CCHTTP_Peer.sol";
import { CCHTTP_Types } from "./CCHTTP_Types.sol";

contract HyperTokenManager is IHyperTokenManager, FeesManager, Ownable {
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

    address prot_factory;
    address hT_factory; // HyperTokenFactory address

    address public hyperNativeToken;

    uint64[] public enabledPeerChains; // List of enabled peer chains
    

    mapping (address hT => hyperTokenInfo) public hyperTokens;

    mapping (address erc20 => address) public ERC20Backed_hyperTokens;
    mapping (uint64 chainId => address) public hyperNativeChildren; // Mapping of child hyperNative tokens by motherchain ID
    mapping (address erc721 => mapping (uint256 id => address hT )) public ERC721Backed_hyperTokens;


    modifier onlyFactory() {
        require(msg.sender == hT_factory, "Only factory can call this function");
        _;
    }

    modifier onlyHyperTokenOwner(address hyperToken) {
        require(hyperTokens[hyperToken].tokenOwner == msg.sender, "Only hyper token owner can call this function");
        _;
    }


    constructor( address protocolDeployer ) Ownable() {
        transferOwnership(protocolDeployer);
        prot_factory = msg.sender;
    }

    function init(
        uint64 _chainId, 
        address _router,
        address _linkToken,
        address _wrappedNative,
        string calldata _nativeName,
        string calldata _nativeSymbol,
        uint8 _nativeDecimals,
        address _hyperTokenFactory
    ) external onlyOwner {
        chainId = _chainId;
        router = _router;
        linkToken = _linkToken;

        wrappedNative = payable(_wrappedNative);
        nativeName = _nativeName;
        nativeSymbol = _nativeSymbol;
        nativeDecimals = _nativeDecimals;

        hT_factory = _hyperTokenFactory;
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

    function setHyperNative( address _hyperNativeToken ) external onlyFactory {
        require( _hyperNativeToken != address(0), "HyperNative token address cannot be zero" );
        hyperNativeToken = _hyperNativeToken;
    }


    function saveHyperTokenInfo(
        address hyperToken,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        CCHTTP_Types.HyperToken_Types tokenType, // Type of the hyper token (ERC20, ERC721, etc.)
        address backingToken,
        uint256 tokenId, // For ERC721, the token ID
        address pool,
        uint64 motherChainId,
        uint256 totalSupply, // Total supply across all chains
        address tokenOwner
    ) external onlyFactory {
        hyperTokens[hyperToken].hyperToken = hyperToken;
        hyperTokens[hyperToken].name = name;
        hyperTokens[hyperToken].symbol = symbol;
        hyperTokens[hyperToken].decimals = decimals;
        hyperTokens[hyperToken].tokenType = tokenType; // Type of the hyper token
        hyperTokens[hyperToken].backingToken = backingToken;
        hyperTokens[hyperToken].tokenId = tokenId; // For ERC721, the
        hyperTokens[hyperToken].pool = pool== address(0) ? 
                IProtocolFactory(prot_factory).estimatePoolAddress(hyperToken, motherChainId, decimals) : 
                pool; // If pool is not provided, estimate it
        hyperTokens[hyperToken].motherChainId = motherChainId;
        hyperTokens[hyperToken].totalSupply = totalSupply; // Total supply across all chains
        hyperTokens[hyperToken].tokenOwner = tokenOwner;

        if( tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ) {
            emit DebugBytes("saveHyperTokenInfo: HyperERC20 token saved: ", abi.encodePacked(hyperToken));
            ERC20Backed_hyperTokens[backingToken] = hyperToken;
        } else if (tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721) {
            ERC721Backed_hyperTokens[backingToken][tokenId] = hyperToken;
            emit DebugBytes("saveHyperTokenInfo: HyperERC721 token saved: ", abi.encodePacked(hyperToken));
        } else if (tokenType == CCHTTP_Types.HyperToken_Types.HyperNative) {
            emit DebugBytes("saveHyperTokenInfo: HyperNative token saved: ", abi.encodePacked(hyperToken));
            if( motherChainId == chainId ) {
                // If the hyperNative token is in the mother chain, save it
                hyperNativeToken = hyperToken;
            } else {
                // If the hyperNative token is in a peer chain, save it in the mapping
                hyperNativeChildren[motherChainId] = hyperToken;
            }
        } 
    }


    function startHyperToken(
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId,   
        uint256 _chainSupply,
        CCHTTP_Types.HyperToken_Types tokenType
    ) external payable returns (address) {
        require(
            _backingToken != wrappedNative,
            "hyperNative deploy reserved to protocol owner"
        );
        require(
            _backingToken != linkToken,
            "hyperLink deploy reserved to protocol owner"
        );

        if( tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ) {
            require( ERC20Backed_hyperTokens[_backingToken] == address(0), "HyperToken already exists for this backing token" );
            require( IERC20(_backingToken).balanceOf(msg.sender) >= _chainSupply, "Insufficient balance of backing token" );
            require( IERC20(_backingToken).allowance(msg.sender, address(this)) >= _chainSupply, "Insufficient allowance for backing token" );
        } else if (tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721) {
            require(IERC721(_backingToken).ownerOf(tokenId) == msg.sender, "You do not own the ERC721 token");
            require(IERC721(_backingToken).getApproved(tokenId) == address(this) 
                || IERC721(_backingToken).isApprovedForAll(msg.sender, address(this)), 
                "Not approved to transfer the ERC721 token"
            );
        } else if (tokenType == CCHTTP_Types.HyperToken_Types.HyperNative) {
            // User can send native or WETH as backing token
            revert("HyperNative tokens cannot be started with this function, use deployHyperNative instead");
        } else {
            revert("Unknown token type");
        }
        
        address hyperTokenAdd;
        if( tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721 ) { 
            hyperTokenAdd = IProtocolFactory(prot_factory).estimateHyperERC721Address(
                _name, // Name of the token
                _symbol, // Symbol of the token
                _decimals, // Decimals of the token
                _backingToken, // Backing token address (ERC721 contract)
                tokenId // Token ID for the ERC721 token
            );
        }
        else{
            hyperTokenAdd = IProtocolFactory(prot_factory).estimateTokenAddress(
                _name, // Name of the token
                _symbol, // Symbol of the token
                _decimals // Decimals of the token
            );
        }
        emit DebugBytes("startHyperToken: estimated address: ", abi.encode(hyperTokenAdd));
        address expectedPoolAddress = IProtocolFactory(prot_factory).estimatePoolAddress(
            hyperTokenAdd, // HyperToken address
            chainId, // Mother chain ID
            _decimals // Decimals of the token
        );
        
        hyperTokens[hyperTokenAdd].hyperToken = hyperTokenAdd;
        hyperTokens[hyperTokenAdd].name = _name;
        hyperTokens[hyperTokenAdd].symbol = _symbol;
        hyperTokens[hyperTokenAdd].decimals = _decimals;
        hyperTokens[hyperTokenAdd].tokenType = tokenType; // Type of the hyper
        hyperTokens[hyperTokenAdd].backingToken = _backingToken;
        hyperTokens[hyperTokenAdd].tokenId = tokenId; // For ERC721,
        hyperTokens[hyperTokenAdd].pool = expectedPoolAddress; // If pool is not provided, estimate it
        hyperTokens[hyperTokenAdd].motherChainId = chainId; // Set the mother
        hyperTokens[hyperTokenAdd].totalSupply = _chainSupply; // Total supply across all chains
        hyperTokens[hyperTokenAdd].tokenOwner = msg.sender; // Token owner is the caller

        // Register the hyper token in the appropriate mapping
        if (
            tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 
        ) {
            ERC20Backed_hyperTokens[_backingToken] = hyperTokenAdd;
        } else if (tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721) {
            ERC721Backed_hyperTokens[_backingToken][tokenId] = hyperTokenAdd;
        }
        
        // Transfer the backing token to hyperTokenFactory
        if( tokenType == CCHTTP_Types.HyperToken_Types.HyperERC20 ) {
            IERC20(_backingToken).safeTransferFrom(
                msg.sender,
                hT_factory, 
                _chainSupply
            ); 
        }
        else if( tokenType == CCHTTP_Types.HyperToken_Types.HyperERC721 ) {
            // For ERC721, transfer the token to the factory
            IERC721(_backingToken).safeTransferFrom(
                msg.sender,
                hT_factory, 
                tokenId
            );
        }

        deployment memory initialDeployment; //in this chain
        initialDeployment.chainId = chainId; // Set the chain ID for the deployment
        initialDeployment.chainSupply = _chainSupply; // Set the chain supply for the deployment
        initialDeployment.waiting = false; // Initially waiting for confirmation
        hyperTokens[hyperTokenAdd].deployments.push(initialDeployment);
        emit Debug("startHyperToken: HyperToken deployment initialized in  mother chain");

        //prepare a deployment for each peer chain
        for (uint256 i = 0; i < enabledPeerChains.length; i++) {
            uint64 chain = enabledPeerChains[i];
            // Create a deployment for each enabled peer chain
            deployment memory deploymentInfo;
            deploymentInfo.chainId = chain; // Set the chain ID for the deployment
            deploymentInfo.chainSupply = 0; // Initially set to 0, will be updated later
            deploymentInfo.waiting = true; // Initially not waiting for confirmation
            hyperTokens[hyperTokenAdd].deployments.push(deploymentInfo);
            emit DebugBytes("startHyperToken: added deployment for peer chain: ", abi.encodePacked(chain));
        }
        // Emit an event to indicate that the HyperToken has been started
        emit HyperTokenStarted(hyperTokenAdd);
        return hyperTokenAdd;
    }


    function estimatePoolAddress(
        address hyperToken,
        uint64 motherChain,
        uint8 decimals
    ) external view returns (address) {
        return IProtocolFactory(prot_factory).estimatePoolAddress(
            hyperToken,
            motherChain,
            decimals
        );
    }


    // Deterministic address calculation for the proxy
    function estimateTokenAddress(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal view returns (address) {
        return IProtocolFactory(prot_factory).estimateTokenAddress(
            _name, // Name of the token
            _symbol, // Symbol of the token
            _decimals // Decimals of the token
        );
    }


    function estimateHyperERC721Address(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId
    ) internal view returns (address) {
        return IProtocolFactory(prot_factory).estimateHyperERC721Address(
            _name, // Name of the token
            _symbol, // Symbol of the token
            _decimals, // Decimals of the token
            _backingToken, // Backing token address (ERC721 contract)
            tokenId // Token ID for the ERC721 token
        );
    }


    function _hyperTokenSalt(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_name, _symbol, _decimals));
    }


    function _hyperERC721Salt(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_name, _symbol, _decimals, _backingToken, tokenId));
    }


    function getHyperTokenInfo(address hyperToken) external view returns (hyperTokenInfo memory) {
        return hyperTokens[hyperToken];
    }


    function getDeploymentIndex(
        address hyperToken,
        uint64 chain
    ) public view returns (uint256) {
        for (uint256 i = 0; i < hyperTokens[hyperToken].deployments.length; i++) {
            if (hyperTokens[hyperToken].deployments[i].chainId == chain) {
                return i;
            }
        }
        revert("Deployment not found for the specified chain ID");
    }

    function deployHyperNative() external onlyOwner {
        emit DebugBytes("deployHyperNative: deploying hyperNative token", abi.encodePacked(msg.sender));
        emit DebugBytes("deployHyperNative: factory owner: ", abi.encodePacked(owner()));
        string memory hN_name = string( abi.encodePacked("hyper_", nativeName ) );
        string memory hN_symbol = string( abi.encodePacked("h", nativeSymbol ) );
        IHyperTokenFactory(hT_factory).deployHyperNative(
            chainId, // Set the mother chain ID
            hN_name, // Set the name of the token
            hN_symbol, // Set the symbol of the token
            nativeDecimals, // Set the decimals of the token
            wrappedNative, // Wrapped native token address
            msg.sender // Token owner is the contract deployer
        );
        // Save the hyperNative token info in the mapping
        hyperTokens[hyperNativeToken].hyperToken = hyperNativeToken;
        hyperTokens[hyperNativeToken].name = hN_name;
        hyperTokens[hyperNativeToken].symbol = hN_symbol;
        hyperTokens[hyperNativeToken].decimals = nativeDecimals;
        hyperTokens[hyperNativeToken].tokenType = CCHTTP_Types.HyperToken_Types.HyperNative; // Type of the hyper token
        hyperTokens[hyperNativeToken].backingToken = wrappedNative; // Wrapped native token address
        hyperTokens[hyperNativeToken].tokenId = 0; // No token ID for native tokens
        hyperTokens[hyperNativeToken].pool = IProtocolFactory(prot_factory).estimatePoolAddress(
            hyperNativeToken, // HyperNative token address
            chainId, // Mother chain ID
            nativeDecimals // Decimals of the token
        );
        hyperTokens[hyperNativeToken].motherChainId = chainId; // Set the mother
        hyperTokens[hyperNativeToken].totalSupply = 0; // Total supply across all chains
        hyperTokens[hyperNativeToken].tokenOwner = msg.sender; // Token owner is the contract deployer
        
        //prepare a deployment in the mother chain
        deployment memory initialDeployment; //in this chain
        initialDeployment.chainId = chainId; // Set the chain ID for the deployment
        initialDeployment.chainSupply = 0; // Initially set to 0
        initialDeployment.waiting = true; // Initially not waiting for confirmation
        hyperTokens[hyperNativeToken].deployments.push(initialDeployment);
        emit Debug("deployHyperNative: HyperNative deployment initialized in mother chain");

        //prepare a deployment for each peer chain
        for (uint256 i = 0; i < enabledPeerChains.length; i++) {
            uint64 chain = enabledPeerChains[i];
            // Create a deployment for each enabled peer chain
            deployment memory deploymentInfo;
            deploymentInfo.chainId = chain; // Set the chain ID for the deployment
            deploymentInfo.chainSupply = 0; // Initially set to 0, will be updated later
            deploymentInfo.waiting = true; // Initially not waiting for confirmation
            hyperTokens[hyperNativeToken].deployments.push(deploymentInfo);
            emit DebugBytes("deployHyperNative: added deployment for peer chain: ", abi.encodePacked(chain));
        }
        emit Debug("deployHyperNative: hyperNative started");
    }


    function deployHyperTokenInChain(
        address hyperToken,
        uint64 chain,
        uint256 chainSupply,
        address feeToken,
        uint256 feeAmount,
        address ackToken,
        uint256 ackAmount
    ) external onlyHyperTokenOwner(hyperToken) {
        // This function will be called by the user who called startHyperToken
        // It will deploy the token and save info in hyperTokens[hyperToken].deployments
        // It will also emit an event HyperTokenDeployed

        cashInAndApproveFeesAndACK(
            feeToken,
            feeAmount,
            ackToken,
            ackAmount,
            hT_factory
        );
        IHyperTokenFactory(hT_factory).sendDeploymentToChain(
            hyperToken,
            chain,
            chainSupply,
            feeToken,
            feeAmount,
            ackToken,
            ackAmount
        );

        emit DeploymentSent(hyperToken, chain);

        // Update the deployment info for the specified chain
        uint256 deploymentIndex = getDeploymentIndex(hyperToken, chain);
        emit DebugBytes("deployHyperTokenInChain: deployment index: ", abi.encodePacked(deploymentIndex));
        emit DebugBytes("deployHyperTokenInChain: chain ID: ", abi.encodePacked(chain));
        emit DebugBytes("deployHyperTokenInChain: chain supply: ", abi.encodePacked(chainSupply));
        
        hyperTokens[hyperToken].deployments[deploymentIndex].chainId = chain; // Set the chain ID for the deployment
        hyperTokens[hyperToken].deployments[deploymentIndex].chainSupply += chainSupply; // Set the chain supply for the deployment
        hyperTokens[hyperToken].deployments[deploymentIndex].waiting = true; // Initially waiting for confirmation        
        emit DebugBytes("deployHyperTokenInChain: deployment info updated for chain: ", abi.encodePacked(chain));
        emit DebugBytes("deployHyperTokenInChain: waiting status: ", abi.encodePacked(hyperTokens[hyperToken].deployments[deploymentIndex].waiting));
    }

    
    function markDeploymentDone(
        address hyperToken,
        uint64 chain
    ) external onlyFactory {
        // This function will be called by the factory when the deployment is done
        // It will update the deployment info for the specified chain
        uint256 deploymentIndex = getDeploymentIndex(hyperToken, chain);
        emit DebugBytes("markDeploymentDone: deployment index: ", abi.encodePacked(deploymentIndex));
        hyperTokens[hyperToken].deployments[deploymentIndex].waiting = false; // Mark as done
        emit DebugBytes("markDeploymentDone: deployment for chain: ", abi.encodePacked(chain));
        emit DebugBytes("markDeploymentDone: waiting status: ", abi.encodePacked(hyperTokens[hyperToken].deployments[deploymentIndex].waiting));
        emit DeploymentReceived(hyperToken, chain);
    }


    function isLastDeployment(
        address hyperToken,
        uint64 chain
    ) external /*view*/ onlyFactory returns (bool) {
        // Check if the last deployment for the specified chain is waiting
        for( uint256 i = 0; i < hyperTokens[hyperToken].deployments.length; i++) {
            if (
                hyperTokens[hyperToken].deployments[i].chainId == chainId || // Skip the mother chain deployment
                hyperTokens[hyperToken].deployments[i].chainId != chain // Skip if the chain ID does not match the specified chain
            ) {
                emit DebugBytes("isLastDeployment: skipping check deployment for chain: ", abi.encodePacked(chain));
                continue;
            }
            emit DebugBytes("isLastDeployment: checking deployment for chain: ", abi.encodePacked(hyperTokens[hyperToken].deployments[i].chainId));
            emit DebugBytes("isLastDeployment: waiting status: ", abi.encodePacked(hyperTokens[hyperToken].deployments[i].waiting));
            if (hyperTokens[hyperToken].deployments[i].waiting) {
                // If any deployment for the specified chain is still waiting, return false
                return false;
            }
        }
        // If all deployments for the specified chain are done, return true
        return true;
    }

    function getSupplyOnChain(
        address hyperToken,
        uint64 chain
    ) external view returns (uint256) {
        //Just for tokens in motherChain
        require(chainId == hyperTokens[hyperToken].motherChainId, "Only in Motherchain");
        // Get the supply for the specified chain
        uint256 deploymentIndex = getDeploymentIndex(hyperToken, chain);
        return hyperTokens[hyperToken].deployments[deploymentIndex].chainSupply;
    }

    function getTotalSupply(
        address hyperToken
    ) external view returns (uint256) {
        // Get the total supply across all chains
        return hyperTokens[hyperToken].totalSupply;
    }


    function updateSupply(
        address hyperToken,
        uint256 newSupply
    ) external onlyFactory {
        // Update the total cross chain supply 
        uint256 oldSupply = hyperTokens[hyperToken].totalSupply;
        if( hyperTokens[hyperToken].motherChainId == chainId ) {
            // If the hyper token is in the mother chain, update the supply directly
            hyperTokens[hyperToken].totalSupply = newSupply;
        
            emit DebugBytes("updateSupply: old supply: ", abi.encodePacked(oldSupply));
            emit DebugBytes("updateSupply: new supply: ", abi.encodePacked(newSupply));       
        }
    }


    function estimateDeploymentCost(
        address hyperToken,
        uint64 destChainId,
        address feeToken,
        address ackToken
    ) external view returns (uint256 feeAmount, uint256 ackAmount) {
        // Estimate the cost of deploying the hyper token to the specified chain
        // This will depend on the fee token and the ack token
        return IHyperTokenFactory(hT_factory).estimateDeploymentCost(
            hyperToken,
            destChainId,
            feeToken,
            ackToken
        );
    }


    function estimateUpdateSupplyCost(
        uint64 chain,
        address hyperToken,
        address feeToken
    ) external view returns (uint256) {
        // Estimate the cost of updating the supply of the hyper token on the specified chain
        return IHyperTokenFactory(hT_factory).estimateUpdateSupplyCost(
            chain,
            hyperToken,
            feeToken
        );
    }


}