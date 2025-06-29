//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IHyperToken} from "./IHyperToken.sol";

interface IERC20Backed_HyperToken is IHyperToken{
    function init(
        uint64 _motherChainId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address _backingToken,
        address _pool,
        address _wrappedNative,
        address _linkToken,
        address _hyperLinkToken
    ) external;

    function wrap(
        uint256 amount
    ) external; 

    function releaseBacking(
        uint256 amount,
        address to
    ) external;
}