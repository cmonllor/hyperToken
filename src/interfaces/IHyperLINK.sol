//SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IHyperToken} from "./IHyperToken.sol";

interface IHyperLINK is IHyperToken {
    function init(
        uint64 _motherChainId,
        address _linkToken
    ) external;

    function setLinkPool(address _linkPool) external;

    function getLinkPool() external view returns (address);

    function wrapLink(uint256 amount) external;

    function unwrapLink(uint256 amount) external;
}