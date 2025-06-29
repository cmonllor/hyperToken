//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { CCHTTP_Types } from "../CCHTTP_Types.sol";

interface IHyperTokenFactory {
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
        address _hyperTokenManager    
    ) external;


    function enablePeerChain(
        uint64 chain
    ) external;


    function deployHyperLINK() external;

    function deployHyperNative(
        uint64 motherChainId,
        string calldata _nativeName,
        string calldata _nativeSymbol,
        uint8 _nativeDecimals,
        address _backingToken,
        address tokenOwner
    ) external returns (address);

    function onERC721Received(
        address op,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);

    
    function sendDeploymentToChain(
        address hyperToken,
        uint64 destChainId,
        uint256 chainSupply,
        address feeToken,
        uint256 feeAmount,
        address CCIP_ackToken,
        uint256 CCIP_ackAmount
    ) external;


    function estimateDeploymentCost(
        address hyperToken,
        uint64 destChainId,
        address feeToken,
        address CCIP_ackToken
    ) external view returns (uint256, uint256);


    function updateSupply(
        address hyperToken,
        int256 deltaSupply,
        address destination,
        address feeToken,
        uint256 feeAmount
    ) external returns (bool);

    function estimateUpdateSupplyCost(
        uint64 chain,
        address hyperToken,
        address feeToken
    ) external view returns (uint256);
}
        