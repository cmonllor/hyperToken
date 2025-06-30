//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IHyperToken} from "./IHyperToken.sol";

interface IERC721Backed_HyperToken is IHyperToken{
    function init(
        uint64 _motherChainId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address _backingToken,
        uint256 _backingNFT_Id,
        address _pool,
        address _wrappedNative,
        address _linkToken,
        address _hyperLinkToken,
        address _factory        
    ) external;

    function getBackingURI() external view returns (string memory);

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}