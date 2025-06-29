//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CCHTTP_Types } from "../CCHTTP_Types.sol";


interface IHyperTokenManager {
    struct hyperTokenInfo {
        address hyperToken;
        string name;
        string symbol;
        uint8 decimals;
        CCHTTP_Types.HyperToken_Types tokenType; // Type of the hyper token (ERC20, ERC721, etc.)
        address backingToken;
        uint256 tokenId; // For ERC721, the token ID
        address pool;
        uint64 motherChainId;
        uint256 totalSupply; // Total supply across all chains
        deployment [] deployments;
        address tokenOwner;
    }


    struct deployment {
        uint64 chainId;
        uint256 chainSupply;
        bool waiting;
    }


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



    function init(
        uint64 _chainId,
        address _router,
        address _linkToken,
        address _wrappedNative,
        string calldata _nativeName,
        string calldata _nativeSymbol,
        uint8 _nativeDecimals,
        address _hyperTokenFactory
    ) external;

    function enablePeerChain(
        uint64 chain
    ) external;


    function setHyperNative(
        address _hyperNative
    ) external;


    function saveHyperTokenInfo(
        address hyperToken,
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        CCHTTP_Types.HyperToken_Types hyperTokenType,
        address backingToken,
        uint256 tokenId,
        address pool,
        uint64 motherChainId,
        uint256 totalSupply,
        address tokenOwner
    ) external;

    function startHyperToken(
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        address _backingToken,
        uint256 tokenId,
        uint256 _chainSupply,
        CCHTTP_Types.HyperToken_Types _hyperTokenType
    ) external payable returns (address);

    function getHyperTokenInfo(
        address hyperToken
    ) external view returns (hyperTokenInfo memory);

    function getDeploymentIndex(
        address hyperToken,
        uint64 chainId
    ) external view returns (uint256);

    function deployHyperNative() external;

    function hyperNativeToken() external view returns (address);
    
    function deployHyperTokenInChain(
        address hyperToken,
        uint64 chainId,
        uint256 chainSupply,
        address feeToken,
        uint256 feeAmount,
        address ackToken,
        uint256 ackAmount
    ) external;

    function markDeploymentDone(
        address hyperToken,
        uint64 chainId
    ) external;


    function isLastDeployment(
        address hyperToken,
        uint64 chainId
    ) external view returns (bool);


    function getSupplyOnChain(
        address hyperToken,
        uint64 chainId
    ) external view returns (uint256);

    function getTotalSupply(
        address hyperToken
    ) external view returns (uint256);

    function updateSupply(
        address hyperToken,
        uint256 newSupply
    ) external;

    function estimateDeploymentCost(
        address hyperToken,
        uint64 destChainId,
        address feeToken,
        address CCIP_ackToken
    ) external view returns (uint256, uint256);

    function estimateUpdateSupplyCost(
        uint64 chain,
        address hyperToken,
        address feeToken
    ) external returns (uint256);
}